-- Recipient-approved friendships; private DMs still require the staff review in 004.
begin;
create table public.community_friendships (
 id uuid primary key default gen_random_uuid(),
 requested_by uuid not null references auth.users(id) on delete cascade,
 recipient_id uuid not null references auth.users(id) on delete cascade,
 user_low uuid generated always as (least(requested_by,recipient_id)) stored,
 user_high uuid generated always as (greatest(requested_by,recipient_id)) stored,
 status text not null default 'pending' check(status in ('pending','accepted','declined','removed')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 responded_at timestamptz,
 check(requested_by<>recipient_id), unique(user_low,user_high)
);
create table public.community_blocks (
 user_id uuid not null references auth.users(id) on delete cascade,
 blocked_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(user_id,blocked_id), check(user_id<>blocked_id)
);
alter table public.community_friendships enable row level security;
alter table public.community_blocks enable row level security;
revoke all on public.community_friendships,public.community_blocks from public,anon,authenticated;
create policy community_friendships_own_read on public.community_friendships for select to authenticated
 using(school_private.community_verified() and auth.uid() in (requested_by,recipient_id));
create policy community_blocks_own_read on public.community_blocks for select to authenticated
 using(school_private.community_verified() and user_id=auth.uid());

create function school_private.community_pair_blocked(p_a uuid,p_b uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.community_blocks b where (b.user_id=p_a and b.blocked_id=p_b) or (b.user_id=p_b and b.blocked_id=p_a));
$$;
create function school_private.community_friend_access(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.community_verified() and not school_private.community_pair_blocked(auth.uid(),p_user) and exists(
 select 1 from public.community_friendships f where f.status='accepted' and
 ((f.requested_by=auth.uid() and f.recipient_id=p_user) or (f.recipient_id=auth.uid() and f.requested_by=p_user)));
$$;
create function school_private.community_lock_pair(p_a uuid,p_b uuid) returns void language plpgsql set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended(least(p_a,p_b)::text||':'||greatest(p_a,p_b)::text,120005));
end; $$;
create or replace function school_private.community_profile_access(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.community_verified() and (p_user=auth.uid() or school_private.is_leadership()
 or exists(select 1 from public.community_profiles p where p.user_id=p_user and p.audience='student' and school_private.community_class_access(p.class_group))
 or (not school_private.community_pair_blocked(auth.uid(),p_user) and (school_private.community_friend_access(p_user)
 or exists(select 1 from public.community_room_members m where m.user_id=p_user and school_private.community_room_access(m.room_id)))));
$$;

create function public.community_list_friends() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_verified() then raise exception 'Verified sign-in required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(f.*)||jsonb_build_object(
 'other_id',p.user_id,'display_name',p.display_name,
 'real_name',case when school_private.community_profile_access(p.user_id) then p.real_name else 'School member' end,
 'avatar_path',case when school_private.community_profile_access(p.user_id) then p.avatar_path end,
 'banner_path',case when school_private.community_profile_access(p.user_id) then p.banner_path end,
 'class_group',case when school_private.community_profile_access(p.user_id) then p.class_group end,
 'bio',case when school_private.community_profile_access(p.user_id) then p.bio end,
 'accent',p.accent,'accent_end',p.accent_end) order by f.updated_at desc)
 from public.community_friendships f join public.community_profiles p on p.user_id=case when f.requested_by=auth.uid() then f.recipient_id else f.requested_by end
 where auth.uid() in (f.requested_by,f.recipient_id) and f.status in ('pending','accepted')
 and not school_private.community_pair_blocked(f.requested_by,f.recipient_id)),'[]');
