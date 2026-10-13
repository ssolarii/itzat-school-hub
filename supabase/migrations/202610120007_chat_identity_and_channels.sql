-- Local-only extension for the school community. Do not apply without explicit approval.
begin;

alter table public.community_profiles
 add column personal_tag text not null default '' check(length(personal_tag)<=24);

alter table public.community_rooms drop constraint if exists community_rooms_school_channel_check;
alter table public.community_rooms
 add column channel_category text not null default 'Conversation' check(length(trim(channel_category)) between 1 and 40),
 add column description text not null default '' check(length(description)<=240),
 add column channel_archived boolean not null default false,
 add constraint community_rooms_school_channel_check check(school_channel is null or school_channel ~ '^[a-z0-9][a-z0-9_-]{0,47}$');
update public.community_rooms set channel_category=case school_channel when 'assignments' then 'Learning' when 'announcements' then 'School notices' else 'Conversation' end
 where kind='school';

create table public.school_space_server (
 id boolean primary key default true check(id),
 name text not null check(length(trim(name)) between 2 and 60),
 description text not null default '' check(length(description)<=240),
 updated_by uuid references auth.users(id) on delete set null,
 updated_at timestamptz not null default now()
);
insert into public.school_space_server(id,name,description) values(true,'Itz’at Community','A place to connect, learn and share.') on conflict(id) do nothing;
alter table public.school_space_server enable row level security;
revoke all on public.school_space_server from public,anon,authenticated;

create table public.school_space_badge_catalog (
 id uuid primary key default gen_random_uuid(),
 name text not null unique check(length(trim(name)) between 2 and 32),
 description text not null default '' check(length(description)<=120),
 emoji text not null default '✦' check(length(emoji)<=16),
 color text not null default '#512393' check(color ~ '^#[0-9a-fA-F]{6}$'),
 active boolean not null default true,
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now()
);
create table public.school_space_badge_awards (
 user_id uuid not null references auth.users(id) on delete cascade,
 badge_id uuid not null references public.school_space_badge_catalog(id) on delete restrict,
 awarded_by uuid not null references auth.users(id) on delete restrict,
 note text not null default '' check(length(note)<=160),
 awarded_at timestamptz not null default now(),
 primary key(user_id,badge_id)
);
alter table public.school_space_badge_catalog enable row level security;
alter table public.school_space_badge_awards enable row level security;
revoke all on public.school_space_badge_catalog,public.school_space_badge_awards from public,anon,authenticated;

create or replace function school_private.community_room_access(p_room uuid) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.community_verified() and exists(select 1 from public.community_rooms r where r.id=p_room and r.status='approved' and not r.channel_archived and
 ((r.kind='class' and school_private.community_class_access(r.class_group))
 or (r.kind='school' and school_private.school_space_access())
 or (r.kind in ('dm','group') and exists(select 1 from public.community_room_members m where m.room_id=r.id and m.user_id=auth.uid()))));
$$;

