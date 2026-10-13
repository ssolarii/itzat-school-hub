-- Admission, recipient consent and production community identity. No staff grants.
begin;

alter table public.school_space_server add column join_policy text not null default 'approval' check(join_policy in ('approval','verified'));

create table public.community_admissions (
 user_id uuid primary key references auth.users(id) on delete cascade,
 id uuid not null unique default gen_random_uuid(),
 name text not null check(length(trim(name)) between 1 and 120),
 note text not null default '' check(length(note)<=1000),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 requested_at timestamptz not null default now(),
 reviewed_by uuid references auth.users(id) on delete set null, reviewed_at timestamptz
);
alter table public.community_admissions enable row level security;
revoke all on public.community_admissions from public,anon,authenticated;

create function school_private.community_email_verified(p_user uuid default auth.uid()) returns boolean language sql stable security definer set search_path='' as $$
 select p_user is not null and exists(select 1 from auth.users where id=p_user and email_confirmed_at is not null);
$$;
create function school_private.community_admitted(p_user uuid default auth.uid()) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.community_email_verified(p_user) and
 (exists(select 1 from public.school_members where user_id=p_user and active)
 or exists(select 1 from public.community_admissions where user_id=p_user and status='approved')
 or exists(select 1 from public.school_space_server where id and join_policy='verified'));
$$;
-- Existing room/profile helpers, writes, Storage and Realtime all share this gate.
create or replace function school_private.community_verified() returns boolean language sql stable security definer set search_path='' as $$
 select school_private.community_admitted(auth.uid());
$$;
create function public.community_admission_state() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_email_verified() then raise exception 'Confirm your email first' using errcode='42501'; end if;
 return jsonb_build_object('admitted',school_private.community_admitted(),'can_review',school_private.community_developer(),
 'request',(select jsonb_build_object('id',id,'status',status,'name',name,'note',note,'requested_at',requested_at) from public.community_admissions where user_id=auth.uid()));
end; $$;
create function public.community_request_admission(p_name text,p_note text default '') returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not school_private.community_email_verified() then raise exception 'Confirm your email before requesting access' using errcode='42501'; end if;
 if p_name is null or length(trim(p_name)) not between 1 and 120 or p_note is null or length(p_note)>1000 then raise exception 'Enter your name and a note up to 1000 characters' using errcode='22023'; end if;
 perform school_private.community_limit('admission_request',3,86400);
 if school_private.community_admitted() then raise exception 'You already have chat access' using errcode='22023'; end if;
 insert into public.community_admissions(user_id,name,note) values(auth.uid(),trim(p_name),trim(p_note))
 on conflict(user_id) do update set name=excluded.name,note=excluded.note,status='pending',requested_at=now(),reviewed_by=null,reviewed_at=null
 returning id into v_id;
 return v_id;
end; $$;
create function public.community_admission_requests() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_verified() or not school_private.community_developer() then raise exception 'Developer permission required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(r.*)) from (select a.*,u.email from public.community_admissions a join auth.users u on u.id=a.user_id where a.status='pending' and u.email_confirmed_at is not null order by a.requested_at limit 100) r),'[]');
end; $$;
create function public.community_review_admission(p_id uuid,p_approve boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer permission required' using errcode='42501'; end if;
 if p_approve is null then raise exception 'Choose approve or decline' using errcode='22023'; end if;
 update public.community_admissions set status=case when p_approve then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=now()
 where id=p_id and status='pending' and school_private.community_email_verified(user_id);
 if not found then raise exception 'Verified pending request unavailable' using errcode='22023'; end if;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'community.admission.review',jsonb_build_object('requestId',p_id,'approved',p_approve));
end; $$;

create function school_private.community_icon_valid(p_key text) returns boolean language sql immutable set search_path='' as $$
 select p_key is null or p_key=any(array['star','award','heart','flame','sparkles','crown','shield-check','rosette','rocket','palette','music','device-gamepad','book','ball-football','moon','sun','coffee','code','school','planet','bolt','headphones','mood-smile']);
$$;
alter table public.community_profiles
 add column discovery_opt_in boolean not null default false,
 add column status_icon text check(school_private.community_icon_valid(status_icon)),
 add column featured_badge_id uuid references public.school_space_badge_catalog(id) on delete set null,
 add constraint community_status_one_symbol check(num_nonnulls(status_emoji,status_emoji_id,status_icon)<=1);
