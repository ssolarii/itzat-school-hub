-- Authenticated school space. Cosmetic selections never grant permissions.
begin;
alter table public.community_profiles
 add column status_text text not null default '' check(length(status_text)<=100),
 add column status_emoji text,
 add column status_emoji_id uuid references public.community_emojis(id) on delete set null,
 add column name_color text not null default '#6546b5' check(name_color ~ '^#[0-9a-fA-F]{6}$'),
 add column theme text not null default 'system' check(theme in ('light','dark','system')),
 add column cosmetic_roles text[] not null default '{}',
 add column space_onboarded boolean not null default false,
 add constraint community_status_one_emoji check(status_emoji is null or status_emoji_id is null);
create table public.school_space_roles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 moderator boolean not null default false,
 permissions text[] not null default '{}' check(permissions <@ array['manage_messages','upload_emojis','kick_members']::text[]),
 kicked boolean not null default false,
 changed_by uuid references auth.users(id) on delete set null,
 updated_at timestamptz not null default now()
);
create table public.school_space_presence (
 user_id uuid primary key references auth.users(id) on delete cascade,
 last_seen timestamptz not null default now()
);
alter table public.school_space_roles enable row level security;
alter table public.school_space_presence enable row level security;
revoke all on public.school_space_roles,public.school_space_presence from public,anon,authenticated;
create policy school_space_roles_own on public.school_space_roles for select to authenticated using(user_id=auth.uid() or school_private.community_developer());
create policy school_space_presence_own on public.school_space_presence for select to authenticated using(user_id=auth.uid());
alter table public.community_rooms drop constraint community_rooms_kind_check;
alter table public.community_rooms add constraint community_rooms_kind_check check(kind in ('class','dm','group','school'));
alter table public.community_rooms add column school_channel text check(school_channel is null or school_channel in ('general','assignments','announcements'));
alter table public.community_rooms add constraint community_school_channel_kind check((kind='school')=(school_channel is not null));
create unique index community_school_channel_unique on public.community_rooms(school_channel) where kind='school';
insert into public.community_rooms(kind,title,status,school_channel) values
 ('school','general','approved','general'),('school','assignments','approved','assignments'),('school','announcements','approved','announcements');

create function school_private.school_space_access() returns boolean language sql stable security definer set search_path='' as $$
 select school_private.community_verified() and exists(select 1 from public.community_profiles p where p.user_id=auth.uid() and p.space_onboarded)
 and not exists(select 1 from public.school_space_roles s where s.user_id=auth.uid() and s.kicked);
$$;
create function school_private.school_space_permission(p_permission text) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.school_space_access() and (school_private.community_developer()
 or (p_permission in ('manage_messages','upload_emojis') and exists(select 1 from public.school_members m where m.user_id=auth.uid() and m.active and m.role in ('teacher','principal')))
 or exists(select 1 from public.school_space_roles s where s.user_id=auth.uid() and s.moderator and not s.kicked and p_permission=any(s.permissions)));
$$;
create function school_private.school_space_role(p_user uuid) returns text language sql stable security definer set search_path='' as $$
 select case
 when exists(select 1 from public.school_members m where m.user_id=p_user and m.active and m.role='developer') then 'Developer'
 when exists(select 1 from public.school_members m where m.user_id=p_user and m.active and m.role in ('teacher','principal')) then 'Teacher'
 when exists(select 1 from public.school_space_roles s where s.user_id=p_user and s.moderator and not s.kicked) then 'Moderator'
 when exists(select 1 from public.community_profiles p where p.user_id=p_user and p.audience='parent') then 'Member'
 else 'Student' end;
$$;
create function school_private.school_space_authority() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('role',school_private.school_space_role(auth.uid()),'permissions',
 (select coalesce(jsonb_agg(c),'[]') from unnest(array['manage_messages','upload_emojis','kick_members']) c where school_private.school_space_permission(c)),
 'kicked',exists(select 1 from public.school_space_roles s where s.user_id=auth.uid() and s.kicked));
$$;
create or replace function school_private.community_room_access(p_room uuid) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.community_verified() and exists(select 1 from public.community_rooms r where r.id=p_room and r.status='approved' and
 ((r.kind='class' and school_private.community_class_access(r.class_group))
 or (r.kind='school' and school_private.school_space_access())
 or (r.kind in ('dm','group') and exists(select 1 from public.community_room_members m where m.room_id=r.id and m.user_id=auth.uid()))));
