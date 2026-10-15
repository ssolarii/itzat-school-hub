begin;

alter table public.school_teacher_requests add column requested_teaching jsonb not null default '[]'::jsonb check(jsonb_typeof(requested_teaching)='array' and jsonb_array_length(requested_teaching)<=100);
create table public.teacher_subject_links (
 teacher_id uuid not null references auth.users(id) on delete cascade,
 subject text not null,
 class_group text not null,
 approved_by uuid references auth.users(id) on delete set null,
 updated_at timestamptz not null default now(),
 primary key(teacher_id,subject,class_group)
);
create table public.teacher_checkouts (
 id uuid primary key default gen_random_uuid(),
 teacher_id uuid not null references auth.users(id) on delete cascade,
 date date not null,
 sessions integer[] not null check(cardinality(sessions) between 1 and 6 and sessions<@array[1,2,3,4,5,6]),
 cancelled_at timestamptz,
 updated_at timestamptz not null default now(),
 unique(teacher_id,date)
);
alter table public.teacher_subject_links enable row level security;
alter table public.teacher_checkouts enable row level security;
revoke all on public.teacher_subject_links,public.teacher_checkouts from public,anon,authenticated;
grant select on public.teacher_subject_links,public.teacher_checkouts to authenticated;
create policy teacher_links_read on public.teacher_subject_links for select to authenticated using(teacher_id=auth.uid() or school_private.is_leadership());
create policy teacher_checkouts_read on public.teacher_checkouts for select to authenticated using(teacher_id=auth.uid() or school_private.is_leadership());

create function school_private.validate_teaching_links(p_links jsonb,p_groups text[]) returns void language plpgsql stable security definer set search_path='' as $$
declare v_document jsonb; v_link jsonb;
begin
 select document into v_document from public.school_versions order by revision desc limit 1;
 if p_links is null or jsonb_typeof(p_links)<>'array' then raise exception 'Choose subject and class pairs' using errcode='22023'; end if;
 if jsonb_array_length(p_links) not between 1 and 100 then raise exception 'Choose between 1 and 100 subject/class pairs' using errcode='22023'; end if;
 if (select count(distinct (value->>'subject',value->>'group')) from jsonb_array_elements(p_links))<>jsonb_array_length(p_links) then raise exception 'Remove repeated subject/class pairs' using errcode='22023'; end if;
 for v_link in select value from jsonb_array_elements(p_links) loop
  if jsonb_typeof(v_link)<>'object' or jsonb_typeof(v_link->'subject') is distinct from 'string' or jsonb_typeof(v_link->'group') is distinct from 'string'
   or not coalesce(v_document->'subjects' ? (v_link->>'subject'),false)
   or v_link->>'subject' in ('PLC','A','Assembly','Advisory','Seminar','Super Teams')
   or not coalesce(v_document->'groups' ? (v_link->>'group'),false)
   or coalesce(v_document->'archivedGroups','[]') ? (v_link->>'group')
   or not coalesce((v_link->>'group')=any(p_groups),false) then
   raise exception 'Each subject must be linked to an active class in this teacher''s approved scope' using errcode='22023';
  end if;
 end loop;
end; $$;
revoke all on function school_private.validate_teaching_links(jsonb,text[]) from public,anon,authenticated;

-- Retain the older request/review signatures for clients and legacy pending requests.
-- A subject claim never grants a link: only leadership can create confirmed links.
create function public.request_teacher_access(p_name text,p_groups text[],p_note text,p_teaching jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 perform school_private.validate_teaching_links(p_teaching,p_groups);
 if exists(select 1 from unnest(p_groups) g where not exists(select 1 from jsonb_array_elements(p_teaching) l where l->>'group'=g)) then raise exception 'Each requested class needs at least one subject' using errcode='22023'; end if;
 v_id:=public.request_teacher_access(p_name,p_groups,p_note);
 update public.school_teacher_requests set requested_teaching=p_teaching where id=v_id;
 return v_id;
end; $$;

create function public.set_teacher_subject_links(p_teacher uuid,p_links jsonb) returns void language plpgsql security definer set search_path='' as $$
declare v_groups text[];
begin
 if not school_private.is_leadership() then raise exception 'Only school leadership can confirm teaching links' using errcode='42501'; end if;
 select groups into v_groups from public.school_members where user_id=p_teacher and active and role='teacher' for update;
 if not found then raise exception 'Active teacher account required' using errcode='22023'; end if;
 -- Empty removes all links and prevents new check-outs until assignments are confirmed.
 if p_links is null or jsonb_typeof(p_links)<>'array' then raise exception 'Choose subject and class pairs' using errcode='22023'; end if;
 if jsonb_array_length(p_links)>0 then perform school_private.validate_teaching_links(p_links,v_groups); end if;
 delete from public.teacher_subject_links where teacher_id=p_teacher;
 insert into public.teacher_subject_links(teacher_id,subject,class_group,approved_by)
  select p_teacher,l->>'subject',l->>'group',auth.uid() from jsonb_array_elements(p_links) l;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'teacher.subjects.confirm',jsonb_build_object('teacher',p_teacher,'links',p_links));
