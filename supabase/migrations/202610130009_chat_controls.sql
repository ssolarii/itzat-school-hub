begin;
alter table public.community_rooms add column speaking_roles text[];
alter table public.community_rooms add column slowmode_seconds integer not null default 0 check(slowmode_seconds between 0 and 3600);
alter table public.community_rooms add constraint school_channel_roles check(speaking_roles is null or (cardinality(speaking_roles) between 1 and 5 and speaking_roles <@ array['Developer','Teacher','Moderator','Student','Member']::text[]));
alter table public.school_space_server add column custom_rate_enabled boolean not null default false;
alter table public.school_space_server add column message_limit integer not null default 10 check(message_limit between 1 and 30);
alter table public.school_space_server add column message_window_seconds integer not null default 60 check(message_window_seconds between 10 and 3600);

create function school_private.channel_can_speak(p_room uuid) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.community_room_access(p_room) and exists(select 1 from public.community_rooms r where r.id=p_room and
 (r.kind<>'school' or school_private.community_developer() or
 case when r.speaking_roles is not null then school_private.school_space_role(auth.uid())=any(r.speaking_roles)
 else r.posting_policy='members' or school_private.school_space_permission('manage_messages') end));
$$;

create function public.school_space_save_channel_controls(p_id uuid,p_name text,p_description text,p_category text,p_posting_policy text,p_speaking_roles text[],p_slowmode_seconds integer) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer permission required' using errcode='42501'; end if;
 if p_slowmode_seconds is null or p_slowmode_seconds not between 0 and 3600 or (p_speaking_roles is not null and (cardinality(p_speaking_roles) not between 1 and 5 or not p_speaking_roles <@ array['Developer','Teacher','Moderator','Student','Member']::text[] or array_position(p_speaking_roles,null) is not null)) then raise exception 'Choose valid roles and a slow mode from 0 to 3600 seconds' using errcode='22023'; end if;
 v_id:=public.school_space_save_channel(p_id,p_name,p_description,p_category,p_posting_policy);
 update public.community_rooms set speaking_roles=p_speaking_roles,slowmode_seconds=p_slowmode_seconds where id=v_id;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'space.channel.controls',jsonb_build_object('channelId',v_id,'roles',p_speaking_roles,'slowmodeSeconds',p_slowmode_seconds));
 return v_id;
end; $$;

create function public.school_space_set_rate_limit(p_enabled boolean,p_limit integer,p_window_seconds integer) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer permission required' using errcode='42501'; end if;
 if p_enabled is null or p_limit is null or p_limit not between 1 and 30 or p_window_seconds is null or p_window_seconds not between 10 and 3600 then raise exception 'Choose 1–30 messages and a window of 10–3600 seconds' using errcode='22023'; end if;
 update public.school_space_server set custom_rate_enabled=p_enabled,message_limit=p_limit,message_window_seconds=p_window_seconds,updated_by=auth.uid(),updated_at=now() where id;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'space.rate_limit.update',jsonb_build_object('enabled',p_enabled,'messages',p_limit,'windowSeconds',p_window_seconds));
end; $$;

alter function public.school_space_get_state() set schema school_private;
alter function school_private.school_space_get_state() rename to school_space_get_state_v8;
create function public.school_space_get_state() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
 v_result:=school_private.school_space_get_state_v8();
 return v_result||jsonb_build_object('server',v_result->'server'||(select jsonb_build_object('custom_rate_enabled',custom_rate_enabled,'message_limit',message_limit,'message_window_seconds',message_window_seconds) from public.school_space_server where id));
end; $$;

