begin;
alter table public.community_message_reactions drop constraint community_message_reactions_emoji_check;
alter table public.community_message_reactions add constraint community_message_reactions_emoji_check check(length(emoji) between 1 and 34 and emoji !~ '[[:cntrl:]]');

-- Preserve room authorization and rate limits; accept only approved custom codes.
create or replace function public.community_react_message(p_id bigint,p_emoji text,p_active boolean) returns void language plpgsql security definer set search_path='' as $$
declare v_room uuid; v_custom boolean;
begin
 perform school_private.community_assert_actor();
 select room_id into v_room from public.community_messages where id=p_id and removed_at is null for share;
 if not found or not school_private.community_room_access(v_room) then raise exception 'Message access required' using errcode='42501'; end if;
 if p_active is null or p_emoji is null or length(p_emoji) not between 1 and 34 or p_emoji ~ '[[:cntrl:]]' then raise exception 'Choose an emoji' using errcode='22023'; end if;
 v_custom:=p_emoji ~ '^:[a-z0-9_]{1,32}:$';
 if v_custom then
  if not exists(select 1 from public.community_emojis where name=substring(p_emoji from 2 for length(p_emoji)-2) and status='approved')
   and not (not p_active and exists(select 1 from public.community_message_reactions where message_id=p_id and user_id=auth.uid() and emoji=p_emoji)) then raise exception 'Choose an approved custom emoji' using errcode='22023'; end if;
 elsif length(p_emoji)>32 or not exists(select 1 from unnest(string_to_array(p_emoji,null)) c where ascii(c)>127) then raise exception 'Choose an emoji' using errcode='22023'; end if;
 perform school_private.community_limit('reaction',60,60);
 perform pg_advisory_xact_lock(hashtextextended('reaction:'||p_id::text||':'||auth.uid()::text,0));
 if p_active then
  if (select count(*) from public.community_message_reactions where message_id=p_id and user_id=auth.uid() and active)>=20 and not exists(select 1 from public.community_message_reactions where message_id=p_id and user_id=auth.uid() and emoji=p_emoji and active) then raise exception 'Use up to 20 reactions per message' using errcode='22023'; end if;
  insert into public.community_message_reactions(message_id,room_id,user_id,emoji) values(p_id,v_room,auth.uid(),p_emoji) on conflict(message_id,user_id,emoji) do update set active=true;
 else update public.community_message_reactions set active=false where message_id=p_id and user_id=auth.uid() and emoji=p_emoji; end if;
end; $$;

-- Cosmetic award requested by the existing, verified Developer. No role grants.
do $$ declare v_user uuid:='2ca0f019-99f3-48b9-8d2e-80212bdc4415'; v_badge uuid:='0f019000-0000-4000-8000-000000000001'; begin
 if exists(select 1 from auth.users u join public.school_members m on m.user_id=u.id where u.id=v_user and lower(u.email)='alejandrojahielm@gmail.com' and u.email_confirmed_at is not null and m.active and m.role='developer') then
  insert into public.school_space_badge_catalog(id,name,description,icon_key,color,created_by) values(v_badge,'Original Founder','Created the place where it all started. Includes the Founder crown and avatar frame.','crown','#b07816',v_user)
  on conflict(id) do update set active=true;
  insert into public.school_space_badge_awards(user_id,badge_id,awarded_by,note) values(v_user,v_badge,v_user,'Special Founder badge and profile decoration requested by the founder.') on conflict(user_id,badge_id) do nothing;
  update public.community_profiles set featured_badge_id=v_badge where user_id=v_user;
  insert into public.school_audit_events(actor,action,details) values(v_user,'space.badge.award',jsonb_build_object('userId',v_user,'badgeId',v_badge,'cosmeticOnly',true));
 end if;
end $$;
notify pgrst,'reload schema';
commit;