end; $$;

create function public.review_teacher_access(p_id uuid,p_approve boolean,p_groups text[],p_message text,p_teaching jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;
begin
 if not school_private.is_leadership() then raise exception 'School leadership required' using errcode='42501'; end if;
 if p_approve then perform school_private.validate_teaching_links(p_teaching,p_groups); end if;
 v_result:=public.review_teacher_access(p_id,p_approve,p_groups,p_message);
 if p_approve then perform public.set_teacher_subject_links((v_result->>'user_id')::uuid,p_teaching); end if;
 return v_result;
end; $$;

create function public.get_teacher_profiles() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in to view teaching links' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('teacher_id',m.user_id,'display_name',coalesce((select r.name from public.school_teacher_requests r where r.user_id=m.user_id and r.status='approved' order by r.reviewed_at desc limit 1),'Teacher'),'groups',m.groups,'teaching_links',coalesce((select jsonb_agg(jsonb_build_object('subject',l.subject,'group',l.class_group) order by l.subject,l.class_group) from public.teacher_subject_links l where l.teacher_id=m.user_id),'[]'::jsonb))) from public.school_members m where m.active and m.role='teacher' and (m.user_id=auth.uid() or school_private.is_leadership())),'[]'::jsonb);
end; $$;

create function public.checkout_teacher(p_date date,p_sessions integer[]) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;
begin
 perform 1 from public.school_members where user_id=auth.uid() and active and role='teacher' for update;
 if not found then raise exception 'Active teacher access required' using errcode='42501'; end if;
 if not exists(select 1 from public.teacher_subject_links l join public.school_members m on m.user_id=l.teacher_id where l.teacher_id=auth.uid() and l.class_group=any(m.groups)) then raise exception 'Ask school leadership to confirm your subjects and classes first' using errcode='22023'; end if;
 if p_date is null or p_date<(now() at time zone 'America/Belize')::date or p_date>(now() at time zone 'America/Belize')::date+366
  or p_sessions is null or cardinality(p_sessions) not between 1 and 6 or not p_sessions<@array[1,2,3,4,5,6]
  or exists(select 1 from unnest(p_sessions) s where s is null)
  or cardinality(p_sessions)<>(select count(distinct s) from unnest(p_sessions) s) then raise exception 'Choose today or a future date within one year, and unique sessions 1–6' using errcode='22023'; end if;
 insert into public.teacher_checkouts(teacher_id,date,sessions) values(auth.uid(),p_date,array(select unnest(p_sessions) order by 1))
 on conflict(teacher_id,date) do update set sessions=excluded.sessions,cancelled_at=null,updated_at=now() returning to_jsonb(teacher_checkouts.*) into v_result;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'teacher.checkout',jsonb_build_object('date',p_date,'sessions',p_sessions));
 return v_result;
end; $$;

create function public.cancel_teacher_checkout(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_teacher uuid;
begin
 select teacher_id into v_teacher from public.teacher_checkouts where id=p_id for update;
 if v_teacher is null or not (school_private.is_leadership() or (v_teacher=auth.uid() and exists(select 1 from public.school_members where user_id=auth.uid() and active and role='teacher'))) then raise exception 'Only this teacher or school leadership can cancel the check-out' using errcode='42501'; end if;
 update public.teacher_checkouts set cancelled_at=now(),updated_at=now() where id=p_id and cancelled_at is null;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'teacher.checkout.cancel',jsonb_build_object('checkout',p_id));
end; $$;