alter table public.school_space_badge_catalog add column icon_key text not null default 'award' check(school_private.community_icon_valid(icon_key));
alter table public.school_space_server
 add column icon_key text check(school_private.community_icon_valid(icon_key)),
 add column icon_path text,
 add constraint school_server_one_icon check(icon_key is null or icon_path is null);
alter table public.community_rooms add column posting_policy text not null default 'members' check(posting_policy in ('members','staff'));
update public.community_rooms set posting_policy='staff' where kind='school' and school_channel='announcements';

create function school_private.community_badges(p_user uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'description',b.description,'icon_key',b.icon_key,'color',b.color) order by a.awarded_at),'[]')
 from public.school_space_badge_awards a join public.school_space_badge_catalog b on b.id=a.badge_id and b.active
 where a.user_id=p_user and school_private.community_profile_access(p_user);
$$;
create function school_private.community_visible_identity(p_user uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',p.user_id,'display_name',p.display_name,'name_color',p.name_color,'accent',p.accent,'accent_end',p.accent_end)
 || case when school_private.community_profile_access(p.user_id) then jsonb_build_object(
 'real_name',p.real_name,'class_group',p.class_group,'avatar_path',p.avatar_path,'banner_path',p.banner_path,'bio',p.bio,
 'personal_tag',p.personal_tag,'cosmetic_roles',p.cosmetic_roles,'status_text',p.status_text,'status_emoji',p.status_emoji,'status_emoji_id',p.status_emoji_id,'status_icon',p.status_icon,
 'badges',school_private.community_badges(p.user_id),'featured_badge_id',case when exists(select 1 from public.school_space_badge_awards a join public.school_space_badge_catalog b on b.id=a.badge_id and b.active where a.user_id=p.user_id and a.badge_id=p.featured_badge_id) then p.featured_badge_id end)
 else jsonb_build_object('real_name','Community member') end
 from public.community_profiles p where p.user_id=p_user and school_private.community_admitted(p.user_id)
 and school_private.community_verified() and not school_private.community_pair_blocked(auth.uid(),p.user_id);
$$;
create or replace function public.community_profiles_directory() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_verified() then raise exception 'Chat admission required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(r.identity) from (select school_private.community_visible_identity(p.user_id) identity from public.community_profiles p where school_private.community_admitted(p.user_id) and not school_private.community_pair_blocked(auth.uid(),p.user_id) order by p.user_id limit 500) r where r.identity is not null),'[]');
end; $$;
create or replace function public.community_list_friends() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_verified() then raise exception 'Chat admission required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(f.*)||school_private.community_visible_identity(p.user_id)||jsonb_build_object('other_id',p.user_id) order by f.updated_at desc)
 from public.community_friendships f join public.community_profiles p on p.user_id=case when f.requested_by=auth.uid() then f.recipient_id else f.requested_by end
 where auth.uid() in (f.requested_by,f.recipient_id) and f.status in ('pending','accepted') and school_private.community_admitted(p.user_id)
 and not school_private.community_pair_blocked(f.requested_by,f.recipient_id)),'[]');
end; $$;
create or replace function public.school_space_members() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.school_space_access() then raise exception 'Join the server first' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(school_private.community_visible_identity(p.user_id)||jsonb_build_object('authority_role',school_private.school_space_role(p.user_id),'online',coalesce(pr.last_seen>now()-interval '90 seconds',false)) order by p.user_id)
 from public.community_profiles p left join public.school_space_presence pr on pr.user_id=p.user_id
 where p.space_onboarded and school_private.community_admitted(p.user_id) and not exists(select 1 from public.school_space_roles s where s.user_id=p.user_id and s.kicked)
 and not school_private.community_pair_blocked(auth.uid(),p.user_id)),'[]');