end; $$;
create function public.community_request_friend(p_user uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_existing public.community_friendships; v_id uuid;
begin
 v_actor:=school_private.community_assert_actor();
 if p_user is null or p_user=v_actor or not exists(select 1 from public.community_profiles p join auth.users u on u.id=p.user_id where p.user_id=p_user and u.email_confirmed_at is not null)
 or not exists(select 1 from public.community_profiles p where p.user_id=v_actor) then
 raise exception 'Choose an available community member and complete your profile first' using errcode='22023'; end if;
 perform school_private.community_lock_pair(v_actor,p_user);
 if school_private.community_pair_blocked(v_actor,p_user) then raise exception 'This friend request is unavailable' using errcode='42501'; end if;
 select * into v_existing from public.community_friendships where user_low=least(v_actor,p_user) and user_high=greatest(v_actor,p_user) for update;
 if v_existing.status in ('pending','accepted') then
  raise exception 'A friend request or friendship already exists' using errcode='22023'; end if;
 if v_existing.status='declined' and v_existing.updated_at>now()-interval '24 hours' then
  raise exception 'Wait at least 24 hours before requesting again' using errcode='22023'; end if;
 perform school_private.community_limit('friend',10,3600);
 insert into public.community_friendships(requested_by,recipient_id) values(v_actor,p_user)
 on conflict(user_low,user_high) do update set requested_by=excluded.requested_by,recipient_id=excluded.recipient_id,
 status='pending',created_at=now(),updated_at=now(),responded_at=null returning id into v_id;
 return v_id;
end; $$;
create function public.community_respond_friend(p_id uuid,p_accept boolean) returns void language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_row public.community_friendships;
begin
 v_actor:=school_private.community_assert_actor();
 if p_accept is null then raise exception 'Choose accept or decline' using errcode='22023'; end if;
 select * into v_row from public.community_friendships where id=p_id;
 if v_row.id is null or v_row.recipient_id<>v_actor then raise exception 'Only the recipient can respond to this request' using errcode='42501'; end if;
 perform school_private.community_lock_pair(v_row.requested_by,v_row.recipient_id);
 select * into v_row from public.community_friendships where id=p_id for update;
 if v_row.status<>'pending' or v_row.recipient_id<>v_actor or school_private.community_pair_blocked(v_row.requested_by,v_row.recipient_id) then
  raise exception 'This friend request is no longer available' using errcode='22023'; end if;
 update public.community_friendships set status=case when p_accept then 'accepted' else 'declined' end,responded_at=now(),updated_at=now() where id=p_id;
end; $$;
create function public.community_remove_friend(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_row public.community_friendships;
begin
 v_actor:=school_private.community_assert_actor();
 select * into v_row from public.community_friendships where id=p_id;
 if v_row.id is null or v_actor not in (v_row.requested_by,v_row.recipient_id) then raise exception 'Friendship unavailable' using errcode='42501'; end if;
 perform school_private.community_lock_pair(v_row.requested_by,v_row.recipient_id);
 select * into v_row from public.community_friendships where id=p_id for update;
 if v_actor not in (v_row.requested_by,v_row.recipient_id) then raise exception 'Friendship unavailable' using errcode='42501'; end if;
 if v_row.status not in ('pending','accepted') then raise exception 'Only a pending request or accepted friendship can be removed' using errcode='22023'; end if;
 update public.community_friendships set status='removed',updated_at=now() where id=p_id;
end; $$;
create function public.community_block_user(p_user uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_actor uuid;
begin
 v_actor:=school_private.community_assert_actor();
 if p_user is null or p_user=v_actor or not exists(select 1 from public.community_profiles p where p.user_id=p_user) then raise exception 'Choose another community member' using errcode='22023'; end if;
 perform school_private.community_lock_pair(v_actor,p_user);
 insert into public.community_blocks(user_id,blocked_id) values(v_actor,p_user) on conflict do nothing;
 -- Preserve declined rows and their timestamp so block/unblock cannot erase the recipient's cooldown.
 update public.community_friendships set status='removed',updated_at=now() where user_low=least(v_actor,p_user) and user_high=greatest(v_actor,p_user) and status in ('pending','accepted');
end; $$;
create function public.community_unblock_user(p_user uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 perform school_private.community_lock_pair(auth.uid(),p_user);
 delete from public.community_blocks where user_id=auth.uid() and blocked_id=p_user;
 -- Unblocking does not restore a friendship or pending invitation.
end; $$;
create function public.community_list_blocks() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_verified() then raise exception 'Verified sign-in required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('user_id',b.blocked_id,'display_name',coalesce(nullif(p.display_name,''),'School member'),'created_at',b.created_at) order by b.created_at desc)
 from public.community_blocks b left join public.community_profiles p on p.user_id=b.blocked_id where b.user_id=auth.uid()),'[]');
end; $$;

create or replace function public.community_request_room(p_kind text,p_title text,p_participants uuid[]) returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_id uuid; v_people uuid[]; v_pair record;
begin
 v_actor:=school_private.community_assert_actor(); perform school_private.community_limit('room',5,3600);
 if p_kind is null or p_kind not in ('dm','group') or coalesce(length(trim(p_title)),0) not between 1 and 100 or p_participants is null then raise exception 'Choose a room type, title and participants' using errcode='22023'; end if;
 select array_agg(distinct u order by u) into v_people from unnest(array_append(p_participants,v_actor)) u;
 if cardinality(v_people) not between 2 and 30 or (p_kind='dm' and cardinality(v_people)<>2) or
 exists(select 1 from unnest(v_people) u where u is null or not exists(select 1 from public.community_profiles p join auth.users a on a.id=p.user_id where p.user_id=u and a.email_confirmed_at is not null)) then
 raise exception 'Choose available community members; direct messages require two people' using errcode='22023'; end if;
 -- Acquire pair locks in a stable order, matching friend/block mutations.
 for v_pair in select a,b from unnest(v_people) a cross join unnest(v_people) b where a<b order by a,b loop
  perform school_private.community_lock_pair(v_pair.a,v_pair.b);
  if school_private.community_pair_blocked(v_pair.a,v_pair.b) then raise exception 'A selected conversation participant is unavailable' using errcode='42501'; end if;
 end loop;
 insert into public.community_rooms(kind,title,created_by) values(p_kind,trim(p_title),v_actor) returning id into v_id;
 insert into public.community_room_members(room_id,user_id) select v_id,u from unnest(v_people) u;
 return v_id;
end; $$;
create or replace function public.community_review_room(p_id uuid,p_approve boolean) returns void language plpgsql security definer set search_path='' as $$
declare v_pair record;
begin
 perform school_private.community_assert_actor();
 if not school_private.is_leadership() then raise exception 'Leadership review required' using errcode='42501'; end if;
 if p_approve is null then raise exception 'Choose approve or reject' using errcode='22023'; end if;
 perform 1 from public.community_rooms where id=p_id and status='pending' and kind<>'class' for update;
 if not found then raise exception 'Pending conversation not found' using errcode='22023'; end if;
 if p_approve then
  for v_pair in select a.user_id a,b.user_id b from public.community_room_members a join public.community_room_members b on a.room_id=b.room_id and a.user_id<b.user_id where a.room_id=p_id order by a.user_id,b.user_id loop
   perform school_private.community_lock_pair(v_pair.a,v_pair.b);
   if school_private.community_pair_blocked(v_pair.a,v_pair.b) then raise exception 'A conversation participant is unavailable; reject this request' using errcode='42501'; end if;
  end loop;
 end if;
 update public.community_rooms set status=case when p_approve then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=now() where id=p_id;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'community.room.review',jsonb_build_object('roomId',p_id,'approved',p_approve));
end; $$;
create or replace function public.community_send_message(p_room uuid,p_body text,p_media_path text default null,p_emoji uuid default null,p_gif_url text default null) returns bigint language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_id bigint; v_other uuid;
begin
 v_actor:=school_private.community_assert_actor();
 if not school_private.community_room_access(p_room) then raise exception 'This conversation is private or awaiting review' using errcode='42501'; end if;
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

create function public.community_activity(p_after bigint default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_max bigint; v_cursor bigint; v_events jsonb;
begin
 v_actor:=school_private.community_assert_actor(); perform school_private.community_limit('activity',30,60);
 if p_after is not null and p_after<0 then raise exception 'Invalid activity cursor' using errcode='22023'; end if;
 select coalesce(max(m.id),0) into v_max from public.community_messages m where m.removed_at is null
 and school_private.community_room_access(m.room_id) and m.author_id is distinct from v_actor
 and not school_private.community_pair_blocked(v_actor,m.author_id);
 if p_after is null then return jsonb_build_object('cursor',v_max,'maxeligibleid',v_max,'events','[]'::jsonb); end if;
 select coalesce(jsonb_agg(to_jsonb(e.*) order by e.id),'[]'),coalesce(max(e.id),p_after) into v_events,v_cursor
 from (select m.id,m.room_id,m.author_id,m.created_at from public.community_messages m
 where m.id>p_after and m.removed_at is null and m.author_id is distinct from v_actor
 and school_private.community_room_access(m.room_id) and not school_private.community_pair_blocked(v_actor,m.author_id)
 order by m.id limit 100) e;
 return jsonb_build_object('cursor',v_cursor,'maxeligibleid',v_max,'events',v_events);
end; $$;

revoke all on function school_private.community_pair_blocked(uuid,uuid),school_private.community_friend_access(uuid),school_private.community_lock_pair(uuid,uuid) from public,anon,authenticated;
-- Only the boolean access helper is directly used by RLS. Other helpers stay internal.
grant execute on function school_private.community_friend_access(uuid) to authenticated;
revoke all on function public.community_list_friends(),public.community_request_friend(uuid),public.community_respond_friend(uuid,boolean),public.community_remove_friend(uuid),public.community_block_user(uuid),public.community_unblock_user(uuid),public.community_list_blocks(),public.community_activity(bigint) from public,anon,authenticated;
grant execute on function public.community_list_friends(),public.community_request_friend(uuid),public.community_respond_friend(uuid,boolean),public.community_remove_friend(uuid),public.community_block_user(uuid),public.community_unblock_user(uuid),public.community_list_blocks(),public.community_activity(bigint) to authenticated;
-- CREATE OR REPLACE preserves the restricted EXECUTE privileges from 004.
commit;