$$;
create or replace function school_private.community_profile_access(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.community_verified() and (p_user=auth.uid() or school_private.is_leadership()
 or exists(select 1 from public.community_profiles p where p.user_id=p_user and p.audience='student' and school_private.community_class_access(p.class_group))
 or (not school_private.community_pair_blocked(auth.uid(),p_user) and (
 school_private.community_friend_access(p_user)
 or (school_private.school_space_access() and exists(select 1 from public.community_profiles p where p.user_id=p_user and p.space_onboarded) and not exists(select 1 from public.school_space_roles s where s.user_id=p_user and s.kicked))
 or exists(select 1 from public.community_room_members m where m.user_id=p_user and school_private.community_room_access(m.room_id)))));
$$;
create function public.school_space_preferences(p_preferences jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_roles text[]; v_emoji text; v_id uuid; v_previous jsonb;
begin
 perform school_private.community_assert_actor(); perform school_private.community_limit('space_preferences',30,3600);
 perform school_private.assert_keys(p_preferences,array['status_text','status_emoji','status_emoji_id','name_color','theme','cosmetic_roles','space_onboarded'],'School-space preferences');
 select jsonb_build_object('status_text',p.status_text,'status_emoji',p.status_emoji,'status_emoji_id',p.status_emoji_id,
 'name_color',p.name_color,'theme',p.theme,'cosmetic_roles',p.cosmetic_roles,'space_onboarded',p.space_onboarded)
 into v_previous from public.community_profiles p where p.user_id=auth.uid() for update;
 if not found then raise exception 'Complete your community profile first' using errcode='22023'; end if;
 -- Updates are patches. A theme or status edit must never silently change school-space consent.
 p_preferences:=v_previous||p_preferences;
 if jsonb_typeof(p_preferences->'status_text') is distinct from 'string' or
 jsonb_typeof(p_preferences->'name_color') is distinct from 'string' or jsonb_typeof(p_preferences->'theme') is distinct from 'string' or
 (p_preferences->>'name_color') !~ '^#[0-9a-fA-F]{6}$' or p_preferences->>'theme' not in ('light','dark','system') or
 (jsonb_typeof(p_preferences->'status_emoji') not in ('null','string')) or
 (jsonb_typeof(p_preferences->'status_emoji_id') not in ('null','string')) then raise exception 'Use a valid status, name color and theme' using errcode='22023'; end if;
 if jsonb_typeof(p_preferences->'cosmetic_roles') is distinct from 'array' then raise exception 'Choose cosmetic interests from the catalog' using errcode='22023'; end if;
 select coalesce(array_agg(value),'{}') into v_roles from jsonb_array_elements_text(p_preferences->'cosmetic_roles');
 if cardinality(v_roles)>4 or cardinality(v_roles)<>(select count(distinct r) from unnest(v_roles) r) or
 not v_roles <@ array['creative','music','gaming','books','sports','night-owl','early-bird','pet-lover']::text[] then raise exception 'Choose up to four distinct cosmetic interests' using errcode='22023'; end if;
 v_emoji:=nullif(p_preferences->>'status_emoji',''); v_id:=nullif(p_preferences->>'status_emoji_id','')::uuid;
 if v_emoji is not null and (length(v_emoji)>16 or not exists(select 1 from unnest(string_to_array(v_emoji,null)) c where ascii(c) between 126976 and 129791 or ascii(c) between 9728 and 10175 or ascii(c)=8419) or exists(select 1 from unnest(string_to_array(v_emoji,null)) c where
 not (ascii(c) between 126976 and 129791 or ascii(c) between 9728 and 10175 or ascii(c) in (8205,65039,8419,35,42) or ascii(c) between 48 and 57))) then
 raise exception 'Choose a standard emoji or an approved custom emoji' using errcode='22023'; end if;
 if v_id is not null and not exists(select 1 from public.community_emojis e where e.id=v_id and e.status='approved') then raise exception 'The status emoji must be approved first' using errcode='22023'; end if;
 if p_preferences->>'space_onboarded' is null or jsonb_typeof(p_preferences->'space_onboarded')<>'boolean' then raise exception 'Confirm school-space profile visibility' using errcode='22023'; end if;
 update public.community_profiles set status_text=coalesce(p_preferences->>'status_text',''),status_emoji=v_emoji,status_emoji_id=v_id,
 name_color=coalesce(p_preferences->>'name_color','#6546b5'),theme=coalesce(p_preferences->>'theme','system'),
 cosmetic_roles=v_roles,space_onboarded=(p_preferences->>'space_onboarded')::boolean,updated_at=now() where user_id=auth.uid();
 if not found then raise exception 'Complete your community profile first' using errcode='22023'; end if;
 return public.school_space_get_state();
end; $$;

create function public.school_space_members() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.school_space_access() then raise exception 'Join the school space first' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('user_id',p.user_id,'real_name',p.real_name,'display_name',p.display_name,
 'avatar_path',p.avatar_path,'banner_path',p.banner_path,'bio',p.bio,'class_group',p.class_group,'accent',p.accent,'accent_end',p.accent_end,
 'status_text',p.status_text,'status_emoji',p.status_emoji,'status_emoji_id',p.status_emoji_id,'name_color',p.name_color,
 'cosmetic_roles',p.cosmetic_roles,'authority_role',school_private.school_space_role(p.user_id),
 'online',coalesce(pr.last_seen>now()-interval '90 seconds',false),'last_seen',pr.last_seen)
 order by case school_private.school_space_role(p.user_id) when 'Developer' then 1 when 'Teacher' then 2 when 'Moderator' then 3 else 4 end,
 coalesce(nullif(p.display_name,''),p.real_name))
 from public.community_profiles p left join public.school_space_presence pr on pr.user_id=p.user_id
 where p.space_onboarded and not exists(select 1 from public.school_space_roles s where s.user_id=p.user_id and s.kicked)
 and exists(select 1 from auth.users u where u.id=p.user_id and u.email_confirmed_at is not null)
 and not school_private.community_pair_blocked(auth.uid(),p.user_id)),'[]');