end; $$;
create function public.community_discover(p_limit integer default 20) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.school_space_access() then raise exception 'Join the server first' using errcode='42501'; end if;
 if p_limit is null or p_limit not between 1 and 50 then raise exception 'Choose a result limit from 1 to 50' using errcode='22023'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('user_id',r.user_id,'display_name',r.display_name,'avatar_path',r.avatar_path,'name_color',r.name_color,'shared_interests',r.shared_interests) order by cardinality(r.shared_interests) desc,r.user_id) from (
 select p.user_id,p.display_name,p.avatar_path,p.name_color,array(select unnest(p.cosmetic_roles) intersect select unnest(own.cosmetic_roles)) shared_interests
 from public.community_profiles p join public.community_profiles own on own.user_id=auth.uid()
 where own.discovery_opt_in and p.user_id<>auth.uid() and p.discovery_opt_in and p.space_onboarded and school_private.community_admitted(p.user_id)
 and p.cosmetic_roles && own.cosmetic_roles and not school_private.community_pair_blocked(auth.uid(),p.user_id)
 and not exists(select 1 from public.school_space_roles s where s.user_id=p.user_id and s.kicked)
 and not exists(select 1 from public.community_friendships f where auth.uid() in (f.requested_by,f.recipient_id) and p.user_id in (f.requested_by,f.recipient_id) and f.status in ('pending','accepted'))
 order by cardinality(array(select unnest(p.cosmetic_roles) intersect select unnest(own.cosmetic_roles))) desc,p.user_id limit p_limit) r),'[]');
end; $$;

-- Preserve the established validators while adding private preferences atomically.
alter function public.school_space_preferences(jsonb) set schema school_private;
alter function school_private.school_space_preferences(jsonb) rename to school_space_preferences_v7;
create function public.school_space_preferences(p_preferences jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_badge uuid; v_icon text; v_preferences jsonb;
begin
 perform school_private.community_assert_actor();
 perform school_private.assert_keys(p_preferences,array['status_text','status_emoji','status_emoji_id','status_icon','name_color','theme','cosmetic_roles','space_onboarded','personal_tag','discovery_opt_in','featured_badge_id'],'Community preferences');
 if p_preferences ? 'discovery_opt_in' and jsonb_typeof(p_preferences->'discovery_opt_in') is distinct from 'boolean' then raise exception 'Choose whether to appear in Discovery' using errcode='22023'; end if;
 if p_preferences ? 'status_icon' then
  if jsonb_typeof(p_preferences->'status_icon') not in ('string','null') then raise exception 'Choose a status icon' using errcode='22023'; end if;
  v_icon:=nullif(p_preferences->>'status_icon','');
  if not school_private.community_icon_valid(v_icon) then raise exception 'Choose an available status icon' using errcode='22023'; end if;
 end if;
 if p_preferences ? 'featured_badge_id' then
  v_badge:=nullif(p_preferences->>'featured_badge_id','')::uuid;
  if v_badge is not null and not exists(select 1 from public.school_space_badge_awards a join public.school_space_badge_catalog b on b.id=a.badge_id and b.active where a.user_id=auth.uid() and a.badge_id=v_badge) then raise exception 'Choose one of your awarded badges' using errcode='22023'; end if;
 end if;
 -- Clear the prior symbol before validation so an icon/emoji switch is atomic.
 if p_preferences ? 'status_icon' or p_preferences ? 'status_emoji' or p_preferences ? 'status_emoji_id' then
  update public.community_profiles set status_icon=null where user_id=auth.uid();
 end if;
 v_preferences:=p_preferences-'discovery_opt_in'-'featured_badge_id'-'status_icon';
 if v_icon is not null then v_preferences:=v_preferences||jsonb_build_object('status_emoji',null,'status_emoji_id',null); end if;
 perform school_private.school_space_preferences_v7(v_preferences);
 update public.community_profiles set
 discovery_opt_in=case when p_preferences ? 'discovery_opt_in' then (p_preferences->>'discovery_opt_in')::boolean else discovery_opt_in end,
 featured_badge_id=case when p_preferences ? 'featured_badge_id' then v_badge else featured_badge_id end,
 status_icon=case when p_preferences ? 'status_icon' then v_icon else status_icon end
 where user_id=auth.uid();
 return public.school_space_get_state();
end; $$;

alter function public.school_space_get_state() set schema school_private;
alter function school_private.school_space_get_state() rename to school_space_get_state_v7;
create function public.school_space_get_state() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
 v_result:=school_private.school_space_get_state_v7();
 return v_result||jsonb_build_object('profile',coalesce(nullif(v_result->'profile','null'::jsonb),'{}')||coalesce((select jsonb_build_object('discovery_opt_in',p.discovery_opt_in,'status_icon',p.status_icon,'featured_badge_id',p.featured_badge_id,'badges',school_private.community_badges(p.user_id)) from public.community_profiles p where p.user_id=auth.uid()),'{}'),
 'server',(select jsonb_build_object('name',name,'description',description,'icon_key',icon_key,'icon_path',icon_path,'join_policy',join_policy) from public.school_space_server where id));
end; $$;

drop function public.school_space_update_server(text,text);
create function public.school_space_update_server(p_name text,p_description text,p_icon_key text default null,p_icon_path text default null,p_join_policy text default null) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer permission required' using errcode='42501'; end if;
 if p_name is null or length(trim(p_name)) not between 2 and 60 or p_description is null or length(p_description)>240 or not school_private.community_icon_valid(p_icon_key) or (p_icon_key is not null and p_icon_path is not null) then raise exception 'Check server name, description and icon' using errcode='22023'; end if;
 if not school_private.community_owns_media(p_icon_path) then raise exception 'Upload your own server image first' using errcode='42501'; end if;
 if p_join_policy is not null and p_join_policy not in ('approval','verified') then raise exception 'Choose an available admission policy' using errcode='22023'; end if;
 update public.school_space_server set join_policy=coalesce(p_join_policy,join_policy),name=trim(p_name),description=trim(p_description),icon_key=p_icon_key,icon_path=p_icon_path,updated_by=auth.uid(),updated_at=now() where id;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'space.server.update',jsonb_build_object('name',trim(p_name),'join_policy',p_join_policy));
