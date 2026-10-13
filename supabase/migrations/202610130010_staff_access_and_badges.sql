begin;
create or replace function school_private.community_icon_valid(p_key text) returns boolean language sql immutable set search_path='' as $$
 select p_key is null or p_key=any(array['star','award','heart','flame','sparkles','crown','shield-check','rosette','rocket','palette','music','device-gamepad','book','ball-football','moon','sun','coffee','code','school','planet','bolt','headphones','mood-smile','bug','flag']);
$$;
create function public.lookup_school_account(p_identifier text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_user auth.users; v_result jsonb; v_chat text[]; v_caps text[];
begin
 if not school_private.community_developer() then raise exception 'Developer access required' using errcode='42501'; end if;
 if p_identifier is null or length(trim(p_identifier)) not between 1 and 320 then raise exception 'Enter an email or account UID' using errcode='22023'; end if;
 select * into v_user from auth.users where id::text=lower(trim(p_identifier)) or lower(email)=lower(trim(p_identifier));
 if not found then raise exception 'No existing account matches that email or UID' using errcode='22023'; end if;
 select to_jsonb(m) into v_result from public.school_members m where user_id=v_user.id;
 select coalesce(array_agg(case p when 'manage_messages' then 'chat.moderate' when 'upload_emojis' then 'chat.emojis' when 'kick_members' then 'chat.kick' end),'{}') into v_chat from public.school_space_roles r cross join unnest(r.permissions) p where r.user_id=v_user.id and r.moderator and not r.kicked;
 select coalesce(array_agg(distinct c),'{}') into v_caps from (select jsonb_array_elements_text(coalesce(v_result->'capabilities','[]')) c union select unnest(v_chat)) all_caps;
 v_result:=coalesce(v_result,'{}')||jsonb_build_object('capabilities',v_caps);
 return jsonb_build_object('user_id',v_user.id,'email',v_user.email,'name',coalesce(v_user.raw_user_meta_data->>'full_name',''),'role','codeveloper','capabilities','[]'::jsonb,'groups',jsonb_build_array('*'),'active',false)||coalesce(v_result,'{}');
end; $$;
create function public.set_school_access(p_identifier text,p_role text,p_capabilities text[],p_groups text[],p_active boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_account jsonb;
begin
 v_account:=public.lookup_school_account(p_identifier);
 return public.set_school_member((v_account->>'user_id')::uuid,p_role,p_capabilities,p_groups,p_active);
end; $$;
revoke all on function public.lookup_school_account(text),public.set_school_access(text,text,text[],text[],boolean) from public,anon;
grant execute on function public.lookup_school_account(text),public.set_school_access(text,text,text[],text[],boolean) to authenticated;

create or replace function school_private.school_space_role(p_user uuid) returns text language sql stable security definer set search_path='' as $$
 select case
 when exists(select 1 from public.school_members where user_id=p_user and active and role='developer') then 'Developer'
 when exists(select 1 from public.school_members where user_id=p_user and active and role='codeveloper') then 'Admin'
 when exists(select 1 from public.school_members where user_id=p_user and active and role in ('teacher','principal')) then 'Teacher'
 when exists(select 1 from public.school_space_roles where user_id=p_user and moderator and not kicked) then 'Moderator'
 when exists(select 1 from public.community_profiles where user_id=p_user and audience='parent') then 'Member' else 'Student' end;
$$;
-- Preserve existing Teacher chat rights when making them individually configurable.
update public.school_members set capabilities=(select array_agg(distinct c) from unnest(capabilities||array['chat.moderate','chat.emojis']) c) where active and role='teacher';
create or replace function school_private.school_space_permission(p_permission text) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.school_space_access() and (school_private.community_developer()
 or (p_permission in ('manage_messages','upload_emojis') and exists(select 1 from public.school_members where user_id=auth.uid() and active and role='principal'))
 or exists(select 1 from public.school_members where user_id=auth.uid() and active and
 case p_permission when 'manage_messages' then 'chat.moderate' when 'upload_emojis' then 'chat.emojis' when 'kick_members' then 'chat.kick' end=any(capabilities))
 or exists(select 1 from public.school_space_roles where user_id=auth.uid() and moderator and not kicked and p_permission=any(permissions)));
$$;

-- Catalog entries are cosmetic awards, never access grants. Keep existing custom entries.
do $$ declare v_creator uuid; begin
 select user_id into v_creator from public.school_members where active and role='developer' order by updated_at limit 1;
 if v_creator is null then raise exception 'A Developer account is required to seed badges'; end if;
 insert into public.school_space_badge_catalog(name,description,icon_key,color,created_by) values
 ('Awarded Developer','Recognized for developing the community.','code','#a34716',v_creator),
 ('Awarded Friendly Face','A welcoming and helpful member.','heart','#b64270',v_creator),
 ('Awarded Admin','Recognized for helping manage the community.','shield-check','#6546b5',v_creator),
 ('Awarded Bug Hunter','Found and reported a useful bug.','bug','#196b5b',v_creator),
 ('Awarded Founder','Joined the community early.','flag','#826017',v_creator)
 on conflict(name) do nothing;
end; $$;
alter table public.community_rooms drop constraint school_channel_roles;
alter table public.community_rooms add constraint school_channel_roles check(speaking_roles is null or (cardinality(speaking_roles) between 1 and 6 and speaking_roles <@ array['Developer','Admin','Teacher','Moderator','Student','Member']::text[]));
create or replace function public.set_school_member(p_user_id uuid,p_role text,p_capabilities text[],p_groups text[],p_active boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor public.school_members; v_result jsonb; v_groups jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('school.staff.access',0));
  select * into v_actor from public.school_members m where m.user_id=auth.uid() and m.active;
  if v_actor.role is distinct from 'developer' then raise exception 'Only Developer can grant or change membership' using errcode='42501'; end if;
  if p_user_id=auth.uid() then raise exception 'Developer cannot change their own membership through this API' using errcode='42501'; end if;
  if p_role not in ('developer','principal','teacher','codeveloper') or p_capabilities is null or p_groups is null or p_active is null or
    not p_capabilities <@ array['schedules.manage','classes.manage','subjects.manage','calendar.manage','substitutions.manage','notices.submit','notices.publish','banners.manage','chat.moderate','chat.emojis','chat.kick']::text[] then
    raise exception 'Invalid role or capability' using errcode='22023';
  end if;
  if array_position(p_capabilities,null) is not null or array_position(p_groups,null) is not null then raise exception 'Invalid permissions or scopes' using errcode='22023'; end if;
  select s.document->'groups' into v_groups from public.school_versions s order by s.revision desc limit 1;
  if exists(select 1 from unnest(p_groups) g where g is null or (g<>'*' and not (v_groups ? g))) or ('*'=any(p_groups) and p_role='teacher') then
    raise exception 'Invalid group scope' using errcode='22023';
  end if;
  if not exists(select 1 from auth.users where id=p_user_id) then raise exception 'Account not found' using errcode='22023'; end if;
  insert into public.school_members(user_id,role,capabilities,groups,active) values(p_user_id,p_role,p_capabilities,p_groups,p_active)
    on conflict(user_id) do update set role=excluded.role,capabilities=excluded.capabilities,groups=excluded.groups,active=excluded.active,updated_at=now()
    returning to_jsonb(school_members.*) into v_result;
  -- The unified editor replaces any legacy moderator grant as well.
  update public.school_space_roles set moderator=false,permissions='{}',changed_by=auth.uid(),updated_at=now() where user_id=p_user_id;
  insert into public.school_audit_events(actor,action,details) values(auth.uid(),'member.change',jsonb_build_object('userId',p_user_id,'role',p_role,'capabilities',p_capabilities,'groups',p_groups,'active',p_active));
  return v_result;
end; $$;

create or replace function public.school_space_save_channel_controls(p_id uuid,p_name text,p_description text,p_category text,p_posting_policy text,p_speaking_roles text[],p_slowmode_seconds integer) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer permission required' using errcode='42501'; end if;
 if p_slowmode_seconds is null or p_slowmode_seconds not between 0 and 3600 or (p_speaking_roles is not null and (cardinality(p_speaking_roles) not between 1 and 6 or not p_speaking_roles <@ array['Developer','Admin','Teacher','Moderator','Student','Member']::text[] or array_position(p_speaking_roles,null) is not null)) then raise exception 'Choose valid roles and a slow mode from 0 to 3600 seconds' using errcode='22023'; end if;
 v_id:=public.school_space_save_channel(p_id,p_name,p_description,p_category,p_posting_policy);
 update public.community_rooms set speaking_roles=p_speaking_roles,slowmode_seconds=p_slowmode_seconds where id=v_id;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'space.channel.controls',jsonb_build_object('channelId',v_id,'roles',p_speaking_roles,'slowmodeSeconds',p_slowmode_seconds));
 return v_id;
end; $$;

create or replace function public.publish_school_document(p_document jsonb, p_expected_revision bigint)
returns table(revision bigint, document jsonb, published_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
  v_member public.school_members; v_old jsonb; v_revision bigint; v_key text; v_group text; v_item jsonb; v_capability text;
begin
  select * into v_member from public.school_members m where m.user_id = auth.uid() and m.active;
  if v_member.user_id is null then raise exception 'Publishing permission required' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(742617092);
  select s.document,s.revision into v_old,v_revision from public.school_versions s order by s.revision desc limit 1;
  if p_expected_revision is distinct from coalesce(v_revision,0) then raise exception 'Revision conflict: reload latest schedule before publishing' using errcode='40001'; end if;
  perform school_private.validate_school_document(p_document);
  foreach v_key in array array['settings','groups','archivedGroups','subjects','bellProfiles','calendar','overrides','announcements','banners','teacherAssignments'] loop
    if p_document->v_key is distinct from v_old->v_key then
      v_capability := case v_key when 'archivedGroups' then 'classes.manage' when 'subjects' then 'subjects.manage' when 'calendar' then 'calendar.manage' when 'bellProfiles' then 'calendar.manage'
        when 'overrides' then 'substitutions.manage' when 'announcements' then 'notices.publish' when 'banners' then 'banners.manage' else 'schedules.manage' end;
      if not school_private.has_capability(v_capability) then raise exception 'Missing capability: %',v_capability using errcode='42501'; end if;
      if v_member.role in ('codeveloper','teacher') and not ('*' = any(v_member.groups)) then
        if v_key in ('settings','subjects','bellProfiles','calendar','banners','teacherAssignments') then raise exception 'Schoolwide scope required for %',v_key using errcode='42501'; end if;
        if v_key = 'archivedGroups' then
          for v_group in select value from jsonb_array_elements_text(coalesce(v_old->'archivedGroups','[]')) union select value from jsonb_array_elements_text(p_document->'archivedGroups') loop
            if not (coalesce(v_old->'archivedGroups','[]') ? v_group and p_document->'archivedGroups' ? v_group) and not school_private.in_scope(v_group) then
              raise exception 'Archived group outside assigned scope' using errcode='42501';
            end if;
          end loop;
        elsif v_key = 'groups' then
          for v_group in select key from jsonb_object_keys(coalesce(v_old->'groups','{}') || p_document->'groups') key loop
            if p_document->'groups'->v_group is distinct from v_old->'groups'->v_group and not school_private.in_scope(v_group) then raise exception 'Group outside assigned scope' using errcode='42501'; end if;
          end loop;
        else
          for v_item in select value from jsonb_array_elements(coalesce(v_old->v_key,'[]')) union select value from jsonb_array_elements(p_document->v_key) loop
            if not (coalesce(v_old->v_key,'[]') @> jsonb_build_array(v_item) and p_document->v_key @> jsonb_build_array(v_item)) and
              not school_private.in_scope(case when v_key='announcements' then v_item->>'audience' else v_item->>'group' end) then
              raise exception 'Changed item outside assigned scope' using errcode='42501';
            end if;
          end loop;
        end if;
      end if;
    end if;
  end loop;
  if (select array_agg(key order by key) from jsonb_object_keys(p_document->'groups') key) is distinct from
    (select array_agg(key order by key) from jsonb_object_keys(coalesce(v_old->'groups','{}')) key) and not school_private.has_capability('classes.manage') then
    raise exception 'Creating or archiving classes requires classes.manage' using errcode='42501';
  end if;
  insert into public.school_versions(document,published_by) values(p_document,auth.uid());
  insert into public.school_audit_events(actor,action,details) values(auth.uid(),'school.publish',jsonb_build_object('previousRevision',coalesce(v_revision,0)));
  return query select s.revision,s.document,s.published_at from public.school_versions s order by s.revision desc limit 1;
end; $$;

notify pgrst,'reload schema';
commit;