create or replace function public.school_space_preferences(p_preferences jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_roles text[]; v_emoji text; v_id uuid; v_previous jsonb;
begin
 perform school_private.community_assert_actor(); perform school_private.community_limit('space_preferences',30,3600);
 perform school_private.assert_keys(p_preferences,array['status_text','status_emoji','status_emoji_id','name_color','theme','cosmetic_roles','space_onboarded','personal_tag'],'School-space preferences');
 select jsonb_build_object('status_text',p.status_text,'status_emoji',p.status_emoji,'status_emoji_id',p.status_emoji_id,'name_color',p.name_color,
 'theme',p.theme,'cosmetic_roles',p.cosmetic_roles,'space_onboarded',p.space_onboarded,'personal_tag',p.personal_tag)
 into v_previous from public.community_profiles p where p.user_id=auth.uid() for update;
 if not found then raise exception 'Complete your community profile first' using errcode='22023'; end if;
 p_preferences:=v_previous||p_preferences;
 if jsonb_typeof(p_preferences->'status_text') is distinct from 'string' or jsonb_typeof(p_preferences->'name_color') is distinct from 'string' or
 jsonb_typeof(p_preferences->'theme') is distinct from 'string' or (p_preferences->>'name_color') !~ '^#[0-9a-fA-F]{6}$' or p_preferences->>'theme' not in ('light','dark','system') or
 (jsonb_typeof(p_preferences->'status_emoji') not in ('null','string')) or (jsonb_typeof(p_preferences->'status_emoji_id') not in ('null','string')) or
 jsonb_typeof(p_preferences->'personal_tag') is distinct from 'string' or length(p_preferences->>'personal_tag')>24 then
  raise exception 'Use a valid status, name color, theme and personal tag' using errcode='22023'; end if;
 if jsonb_typeof(p_preferences->'cosmetic_roles') is distinct from 'array' then raise exception 'Choose interests from the catalog' using errcode='22023'; end if;
 select coalesce(array_agg(value),'{}') into v_roles from jsonb_array_elements_text(p_preferences->'cosmetic_roles');
 if cardinality(v_roles)>4 or cardinality(v_roles)<>(select count(distinct r) from unnest(v_roles) r) or
 not v_roles <@ array['creative','music','gaming','books','sports','night-owl','early-bird','pet-lover']::text[] then raise exception 'Choose up to four distinct interests' using errcode='22023'; end if;
 v_emoji:=nullif(p_preferences->>'status_emoji',''); v_id:=nullif(p_preferences->>'status_emoji_id','')::uuid;
 if v_emoji is not null and (length(v_emoji)>32 or v_emoji ~ '[[:cntrl:]]') then raise exception 'Use one emoji in your status' using errcode='22023'; end if;
 if v_id is not null and not exists(select 1 from public.community_emojis e where e.id=v_id and e.status='approved') then raise exception 'The status emoji must be approved first' using errcode='22023'; end if;
 if p_preferences->>'space_onboarded' is null or jsonb_typeof(p_preferences->'space_onboarded')<>'boolean' then raise exception 'Confirm server profile visibility' using errcode='22023'; end if;
 update public.community_profiles set status_text=coalesce(p_preferences->>'status_text',''),status_emoji=v_emoji,status_emoji_id=v_id,
 name_color=coalesce(p_preferences->>'name_color','#6546b5'),theme=coalesce(p_preferences->>'theme','system'),cosmetic_roles=v_roles,
 personal_tag=trim(p_preferences->>'personal_tag'),space_onboarded=(p_preferences->>'space_onboarded')::boolean,updated_at=now() where user_id=auth.uid();
 return public.school_space_get_state();
end; $$;

create or replace function public.school_space_members() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.school_space_access() then raise exception 'Join the server first' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('user_id',p.user_id,'real_name',p.real_name,'display_name',p.display_name,'personal_tag',p.personal_tag,
 'avatar_path',p.avatar_path,'banner_path',p.banner_path,'bio',p.bio,'class_group',p.class_group,'accent',p.accent,'accent_end',p.accent_end,
 'status_text',p.status_text,'status_emoji',p.status_emoji,'status_emoji_id',p.status_emoji_id,'name_color',p.name_color,'cosmetic_roles',p.cosmetic_roles,
 'badges',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'description',b.description,'emoji',b.emoji,'color',b.color)) from public.school_space_badge_awards a join public.school_space_badge_catalog b on b.id=a.badge_id and b.active where a.user_id=p.user_id),'[]'),
 'authority_role',school_private.school_space_role(p.user_id),'online',coalesce(pr.last_seen>now()-interval '90 seconds',false),'last_seen',pr.last_seen)
 order by case school_private.school_space_role(p.user_id) when 'Developer' then 1 when 'Teacher' then 2 when 'Moderator' then 3 else 4 end,coalesce(nullif(p.display_name,''),p.real_name))
 from public.community_profiles p left join public.school_space_presence pr on pr.user_id=p.user_id
 where p.space_onboarded and not exists(select 1 from public.school_space_roles s where s.user_id=p.user_id and s.kicked)
 and exists(select 1 from auth.users u where u.id=p.user_id and u.email_confirmed_at is not null) and not school_private.community_pair_blocked(auth.uid(),p.user_id)),'[]');
end; $$;

create or replace function public.school_space_get_state() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_profile jsonb; v_channels jsonb; v_members jsonb; v_server jsonb; v_badges jsonb;
begin
 if not school_private.community_verified() then raise exception 'Verified sign-in required' using errcode='42501'; end if;
 select jsonb_build_object('status_text',p.status_text,'status_emoji',p.status_emoji,'status_emoji_id',p.status_emoji_id,'name_color',p.name_color,'theme',p.theme,
 'cosmetic_roles',p.cosmetic_roles,'personal_tag',p.personal_tag,'space_onboarded',p.space_onboarded) into v_profile from public.community_profiles p where p.user_id=auth.uid();
 select jsonb_build_object('name',s.name,'description',s.description) into v_server from public.school_space_server s where s.id=true;
 if school_private.school_space_access() then
  select coalesce(jsonb_agg(to_jsonb(r.*) order by r.channel_category,r.title),'[]') into v_channels from public.community_rooms r where r.kind='school'
   and ((not r.channel_archived and school_private.community_room_access(r.id)) or (r.channel_archived and school_private.community_developer()));
  v_members:=public.school_space_members();
 else v_channels:='[]'; v_members:='[]'; end if;
 select coalesce(jsonb_agg(to_jsonb(b.*) order by b.name),'[]') into v_badges from public.school_space_badge_catalog b where b.active;
 return jsonb_build_object('profile',v_profile,'server',coalesce(v_server,jsonb_build_object('name','Itz’at Community','description','')),'channels',v_channels,'members',v_members,'badge_catalog',coalesce(v_badges,'[]'),
 'authority',school_private.school_space_authority(),
 'role_catalog',jsonb_build_array(jsonb_build_object('id','creative','label','Creative'),jsonb_build_object('id','music','label','Music'),jsonb_build_object('id','gaming','label','Gaming'),jsonb_build_object('id','books','label','Books'),jsonb_build_object('id','early-bird','label','Early bird'),jsonb_build_object('id','pet-lover','label','Pet lover'),jsonb_build_object('id','sports','label','Sports'),jsonb_build_object('id','night-owl','label','Night owl')));