end; $$;
create function public.school_space_get_state() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_profile jsonb; v_channels jsonb; v_members jsonb;
begin
 if not school_private.community_verified() then raise exception 'Verified sign-in required' using errcode='42501'; end if;
 select jsonb_build_object('status_text',p.status_text,'status_emoji',p.status_emoji,'status_emoji_id',p.status_emoji_id,
 'name_color',p.name_color,'theme',p.theme,'cosmetic_roles',p.cosmetic_roles,'space_onboarded',p.space_onboarded) into v_profile from public.community_profiles p where p.user_id=auth.uid();
 if school_private.school_space_access() then
  select coalesce(jsonb_agg(to_jsonb(r.*) order by case r.school_channel when 'general' then 1 when 'assignments' then 2 else 3 end),'[]') into v_channels from public.community_rooms r where r.kind='school' and school_private.community_room_access(r.id);
  v_members:=public.school_space_members();
 else v_channels:='[]'; v_members:='[]'; end if;
 return jsonb_build_object('profile',v_profile,'authority',school_private.school_space_authority(),'channels',v_channels,'members',v_members,
 'role_catalog',jsonb_build_array(jsonb_build_object('id','creative','label','Creative'),jsonb_build_object('id','music','label','Music'),jsonb_build_object('id','gaming','label','Gaming'),jsonb_build_object('id','books','label','Books'),jsonb_build_object('id','early-bird','label','Early bird'),jsonb_build_object('id','pet-lover','label','Pet lover'),jsonb_build_object('id','sports','label','Sports'),jsonb_build_object('id','night-owl','label','Night owl')));
