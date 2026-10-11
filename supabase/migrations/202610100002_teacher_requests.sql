-- Password authentication remains entirely in Supabase Auth.
-- This migration stores private account requests and bounded teacher approval only.
begin;
create table if not exists public.school_teacher_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 120),
  requested_groups text[] not null,
  note text not null default '' check (length(note) <= 2000),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  approved_groups text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null
);
create unique index if not exists school_teacher_one_pending_request
  on public.school_teacher_requests(user_id) where status='pending';
alter table public.school_teacher_requests enable row level security;
drop policy if exists school_teacher_requests_read on public.school_teacher_requests;
create policy school_teacher_requests_read on public.school_teacher_requests
  for select to authenticated using (user_id=(select auth.uid()) or (select school_private.is_leadership()));
revoke all on public.school_teacher_requests from public,anon,authenticated;
grant select on public.school_teacher_requests to authenticated;

create or replace function school_private.validate_teacher_groups(p_groups text[])
returns void language plpgsql stable security definer set search_path = '' as $$
declare v_document jsonb;
begin
  select s.document into v_document from public.school_versions s order by s.revision desc limit 1;
  if p_groups is null or coalesce(cardinality(p_groups),0) not between 1 and 50 or
    cardinality(p_groups) <> (select count(distinct g) from unnest(p_groups) g) or
    exists(select 1 from unnest(p_groups) g where g is null or g='*' or
      not coalesce(v_document->'groups' ? g,false) or coalesce(v_document->'archivedGroups','[]') ? g) then
    raise exception 'Teacher access requires unique active class groups; schoolwide scope is not allowed' using errcode='22023';
  end if;
end; $$;
revoke all on function school_private.validate_teacher_groups(text[]) from public,anon,authenticated;

create or replace function public.request_teacher_access(p_name text,p_groups text[],p_note text default '')
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if auth.uid() is null or not exists(select 1 from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null) then
    raise exception 'Sign in with a verified email account before requesting teacher access' using errcode='42501';
  end if;
  if exists(select 1 from public.school_members m where m.user_id=auth.uid() and m.active) then
    raise exception 'This account already has approved staff access' using errcode='42501';
  end if;
  if coalesce(length(trim(p_name)),0) not between 1 and 120 or p_note is null or length(p_note)>2000 then
    raise exception 'Provide your name and a note of at most 2000 characters' using errcode='22023';
  end if;
  perform school_private.validate_teacher_groups(p_groups);
  insert into public.school_teacher_requests(user_id,name,requested_groups,note)
    values(auth.uid(),trim(p_name),p_groups,p_note)
    on conflict(user_id) where status='pending' do update
      set name=excluded.name,requested_groups=excluded.requested_groups,note=excluded.note,updated_at=now()
    returning id into v_id;
  insert into public.school_audit_events(actor,action,details)
    values(auth.uid(),'teacher.request',jsonb_build_object('requestId',v_id));
  return v_id;
end; $$;