end; $$;
drop function public.school_space_create_badge(text,text,text,text);
create function public.school_space_create_badge(p_name text,p_description text,p_icon_key text,p_color text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer permission required' using errcode='42501'; end if;
 if p_name is null or length(trim(p_name)) not between 2 and 32 or p_description is null or length(p_description)>120 or p_icon_key is null or not school_private.community_icon_valid(p_icon_key) or p_color is null or p_color !~ '^#[0-9a-fA-F]{6}$' then raise exception 'Check badge name, icon and color' using errcode='22023'; end if;
 insert into public.school_space_badge_catalog(name,description,icon_key,color,created_by) values(trim(p_name),trim(p_description),p_icon_key,p_color,auth.uid()) returning id into v_id;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'space.badge.create',jsonb_build_object('badgeId',v_id)); return v_id;
end; $$;

alter table public.community_room_members add column consent text not null default 'accepted' check(consent in ('pending','accepted','declined','left'));
alter table public.community_room_members add column responded_at timestamptz;

create or replace function public.community_list_rooms(p_pending boolean default false) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_verified() then raise exception 'Chat admission required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(r.*)||jsonb_build_object('participants',coalesce((select jsonb_agg(m.user_id) from public.community_room_members m where m.room_id=r.id),'[]'),'my_consent',(select consent from public.community_room_members m where m.room_id=r.id and m.user_id=auth.uid()),'can_respond',exists(select 1 from public.community_room_members m where m.room_id=r.id and m.user_id=auth.uid() and m.consent='pending'),'direction',case when r.created_by=auth.uid() then 'outgoing' else 'incoming' end) order by r.created_at)
 from public.community_rooms r where not r.channel_archived and case when p_pending then r.kind in ('dm','group') and exists(select 1 from public.community_room_members m where m.room_id=r.id and m.user_id=auth.uid() and m.consent='pending')
 else school_private.community_room_access(r.id) or r.created_by=auth.uid() or exists(select 1 from public.community_room_members m where m.room_id=r.id and m.user_id=auth.uid() and m.consent in ('pending','accepted')) end),'[]');
end; $$;