end; $$;
create function public.school_space_save_profile(p_profile jsonb,p_preferences jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 -- One RPC transaction: invalid cosmetic/status input also rolls back the base profile edit.
 perform public.community_save_profile(p_profile);
 perform public.school_space_preferences(p_preferences);
 return public.community_get_profile();
end; $$;
create or replace function public.community_profiles_directory() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_verified() then raise exception 'Verified sign-in required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('user_id',p.user_id,
 'real_name',case when school_private.community_profile_access(p.user_id) then p.real_name else 'School member' end,'display_name',p.display_name,
 'class_group',case when school_private.community_profile_access(p.user_id) then p.class_group end,
 'avatar_path',case when school_private.community_profile_access(p.user_id) then p.avatar_path end,
 'banner_path',case when school_private.community_profile_access(p.user_id) then p.banner_path end,
 'bio',case when school_private.community_profile_access(p.user_id) then p.bio end,
 'status_text',case when school_private.community_profile_access(p.user_id) then p.status_text end,
 'status_emoji',case when school_private.community_profile_access(p.user_id) then p.status_emoji end,
 'status_emoji_id',case when school_private.community_profile_access(p.user_id) then p.status_emoji_id end,
 'cosmetic_roles',case when school_private.community_profile_access(p.user_id) then p.cosmetic_roles else '{}'::text[] end,
 'name_color',p.name_color,'accent',p.accent,'accent_end',p.accent_end))
 from public.community_profiles p where exists(select 1 from auth.users u where u.id=p.user_id and u.email_confirmed_at is not null)),'[]');
end; $$;
create or replace function public.community_list_friends() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_verified() then raise exception 'Verified sign-in required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(f.*)||jsonb_build_object(
 'other_id',p.user_id,'display_name',p.display_name,
 'real_name',case when school_private.community_profile_access(p.user_id) then p.real_name else 'School member' end,
 'avatar_path',case when school_private.community_profile_access(p.user_id) then p.avatar_path end,
 'banner_path',case when school_private.community_profile_access(p.user_id) then p.banner_path end,
 'class_group',case when school_private.community_profile_access(p.user_id) then p.class_group end,
 'bio',case when school_private.community_profile_access(p.user_id) then p.bio end,
 'status_text',case when school_private.community_profile_access(p.user_id) then p.status_text end,
 'status_emoji',case when school_private.community_profile_access(p.user_id) then p.status_emoji end,
 'status_emoji_id',case when school_private.community_profile_access(p.user_id) then p.status_emoji_id end,
 'cosmetic_roles',case when school_private.community_profile_access(p.user_id) then p.cosmetic_roles else '{}'::text[] end,
 'name_color',p.name_color,'accent',p.accent,'accent_end',p.accent_end) order by f.updated_at desc)
 from public.community_friendships f join public.community_profiles p on p.user_id=case when f.requested_by=auth.uid() then f.recipient_id else f.requested_by end
 where auth.uid() in (f.requested_by,f.recipient_id) and f.status in ('pending','accepted')
 and not school_private.community_pair_blocked(f.requested_by,f.recipient_id)),'[]');
end; $$;
create function public.school_space_heartbeat() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if not school_private.school_space_access() then raise exception 'Join the school space first' using errcode='42501'; end if;
 perform school_private.community_limit('presence',6,60);
 insert into public.school_space_presence(user_id,last_seen) values(auth.uid(),now()) on conflict(user_id) do update set last_seen=now();
 return jsonb_build_object('last_seen',now());
end; $$;
create function public.school_space_assign_moderator(p_user uuid,p_permissions text[],p_active boolean default true) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() or p_user=auth.uid() then raise exception 'Developer approval for another account is required' using errcode='42501'; end if;
 if p_permissions is null or p_active is null or not p_permissions <@ array['manage_messages','upload_emojis','kick_members']::text[] or
 not exists(select 1 from public.community_profiles p join auth.users u on u.id=p.user_id where p.user_id=p_user and u.email_confirmed_at is not null) then raise exception 'Choose a verified community member and valid permissions' using errcode='22023'; end if;
 insert into public.school_space_roles(user_id,moderator,permissions,changed_by) values(p_user,p_active,case when p_active then p_permissions else '{}' end,auth.uid())
 on conflict(user_id) do update set moderator=excluded.moderator,permissions=excluded.permissions,changed_by=auth.uid(),updated_at=now();
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'space.moderator.assign',jsonb_build_object('userId',p_user,'permissions',p_permissions,'active',p_active));
end; $$;
create function public.school_space_kick(p_user uuid,p_kicked boolean default true) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if not school_private.school_space_permission('kick_members') or p_user=auth.uid() then raise exception 'School-space kick permission is required for another account' using errcode='42501'; end if;
 if p_kicked is null or not exists(select 1 from public.community_profiles p where p.user_id=p_user) then raise exception 'Choose an existing member' using errcode='22023'; end if;
 if exists(select 1 from public.school_members m where m.user_id=p_user and m.active and m.role in ('developer','teacher','principal')) then raise exception 'School staff cannot be excluded through school-space moderation' using errcode='42501'; end if;
 if exists(select 1 from public.school_space_roles s where s.user_id=p_user and s.moderator) and not school_private.community_developer() then raise exception 'Only Developer can exclude a Moderator' using errcode='42501'; end if;
 insert into public.school_space_roles(user_id,kicked,changed_by) values(p_user,p_kicked,auth.uid()) on conflict(user_id) do update set kicked=excluded.kicked,changed_by=auth.uid(),updated_at=now();
 delete from public.school_space_presence where user_id=p_user;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'space.member.exclude',jsonb_build_object('userId',p_user,'kicked',p_kicked));