create table public.community_user_reports (
 id uuid primary key default gen_random_uuid(),
 target_id uuid not null references auth.users(id),
 reporter_id uuid not null references auth.users(id),
 category text not null check(category in ('spam','harassment','unsafe_content','impersonation','other')),
 reason text not null check(length(trim(reason)) between 1 and 1000),
 status text not null default 'open' check(status in ('open','resolved','dismissed')),
 created_at timestamptz not null default now(),reviewed_by uuid references auth.users(id),reviewed_at timestamptz,
 check(target_id<>reporter_id)
);
create unique index one_open_user_report on public.community_user_reports(target_id,reporter_id) where status='open';
alter table public.community_user_reports enable row level security;
revoke all on public.community_user_reports from public,anon,authenticated;
create function public.community_report_user(p_user uuid,p_category text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if p_user=auth.uid() or not school_private.community_profile_access(p_user) then raise exception 'Choose another visible community member' using errcode='42501'; end if;
 perform school_private.community_limit('user_report',5,3600);
 insert into public.community_user_reports(target_id,reporter_id,category,reason) values(p_user,auth.uid(),p_category,trim(p_reason))
 on conflict(target_id,reporter_id) where status='open' do update set category=excluded.category,reason=excluded.reason;
end; $$;
create function public.community_list_user_reports() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_developer() then raise exception 'Developer review required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(r.*)||jsonb_build_object('target_name',coalesce(nullif(p.display_name,''),p.real_name,'Member')) order by r.created_at) from public.community_user_reports r left join public.community_profiles p on p.user_id=r.target_id where r.status='open'),'[]');
end; $$;
create function public.community_review_user_report(p_id uuid,p_action text) returns void language plpgsql security definer set search_path='' as $$
declare v_target uuid;
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer review required' using errcode='42501'; end if;
 if p_action is null or p_action not in ('resolve','dismiss','kick') then raise exception 'Choose a review action' using errcode='22023'; end if;
 select target_id into v_target from public.community_user_reports where id=p_id and status='open' for update;
 if not found then raise exception 'Report is no longer open' using errcode='22023'; end if;
 if p_action='kick' then perform public.school_space_kick(v_target,true); end if;
 update public.community_user_reports set status=case when p_action='dismiss' then 'dismissed' else 'resolved' end,reviewed_by=auth.uid(),reviewed_at=now() where id=p_id;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'community.user_report.review',jsonb_build_object('reportId',p_id,'action',p_action));
end; $$;
revoke all on function school_private.channel_can_speak(uuid),school_private.school_space_get_state_v8() from public,anon,authenticated;
revoke all on function public.school_space_save_channel_controls(uuid,text,text,text,text,text[],integer),public.school_space_set_rate_limit(boolean,integer,integer),public.school_space_get_state(),public.community_report_user(uuid,text,text),public.community_list_user_reports(),public.community_review_user_report(uuid,text) from public,anon;
grant execute on function public.school_space_save_channel_controls(uuid,text,text,text,text,text[],integer),public.school_space_set_rate_limit(boolean,integer,integer),public.school_space_get_state(),public.community_report_user(uuid,text,text),public.community_list_user_reports(),public.community_review_user_report(uuid,text) to authenticated;

create or replace function public.community_send_message(p_room uuid,p_body text,p_media_path text default null,p_emoji uuid default null,p_gif_url text default null) returns bigint language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_id bigint; v_other uuid; v_room public.community_rooms; v_server public.school_space_server;
begin
 v_actor:=school_private.community_assert_actor();
 if not school_private.community_room_access(p_room) then raise exception 'Join or accept this conversation first' using errcode='42501'; end if;
 if not school_private.channel_can_speak(p_room) then raise exception 'Your role cannot post in this channel' using errcode='42501'; end if;
 if exists(select 1 from public.community_rooms where id=p_room and kind='dm') then
  select m.user_id into v_other from public.community_room_members m where m.room_id=p_room and m.user_id<>v_actor;
  perform school_private.community_lock_pair(v_actor,v_other);
  if school_private.community_pair_blocked(v_actor,v_other) then raise exception 'Direct messaging is unavailable' using errcode='42501'; end if;
 end if;
 perform school_private.community_limit('message',30,60);
 select * into v_room from public.community_rooms where id=p_room;
 if v_room.kind='school' then
  select * into v_server from public.school_space_server where id;
  if v_server.custom_rate_enabled then perform school_private.community_limit('school_messages',v_server.message_limit,v_server.message_window_seconds); end if;
  if v_room.slowmode_seconds>0 then
   begin perform school_private.community_limit('channel:'||p_room::text,1,v_room.slowmode_seconds);
   exception when sqlstate 'P0001' then raise exception 'Slow mode: wait % seconds between messages in this channel',v_room.slowmode_seconds using errcode='P0001'; end;
  end if;
 end if;
 if not school_private.community_owns_media(p_media_path) then raise exception 'Use your own uploaded media' using errcode='42501'; end if;
 if p_emoji is not null and not exists(select 1 from public.community_emojis where id=p_emoji and status='approved') then raise exception 'Emoji is not approved' using errcode='22023'; end if;
 insert into public.community_messages(room_id,author_id,body,media_path,emoji_id,gif_url) values(p_room,v_actor,trim(coalesce(p_body,'')),p_media_path,p_emoji,p_gif_url) returning id into v_id; return v_id;
end; $$;

-- Opening entry does not bypass verification, blocks, kicks or private-room consent.
update public.school_space_server set join_policy='verified',updated_at=now() where id;
insert into public.school_audit_events(actor,action,details) values(auth.uid(),'space.admission.open',jsonb_build_object('joinPolicy','verified'));
notify pgrst,'reload schema';
commit;