create table public.community_invites (
 id uuid primary key default gen_random_uuid(), token_hash text not null unique,
 created_by uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '7 days',
 redeemed_by uuid references auth.users(id) on delete set null, redeemed_at timestamptz,
 revoked boolean not null default false
);
alter table public.community_invites enable row level security;
revoke all on public.community_invites from public,anon,authenticated;
create function public.community_create_invite() returns jsonb language plpgsql security definer set search_path='' as $$
declare v_token text; v_id uuid; v_expires timestamptz;
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer permission required' using errcode='42501'; end if;
 perform school_private.community_limit('invite',30,3600);
 v_token:=replace(gen_random_uuid()::text||gen_random_uuid()::text,'-','');
 insert into public.community_invites(token_hash,created_by) values(encode(sha256(convert_to(v_token,'UTF8')),'hex'),auth.uid()) returning id,expires_at into v_id,v_expires;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'community.invite.create',jsonb_build_object('inviteId',v_id,'expiresAt',v_expires));
 return jsonb_build_object('id',v_id,'token',v_token,'expires_at',v_expires);
end; $$;
create function public.community_redeem_invite(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_invite public.community_invites;
begin
 if not school_private.community_email_verified() then raise exception 'Confirm your email first' using errcode='42501'; end if;
 if p_token is null or p_token !~ '^[0-9a-f]{64}$' then raise exception 'Invite unavailable or expired' using errcode='22023'; end if;
 perform school_private.community_limit('redeem_invite',10,3600);
 select * into v_invite from public.community_invites where token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex') for update;
 if not found or v_invite.revoked or v_invite.redeemed_at is not null or v_invite.expires_at<=now() then raise exception 'Invite unavailable or expired' using errcode='22023'; end if;
 insert into public.community_admissions(user_id,name,status,reviewed_by,reviewed_at) values(auth.uid(),coalesce((select real_name from public.community_profiles where user_id=auth.uid()),'Invited member'),'approved',v_invite.created_by,now())
 on conflict(user_id) do update set status='approved',reviewed_by=excluded.reviewed_by,reviewed_at=now();
 update public.community_invites set redeemed_by=auth.uid(),redeemed_at=now() where id=v_invite.id;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'community.invite.redeem',jsonb_build_object('inviteId',v_invite.id));
 return public.community_admission_state();
end; $$;
create function public.community_revoke_invite(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer permission required' using errcode='42501'; end if;
 update public.community_invites set revoked=true where id=p_id;
 if not found then raise exception 'Invite unavailable' using errcode='22023'; end if;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'community.invite.revoke',jsonb_build_object('inviteId',p_id));
end; $$;

create or replace function school_private.community_room_access(p_room uuid) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.community_verified() and exists(select 1 from public.community_rooms r where r.id=p_room and r.status='approved' and not r.channel_archived and
 ((r.kind='class' and school_private.community_class_access(r.class_group))
 or (r.kind='school' and school_private.school_space_access())
 or (r.kind in ('dm','group') and exists(select 1 from public.community_room_members m where m.room_id=r.id and m.user_id=auth.uid() and m.consent='accepted'))));