create or replace function public.review_teacher_access(p_id uuid,p_approve boolean,p_groups text[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_request public.school_teacher_requests; v_result jsonb; v_existing_role text;
begin
  if not school_private.is_leadership() then
    raise exception 'Only Developer, Principal or Vice Principal may review teacher requests' using errcode='42501';
  end if;
  if p_approve is null then raise exception 'Choose approve or reject' using errcode='22023'; end if;
  select * into v_request from public.school_teacher_requests r where r.id=p_id for update;
  if v_request.id is null or v_request.status<>'pending' then
    raise exception 'Pending teacher request not found' using errcode='22023';
  end if;
  if p_approve then
    perform school_private.validate_teacher_groups(p_groups);
    if not exists(select 1 from auth.users u where u.id=v_request.user_id and u.email_confirmed_at is not null) then
      raise exception 'Requester email must remain verified' using errcode='42501';
    end if;
    -- Serialize staff grants with the same account's ordinary Developer grant API.
    perform pg_advisory_xact_lock(hashtextextended(v_request.user_id::text,81277));
    select m.role into v_existing_role from public.school_members m where m.user_id=v_request.user_id for update;
    if v_existing_role is not null and v_existing_role<>'teacher' then
      raise exception 'Teacher review cannot replace a privileged staff role' using errcode='42501';
    end if;
    insert into public.school_members(user_id,role,capabilities,groups,active)
      values(v_request.user_id,'teacher',array['notices.submit']::text[],p_groups,true)
      on conflict(user_id) do update set role='teacher',capabilities=array['notices.submit']::text[],
        groups=excluded.groups,active=true,updated_at=now();
  end if;
  update public.school_teacher_requests r set status=case when p_approve then 'approved' else 'rejected' end,
    approved_groups=case when p_approve then p_groups else '{}'::text[] end,
    reviewed_at=now(),reviewed_by=auth.uid(),updated_at=now()
    where r.id=p_id returning to_jsonb(r.*) into v_result;
  insert into public.school_audit_events(actor,action,details) values(auth.uid(),'teacher.review',jsonb_build_object(
    'requestId',p_id,'userId',v_request.user_id,'approved',p_approve,'groups',case when p_approve then p_groups else '{}'::text[] end));
  return v_result;
end; $$;
revoke all on function public.request_teacher_access(text,text[],text),public.review_teacher_access(uuid,boolean,text[]) from public,anon,authenticated;
grant execute on function public.request_teacher_access(text,text[],text),public.review_teacher_access(uuid,boolean,text[]) to authenticated;

-- Keep the existing Developer-only general grant API unchanged in authority,
-- and serialize grants against bounded teacher approvals on the same account.
create or replace function public.set_school_member(p_user_id uuid,p_role text,p_capabilities text[],p_groups text[],p_active boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor public.school_members; v_result jsonb; v_groups jsonb;
begin
  select * into v_actor from public.school_members m where m.user_id=auth.uid() and m.active;
  if v_actor.role is distinct from 'developer' then raise exception 'Only Developer can grant or change membership' using errcode='42501'; end if;
  if p_user_id=auth.uid() then raise exception 'Developer cannot change their own membership through this API' using errcode='42501'; end if;
  if p_role not in ('developer','principal','teacher','codeveloper') or p_capabilities is null or p_groups is null or p_active is null or
    not p_capabilities <@ array['schedules.manage','classes.manage','subjects.manage','calendar.manage','substitutions.manage','notices.submit','notices.publish','banners.manage']::text[] then
    raise exception 'Invalid role or capability' using errcode='22023';
  end if;
  if p_role='teacher' and not p_capabilities <@ array['notices.submit']::text[] then raise exception 'Teacher grants are limited to notice submissions' using errcode='22023'; end if;
  select s.document->'groups' into v_groups from public.school_versions s order by s.revision desc limit 1;
  if exists(select 1 from unnest(p_groups) g where g is null or (g<>'*' and not (v_groups ? g))) or ('*'=any(p_groups) and p_role='teacher') then
    raise exception 'Invalid group scope' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,81277));
  insert into public.school_members(user_id,role,capabilities,groups,active) values(p_user_id,p_role,p_capabilities,p_groups,p_active)
    on conflict(user_id) do update set role=excluded.role,capabilities=excluded.capabilities,groups=excluded.groups,active=excluded.active,updated_at=now()
    returning to_jsonb(school_members.*) into v_result;
  insert into public.school_audit_events(actor,action,details) values(auth.uid(),'member.change',jsonb_build_object('userId',p_user_id,'role',p_role,'capabilities',p_capabilities,'groups',p_groups,'active',p_active));
  return v_result;
end; $$;
-- CREATE OR REPLACE preserves existing privileges, but restate the bounded grant.
revoke all on function public.set_school_member(uuid,text,text[],text[],boolean) from public,anon,authenticated;
grant execute on function public.set_school_member(uuid,text,text[],text[],boolean) to authenticated;
commit;