-- Public lesson impact contains no teacher identity, account ID, upload, or reason.
-- Private digitized timetables are authoritative; public assignments are next;
-- only a teacher without either falls back to their confirmed subject/class pairs.
create function public.get_teacher_unavailability(p_from date,p_to date)
returns table(date date,class_group text,subject text,cycle_day integer,session integer)
language plpgsql stable security definer set search_path='' as $$
declare v_document jsonb;
begin
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>400 then raise exception 'Choose a date range of at most 400 days' using errcode='22023'; end if;
 select document into v_document from public.school_versions order by revision desc limit 1;
 return query with active as (
  select c.date,c.sessions,c.teacher_id,l.class_group,l.subject,
   case when u.status='digitized' then u.digitized_schedule end as schedule,
   exists(select 1 from jsonb_array_elements(coalesce(v_document->'teacherAssignments','[]')) a where a->>'teacher'=c.teacher_id::text) as has_assignments
  from public.teacher_checkouts c join public.school_members m on m.user_id=c.teacher_id and m.active and m.role='teacher'
  join public.teacher_subject_links l on l.teacher_id=c.teacher_id and l.class_group=any(m.groups)
  left join public.teacher_timetable_uploads u on u.teacher_id=c.teacher_id
  where c.cancelled_at is null and c.date between p_from and p_to
   and v_document->'subjects' ? l.subject and v_document->'groups' ? l.class_group
   and not coalesce(v_document->'archivedGroups','[]') ? l.class_group
 ), impacts as (
  select a.date,a.class_group,a.subject,(entry->>'day')::integer as cycle_day,s.slot as session
  from active a cross join lateral jsonb_array_elements(a.schedule->'entries') entry
  cross join lateral generate_series((entry->>'session')::integer,(entry->>'session')::integer+coalesce((entry->>'span')::integer,1)-1) s(slot)
  where a.schedule is not null and entry->>'subject'=a.subject and entry->'groups' ? a.class_group and s.slot=any(a.sessions)
  union all
  select a.date,a.class_group,a.subject,(entry->>'day')::integer,(entry->>'session')::integer
  from active a cross join lateral jsonb_array_elements(coalesce(v_document->'teacherAssignments','[]')) entry
  where a.schedule is null and a.has_assignments and entry->>'teacher'=a.teacher_id::text and entry->>'group'=a.class_group and (entry->>'session')::integer=any(a.sessions)
  union all
  select a.date,a.class_group,a.subject,null::integer,s.slot
  from active a cross join lateral unnest(a.sessions) s(slot) where a.schedule is null and not a.has_assignments
 ) select distinct i.date,i.class_group,i.subject,i.cycle_day,i.session from impacts i;
end; $$;

-- Derive existing links only from verified digitized lessons already in scope.
insert into public.teacher_subject_links(teacher_id,subject,class_group)
select distinct m.user_id,entry->>'subject',g.value
from public.school_members m join public.teacher_timetable_uploads u on u.teacher_id=m.user_id and u.status='digitized'
cross join lateral jsonb_array_elements(u.digitized_schedule->'entries') entry
cross join lateral jsonb_array_elements_text(entry->'groups') g(value)
where m.active and m.role='teacher' and g.value=any(m.groups)
and entry->>'subject' not in ('PLC','A','Assembly','Advisory','Seminar','Super Teams')
and exists(select 1 from public.school_versions v where v.revision=(select max(revision) from public.school_versions) and v.document->'subjects' ? (entry->>'subject') and v.document->'groups' ? g.value and not coalesce(v.document->'archivedGroups','[]') ? g.value)
on conflict do nothing;

revoke all on function public.request_teacher_access(text,text[],text,jsonb),public.review_teacher_access(uuid,boolean,text[],text,jsonb),public.set_teacher_subject_links(uuid,jsonb),public.get_teacher_profiles(),public.checkout_teacher(date,integer[]),public.cancel_teacher_checkout(uuid),public.get_teacher_unavailability(date,date) from public,anon,authenticated;
grant execute on function public.request_teacher_access(text,text[],text,jsonb),public.review_teacher_access(uuid,boolean,text[],text,jsonb),public.set_teacher_subject_links(uuid,jsonb),public.get_teacher_profiles(),public.checkout_teacher(date,integer[]),public.cancel_teacher_checkout(uuid) to authenticated;
grant execute on function public.get_teacher_unavailability(date,date) to anon,authenticated;
notify pgrst,'reload schema';
commit;