end; $$;
create function public.school_space_remove_message(p_id bigint) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if not school_private.school_space_permission('manage_messages') then raise exception 'School-space message permission required' using errcode='42501'; end if;
 update public.community_messages m set removed_at=now() from public.community_rooms r where m.id=p_id and m.room_id=r.id and r.kind='school' and m.removed_at is null;
 if not found then raise exception 'School-space message unavailable' using errcode='22023'; end if;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'space.message.remove',jsonb_build_object('messageId',p_id));
end; $$;
create function public.school_space_submit_emoji(p_name text,p_media_path text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 perform school_private.community_assert_actor();
 if not school_private.school_space_permission('upload_emojis') then raise exception 'School-space emoji upload permission required' using errcode='42501'; end if;
 v_id:=public.community_submit_emoji(p_name,p_media_path);
 -- Upload permission never bypasses Developer approval.
 return jsonb_build_object('id',v_id,'pending_review',true);
end; $$;

create or replace function public.community_send_message(p_room uuid,p_body text,p_media_path text default null,p_emoji uuid default null,p_gif_url text default null) returns bigint language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_id bigint; v_other uuid;
begin
 v_actor:=school_private.community_assert_actor();
 if not school_private.community_room_access(p_room) then raise exception 'This conversation is private or awaiting review' using errcode='42501'; end if;
 if exists(select 1 from public.community_rooms where id=p_room and kind='school' and school_channel='announcements') and not school_private.school_space_permission('manage_messages') then raise exception 'Only approved school-space staff can post announcements' using errcode='42501'; end if;
 if exists(select 1 from public.community_rooms where id=p_room and kind='dm') then
  select m.user_id into v_other from public.community_room_members m where m.room_id=p_room and m.user_id<>v_actor;
  perform school_private.community_lock_pair(v_actor,v_other);
  if school_private.community_pair_blocked(v_actor,v_other) then raise exception 'Direct messaging is unavailable for this conversation' using errcode='42501'; end if;
 end if;
 perform school_private.community_limit('message',30,60);
 if not school_private.community_owns_media(p_media_path) then raise exception 'Use your own uploaded media' using errcode='42501'; end if;
 if p_emoji is not null and not exists(select 1 from public.community_emojis e where e.id=p_emoji and e.status='approved') then raise exception 'Emoji is not approved' using errcode='22023'; end if;
 insert into public.community_messages(room_id,author_id,body,media_path,emoji_id,gif_url) values(p_room,v_actor,trim(coalesce(p_body,'')),p_media_path,p_emoji,p_gif_url) returning id into v_id;
 return v_id;
end; $$;

-- Realtime INSERT notifications and REST reads have the same verified room boundary.
-- Removed content remains available only as the RPC's moderation placeholder.
drop policy community_messages_read on public.community_messages;
create policy community_messages_read on public.community_messages for select to authenticated using(removed_at is null and school_private.community_room_access(room_id));
grant select(id,room_id,author_id,body,media_path,gif_url,emoji_id,created_at,removed_at) on public.community_messages to authenticated;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='community_messages') then
  alter publication supabase_realtime add table public.community_messages;
 end if;
end; $$;

do $$ declare f record; begin
 for f in select p.oid::regprocedure signature,n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname like 'school_space_%' and n.nspname in ('public','school_private') loop
 execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 if f.nspname='public' then execute format('grant execute on function %s to authenticated',f.signature); end if;
 end loop;
end; $$;
grant execute on function school_private.school_space_access(),school_private.school_space_permission(text) to authenticated;
commit;