end; $$;

create function public.school_space_update_server(p_name text,p_description text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer permission is required' using errcode='42501'; end if;
 if p_name is null or length(trim(p_name)) not between 2 and 60 or p_description is null or length(p_description)>240 then raise exception 'Use a server name up to 60 characters and description up to 240' using errcode='22023'; end if;
 update public.school_space_server set name=trim(p_name),description=trim(p_description),updated_by=auth.uid(),updated_at=now() where id=true;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'space.server.update',jsonb_build_object('name',trim(p_name)));
end; $$;

create function public.school_space_save_channel(p_id uuid,p_name text,p_description text,p_category text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_slug text;
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer permission is required' using errcode='42501'; end if;
 if p_name is null or length(trim(p_name)) not between 2 and 60 or p_description is null or length(p_description)>240 or p_category is null or length(trim(p_category)) not between 1 and 40 then raise exception 'Check the channel name, topic and category lengths' using errcode='22023'; end if;
 v_slug:=trim(both '_' from regexp_replace(lower(trim(p_name)),'[^a-z0-9]+','_','g'));
 if v_slug !~ '^[a-z0-9][a-z0-9_-]{0,47}$' then raise exception 'Choose a channel name with at least one letter or number' using errcode='22023'; end if;
 if p_id is null then
  insert into public.community_rooms(kind,title,status,school_channel,channel_category,description,channel_archived,created_by)
   values('school',trim(p_name),'approved',v_slug,trim(p_category),trim(p_description),false,auth.uid()) returning id into v_id;
 else
  update public.community_rooms set title=trim(p_name),school_channel=v_slug,channel_category=trim(p_category),description=trim(p_description),channel_archived=false
   where id=p_id and kind='school' returning id into v_id;
  if v_id is null then raise exception 'Choose an existing server channel' using errcode='22023'; end if;
 end if;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),case when p_id is null then 'space.channel.create' else 'space.channel.update' end,jsonb_build_object('channelId',v_id,'name',trim(p_name),'category',trim(p_category)));
 return v_id;
end; $$;

create function public.school_space_set_channel_archived(p_id uuid,p_archived boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() or p_archived is null then raise exception 'Developer permission is required' using errcode='42501'; end if;
 update public.community_rooms set channel_archived=p_archived where id=p_id and kind='school';
 if not found then raise exception 'Choose an existing server channel' using errcode='22023'; end if;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'space.channel.archive',jsonb_build_object('channelId',p_id,'archived',p_archived));
end; $$;

create function public.school_space_create_badge(p_name text,p_description text,p_emoji text,p_color text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer permission is required' using errcode='42501'; end if;
 if p_name is null or length(trim(p_name)) not between 2 and 32 or p_description is null or length(p_description)>120 or p_emoji is null or length(p_emoji)>16 or p_color !~ '^#[0-9a-fA-F]{6}$' then raise exception 'Check the badge name, description, emoji and color' using errcode='22023'; end if;
 insert into public.school_space_badge_catalog(name,description,emoji,color,created_by) values(trim(p_name),trim(p_description),coalesce(nullif(trim(p_emoji),''),'✦'),p_color,auth.uid()) returning id into v_id;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'space.badge.create',jsonb_build_object('badgeId',v_id,'name',trim(p_name)));
 return v_id;
end; $$;

create function public.school_space_award_badge(p_user uuid,p_badge uuid,p_active boolean default true) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer permission is required' using errcode='42501'; end if;
 if p_user is null or p_badge is null or p_active is null or not exists(select 1 from public.community_profiles p where p.user_id=p_user and p.space_onboarded)
 or exists(select 1 from public.school_space_roles s where s.user_id=p_user and s.kicked) or not exists(select 1 from public.school_space_badge_catalog b where b.id=p_badge and b.active) then
  raise exception 'Choose an active server member and badge' using errcode='22023'; end if;
 if p_active then
  insert into public.school_space_badge_awards(user_id,badge_id,awarded_by) values(p_user,p_badge,auth.uid()) on conflict(user_id,badge_id) do update set awarded_by=auth.uid(),awarded_at=now();
 else delete from public.school_space_badge_awards where user_id=p_user and badge_id=p_badge; end if;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),case when p_active then 'space.badge.award' else 'space.badge.revoke' end,jsonb_build_object('userId',p_user,'badgeId',p_badge));
end; $$;

do $$ declare f record; begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('school_space_update_server','school_space_save_channel','school_space_set_channel_archived','school_space_create_badge','school_space_award_badge') loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
  execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end; $$;
commit;