$$;
create or replace function school_private.community_profile_access(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.community_verified() and school_private.community_admitted(p_user) and (p_user=auth.uid() or school_private.is_leadership()
 or exists(select 1 from public.community_profiles p where p.user_id=p_user and p.audience='student' and school_private.community_class_access(p.class_group))
 or (not school_private.community_pair_blocked(auth.uid(),p_user) and (
 school_private.community_friend_access(p_user)
 or (school_private.school_space_access() and exists(select 1 from public.community_profiles p where p.user_id=p_user and p.space_onboarded) and not exists(select 1 from public.school_space_roles s where s.user_id=p_user and s.kicked))
 or exists(select 1 from public.community_room_members m where m.user_id=p_user and m.consent='accepted' and school_private.community_room_access(m.room_id)))));
$$;

create or replace function public.community_request_room(p_kind text,p_title text,p_participants uuid[]) returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_id uuid; v_people uuid[]; v_pair record; v_all_friends boolean;
begin
 v_actor:=school_private.community_assert_actor(); perform school_private.community_limit('room',5,3600);
 if p_kind is null or p_kind not in ('dm','group') or coalesce(length(trim(p_title)),0) not between 1 and 100 or p_participants is null then raise exception 'Choose a conversation type, title and members' using errcode='22023'; end if;
 select array_agg(distinct u order by u) into v_people from unnest(array_append(p_participants,v_actor)) u;
 if cardinality(v_people) not between 2 and 30 or (p_kind='dm' and cardinality(v_people)<>2) or exists(select 1 from unnest(v_people) u where u is null or not school_private.community_admitted(u) or not exists(select 1 from public.community_profiles p where p.user_id=u)) then raise exception 'Choose admitted community members' using errcode='22023'; end if;
 for v_pair in select a,b from unnest(v_people) a cross join unnest(v_people) b where a<b order by a,b loop
  perform school_private.community_lock_pair(v_pair.a,v_pair.b);
  if school_private.community_pair_blocked(v_pair.a,v_pair.b) then raise exception 'A selected member is unavailable' using errcode='42501'; end if;
 end loop;
 if p_kind='dm' then
  select r.id into v_id from public.community_rooms r where r.kind='dm' and r.status in ('pending','approved')
  and (select array_agg(m.user_id order by m.user_id) from public.community_room_members m where m.room_id=r.id and m.consent in ('pending','accepted'))=v_people limit 1;
  if v_id is not null then return v_id; end if;
 end if;
 select bool_and(u=v_actor or school_private.community_friend_access(u)) into v_all_friends from unnest(v_people) u;
 insert into public.community_rooms(kind,title,created_by,status) values(p_kind,trim(p_title),v_actor,case when p_kind='group' or v_all_friends then 'approved' else 'pending' end) returning id into v_id;
 insert into public.community_room_members(room_id,user_id,consent) select v_id,u,case when u=v_actor or school_private.community_friend_access(u) then 'accepted' else 'pending' end from unnest(v_people) u;
 return v_id;
end; $$;
create function public.community_respond_room(p_id uuid,p_accept boolean) returns void language plpgsql security definer set search_path='' as $$
declare v_room public.community_rooms; v_member uuid;
begin
 perform school_private.community_assert_actor();
 if p_accept is null then raise exception 'Choose accept or decline' using errcode='22023'; end if;
 perform school_private.community_limit('room_response',30,3600);
 select * into v_room from public.community_rooms where id=p_id and kind in ('dm','group') and not channel_archived for update;
 if not found or not exists(select 1 from public.community_room_members where room_id=p_id and user_id=auth.uid() and consent='pending') then raise exception 'This invitation is unavailable' using errcode='42501'; end if;
 if p_accept then
  for v_member in select user_id from public.community_room_members where room_id=p_id and consent='accepted' order by user_id loop
   perform school_private.community_lock_pair(least(auth.uid(),v_member),greatest(auth.uid(),v_member));
   if school_private.community_pair_blocked(auth.uid(),v_member) then raise exception 'This invitation is unavailable' using errcode='42501'; end if;
  end loop;
 end if;
 update public.community_room_members set consent=case when p_accept then 'accepted' else 'declined' end,responded_at=now() where room_id=p_id and user_id=auth.uid();
 if v_room.kind='dm' then update public.community_rooms set status=case when p_accept then 'approved' else 'rejected' end where id=p_id; end if;
end; $$;
create function public.community_leave_room(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 perform 1 from public.community_rooms where id=p_id and kind in ('dm','group') for update;
 if not found then raise exception 'Choose a private conversation' using errcode='22023'; end if;
 update public.community_room_members set consent='left',responded_at=now() where room_id=p_id and user_id=auth.uid() and consent in ('pending','accepted');
 if not found then raise exception 'You are not a member of this conversation' using errcode='42501'; end if;
end; $$;
create or replace function public.community_review_room(p_id uuid,p_approve boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 raise exception 'Private conversation requests are accepted by their recipients' using errcode='42501';
end; $$;

-- The immutable posting policy survives title/slug edits; room access also checks consent.
create or replace function public.community_send_message(p_room uuid,p_body text,p_media_path text default null,p_emoji uuid default null,p_gif_url text default null) returns bigint language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_id bigint; v_other uuid;
begin
 v_actor:=school_private.community_assert_actor();
 if not school_private.community_room_access(p_room) then raise exception 'Join or accept this conversation first' using errcode='42501'; end if;
 if exists(select 1 from public.community_rooms where id=p_room and kind='school' and posting_policy='staff') and not school_private.school_space_permission('manage_messages') then raise exception 'Only approved staff can post in this channel' using errcode='42501'; end if;
 if exists(select 1 from public.community_rooms where id=p_room and kind='dm') then
  select m.user_id into v_other from public.community_room_members m where m.room_id=p_room and m.user_id<>v_actor;
  perform school_private.community_lock_pair(v_actor,v_other);
  if school_private.community_pair_blocked(v_actor,v_other) then raise exception 'Direct messaging is unavailable' using errcode='42501'; end if;
 end if;
 perform school_private.community_limit('message',30,60);
 if not school_private.community_owns_media(p_media_path) then raise exception 'Use your own uploaded media' using errcode='42501'; end if;
 if p_emoji is not null and not exists(select 1 from public.community_emojis where id=p_emoji and status='approved') then raise exception 'Emoji is not approved' using errcode='22023'; end if;
 insert into public.community_messages(room_id,author_id,body,media_path,emoji_id,gif_url) values(p_room,v_actor,trim(coalesce(p_body,'')),p_media_path,p_emoji,p_gif_url) returning id into v_id; return v_id;
end; $$;

-- Protect direct friend RPC calls as well as directory-based UI discovery.
alter function public.community_request_friend(uuid) set schema school_private;
alter function school_private.community_request_friend(uuid) rename to community_request_friend_v5;
create function public.community_request_friend(p_user uuid) returns uuid language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if not school_private.community_admitted(p_user) then raise exception 'Member unavailable' using errcode='42501'; end if;
 return school_private.community_request_friend_v5(p_user);
end; $$;

create or replace function school_private.community_owns_media(p_path text) returns boolean language sql stable security definer set search_path='' as $$
 select p_path is null or (p_path ~ ('^'||auth.uid()::text||'/(avatar|banner|emoji|chat|server)/[a-zA-Z0-9_.-]+$') and
 exists(select 1 from storage.objects o where o.bucket_id='community-media' and o.name=p_path and o.owner_id=auth.uid()::text));
$$;
create or replace function school_private.community_upload_allowed(p_path text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if p_path !~ ('^'||auth.uid()::text||'/(avatar|banner|emoji|chat|server)/[a-zA-Z0-9_.-]+$') then return false; end if;
 if split_part(p_path,'/',2)='server' and not school_private.community_developer() then return false; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,110004));
 perform school_private.community_limit('upload',10,3600);
 if (select count(*) from storage.objects o where o.bucket_id='community-media' and o.owner_id=auth.uid()::text)>=100 then raise exception 'Your image limit has been reached; contact the Developer' using errcode='22023'; end if;
 return true;
end; $$;
alter function school_private.community_media_read(text) rename to community_media_read_v4;
create function school_private.community_media_read(p_path text) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.community_verified() and (school_private.community_media_read_v4(p_path) or exists(select 1 from public.school_space_server where id and icon_path=p_path));
$$;
-- Policy dependencies are bound to function identity, so explicitly recreate this one.
drop policy community_media_select on storage.objects;
create policy community_media_select on storage.objects for select to authenticated using(bucket_id='community-media' and school_private.community_media_read(name));

create function school_private.community_badge_unfeature() returns trigger language plpgsql security definer set search_path='' as $$
begin
 update public.community_profiles set featured_badge_id=null where user_id=old.user_id and featured_badge_id=old.badge_id;
 return old;
end; $$;
create trigger community_badge_unfeature after delete on public.school_space_badge_awards for each row execute function school_private.community_badge_unfeature();

drop function public.school_space_save_channel(uuid,text,text,text);
create function public.school_space_save_channel(p_id uuid,p_name text,p_description text,p_category text,p_posting_policy text default 'members') returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_slug text;
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer permission required' using errcode='42501'; end if;
 if p_name is null or length(trim(p_name)) not between 2 and 60 or p_description is null or length(p_description)>240 or p_category is null or length(trim(p_category)) not between 1 and 40 or p_posting_policy is null or p_posting_policy not in ('members','staff') then raise exception 'Check the channel name, topic, category and posting permissions' using errcode='22023'; end if;
 v_slug:=trim(both '_' from regexp_replace(lower(trim(p_name)),'[^a-z0-9]+','_','g'));
 if v_slug !~ '^[a-z0-9][a-z0-9_-]{0,47}$' then raise exception 'Choose a channel name with letters or numbers' using errcode='22023'; end if;
 if p_id is null then
  insert into public.community_rooms(kind,title,status,school_channel,channel_category,description,posting_policy,created_by) values('school',trim(p_name),'approved',v_slug,trim(p_category),trim(p_description),p_posting_policy,auth.uid()) returning id into v_id;
 else
  update public.community_rooms set title=trim(p_name),school_channel=v_slug,channel_category=trim(p_category),description=trim(p_description),posting_policy=p_posting_policy where id=p_id and kind='school' returning id into v_id;
  if not found then raise exception 'Channel unavailable' using errcode='22023'; end if;
 end if;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'space.channel.save',jsonb_build_object('channelId',v_id,'postingPolicy',p_posting_policy));
 return v_id;
end; $$;

-- Any Unicode emoji sequence is accepted, including flags, skin tones and joined emoji.
-- The status field cannot contain markup or ordinary prose; custom images use their approved id.
create function school_private.community_emoji_valid(p_text text) returns boolean language sql immutable set search_path='' as $$
 select p_text is null or (length(p_text) between 1 and 32 and
 exists(select 1 from unnest(string_to_array(p_text,null)) c where ascii(c) between 9728 and 129791 or ascii(c) in (169,174,8252,8265,8482,8505,8419,12336,12349,12951,12953) or ascii(c) between 8596 and 8601 or ascii(c) between 8617 and 8618 or ascii(c) between 8986 and 9210 or ascii(c) in (9410,9642,9643,9654,9664)) and
 not exists(select 1 from unnest(string_to_array(p_text,null)) c where not (ascii(c) between 9728 and 129791 or ascii(c) between 917536 and 917631 or ascii(c) between 8596 and 8601 or ascii(c) between 8617 and 8618 or ascii(c) between 8986 and 9210 or ascii(c) in (169,174,8252,8265,8482,8505,8419,12336,12349,12951,12953,9410,9642,9643,9654,9664,8205,65039,65038,35,42) or ascii(c) between 48 and 57)));
$$;
alter table public.community_profiles add constraint community_status_emoji_valid check(school_private.community_emoji_valid(status_emoji));

-- A creator who leaves a room does not retain membership through room ownership.
create or replace function public.community_list_rooms(p_pending boolean default false) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_verified() then raise exception 'Chat admission required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(r.*)||jsonb_build_object('participants',coalesce((select jsonb_agg(m.user_id) from public.community_room_members m where m.room_id=r.id and m.consent in ('pending','accepted')),'[]'),'my_consent',(select consent from public.community_room_members m where m.room_id=r.id and m.user_id=auth.uid()),'can_respond',exists(select 1 from public.community_room_members m where m.room_id=r.id and m.user_id=auth.uid() and m.consent='pending'),'direction',case when r.created_by=auth.uid() then 'outgoing' else 'incoming' end) order by r.created_at)
 from public.community_rooms r where not r.channel_archived and r.status in ('pending','approved') and case when p_pending then r.kind in ('dm','group') and exists(select 1 from public.community_room_members m where m.room_id=r.id and m.user_id=auth.uid() and m.consent='pending')
 else school_private.community_room_access(r.id) or exists(select 1 from public.community_room_members m where m.room_id=r.id and m.user_id=auth.uid() and m.consent in ('pending','accepted')) end),'[]');
end; $$;

create function public.community_list_invites() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_verified() or not school_private.community_developer() then raise exception 'Developer permission required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(i)) from (select id,created_at,expires_at,redeemed_at,revoked from public.community_invites order by created_at desc limit 100) i),'[]');
end; $$;

-- Function moves retain grants. Remove access to all internal aliases and pin RPC access.
do $$ declare f record; begin
 for f in select p.oid::regprocedure signature,n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('public','school_private') and (p.proname like 'community_%' or p.proname like 'school_space_%') loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
  if f.nspname='public' then execute format('grant execute on function %s to authenticated',f.signature); end if;
 end loop;
end; $$;
grant execute on function school_private.community_verified(),school_private.community_developer(),school_private.community_class_access(text),school_private.community_room_access(uuid),school_private.community_profile_access(uuid),school_private.community_post_access(uuid),school_private.community_media_read(text),school_private.community_upload_allowed(text),school_private.school_space_access(),school_private.school_space_permission(text) to authenticated;
grant execute on function school_private.community_post_access(uuid) to anon;
grant execute on function public.community_list_posts(text,text,boolean) to anon;
commit;
