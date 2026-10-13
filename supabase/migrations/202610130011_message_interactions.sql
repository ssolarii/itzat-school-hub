begin;
alter table public.community_messages
 add column edited_at timestamptz,
 add column deleted_by_author boolean not null default false,
 add column reply_to bigint references public.community_messages(id) on delete set null,
 add column mentioned_ids uuid[] not null default '{}',
 add column ping_everyone boolean not null default false;
create table public.community_message_reactions (
 message_id bigint not null references public.community_messages(id) on delete cascade,
 room_id uuid not null references public.community_rooms(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 emoji text not null check(length(emoji) between 1 and 32 and emoji !~ '[[:cntrl:]]'),
 active boolean not null default true,
 created_at timestamptz not null default now(),
 primary key(message_id,user_id,emoji)
);
alter table public.community_message_reactions enable row level security;
revoke all on public.community_message_reactions from public,anon,authenticated;
grant select on public.community_message_reactions to authenticated;
create policy community_reactions_read on public.community_message_reactions for select to authenticated using(school_private.community_room_access(room_id));

create function school_private.community_mention_allowed(p_room uuid,p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select not school_private.community_pair_blocked(auth.uid(),p_user) and exists(
 select 1 from public.community_rooms r join public.community_profiles p on p.user_id=p_user where r.id=p_room and
 ((r.kind='school' and p.space_onboarded and school_private.community_admitted(p_user) and not exists(select 1 from public.school_space_roles s where s.user_id=p_user and s.kicked))
 or (r.kind='class' and p.audience='student' and p.class_group=r.class_group and school_private.community_admitted(p_user))
 or (r.kind in ('dm','group') and exists(select 1 from public.community_room_members m where m.room_id=p_room and m.user_id=p_user and m.consent='accepted'))));
$$;
create function school_private.community_parse_mentions(p_room uuid,p_body text) returns uuid[] language plpgsql stable security definer set search_path='' as $$
declare v_ids uuid[];
begin
 select coalesce(array_agg(distinct (m[1])::uuid),'{}') into v_ids from regexp_matches(coalesce(p_body,''),'<@([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})>','g') m;
 if not school_private.community_developer() and (cardinality(v_ids)>1 or coalesce(p_body,'') ~* '(^|[^[:alnum:]_])@(everyone|here|all)([^[:alnum:]_]|$)') then raise exception 'You can mention one person per message; everyone mentions are Developer-only' using errcode='42501'; end if;
 if exists(select 1 from unnest(v_ids) u where not school_private.community_mention_allowed(p_room,u)) then raise exception 'Mention someone who belongs to this conversation' using errcode='42501'; end if;
 return v_ids;
end; $$;
create function public.community_mention_directory(p_room uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_room_access(p_room) then raise exception 'Conversation access required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('user_id',p.user_id,'display_name',p.display_name,'real_name',p.real_name) order by p.real_name) from public.community_profiles p where school_private.community_mention_allowed(p_room,p.user_id)),'[]');
end; $$;

-- Keep existing consent checks, upload validation, slow mode and rate limits.
alter function public.community_send_message(uuid,text,text,uuid,text) set schema school_private;
alter function school_private.community_send_message(uuid,text,text,uuid,text) rename to community_send_message_v9;
revoke all on function school_private.community_send_message_v9(uuid,text,text,uuid,text) from public,anon,authenticated;
create function public.community_send_message(p_room uuid,p_body text,p_media_path text default null,p_emoji uuid default null,p_gif_url text default null,p_reply_to bigint default null) returns bigint language plpgsql security definer set search_path='' as $$
declare v_id bigint; v_mentions uuid[];
begin
 perform school_private.community_assert_actor();
 if not school_private.community_room_access(p_room) then raise exception 'Conversation access required' using errcode='42501'; end if;
 v_mentions:=school_private.community_parse_mentions(p_room,p_body);
 if p_reply_to is not null then
  perform 1 from public.community_messages where id=p_reply_to and room_id=p_room and removed_at is null for share;
  if not found then raise exception 'The message you are replying to is unavailable' using errcode='22023'; end if;
 end if;
 v_id:=school_private.community_send_message_v9(p_room,p_body,p_media_path,p_emoji,p_gif_url);
 update public.community_messages set reply_to=p_reply_to,mentioned_ids=v_mentions,ping_everyone=coalesce(p_body,'') ~* '(^|[^[:alnum:]_])@(everyone|here|all)([^[:alnum:]_]|$)' where id=v_id;
 return v_id;
end; $$;
create function public.community_edit_message(p_id bigint,p_body text) returns void language plpgsql security definer set search_path='' as $$
declare v_message public.community_messages; v_mentions uuid[];
begin
 perform school_private.community_assert_actor();
 select * into v_message from public.community_messages where id=p_id and author_id=auth.uid() and removed_at is null for update;
 if not found or not school_private.community_room_access(v_message.room_id) or not school_private.channel_can_speak(v_message.room_id) then raise exception 'You can only edit your own available messages in a channel where you can post' using errcode='42501'; end if;
 if p_body is null or length(p_body)>4000 or (length(trim(p_body))=0 and v_message.media_path is null and v_message.gif_url is null and v_message.emoji_id is null) then raise exception 'Write a message of up to 4000 characters' using errcode='22023'; end if;
 perform school_private.community_limit('message_edit',30,60);
 v_mentions:=school_private.community_parse_mentions(v_message.room_id,p_body);
 update public.community_messages set body=trim(p_body),edited_at=now(),mentioned_ids=v_mentions,ping_everyone=p_body ~* '(^|[^[:alnum:]_])@(everyone|here|all)([^[:alnum:]_]|$)' where id=p_id;
end; $$;
create function public.community_delete_message(p_id bigint) returns void language plpgsql security definer set search_path='' as $$
declare v_room uuid;
begin
 if auth.uid() is null then raise exception 'Sign in first' using errcode='42501'; end if;
 select room_id into v_room from public.community_messages where id=p_id and author_id=auth.uid() and removed_at is null for update;
 if not found or not school_private.community_room_access(v_room) then raise exception 'You can only delete your own available messages' using errcode='42501'; end if;
 update public.community_messages set body='Message deleted',media_path=null,gif_url=null,emoji_id=null,removed_at=now(),deleted_by_author=true,mentioned_ids='{}',ping_everyone=false where id=p_id;
 delete from public.community_message_reactions where message_id=p_id;
end; $$;
create function public.community_react_message(p_id bigint,p_emoji text,p_active boolean) returns void language plpgsql security definer set search_path='' as $$
declare v_room uuid;
begin
 perform school_private.community_assert_actor();
 select room_id into v_room from public.community_messages where id=p_id and removed_at is null for share;
 if not found or not school_private.community_room_access(v_room) then raise exception 'Message access required' using errcode='42501'; end if;
 if p_active is null or p_emoji is null or length(p_emoji) not between 1 and 32 or p_emoji ~ '[[:cntrl:]]' or not exists(select 1 from unnest(string_to_array(p_emoji,null)) c where ascii(c)>127) then raise exception 'Choose an emoji' using errcode='22023'; end if;
 perform school_private.community_limit('reaction',60,60);
 perform pg_advisory_xact_lock(hashtextextended('reaction:'||p_id::text||':'||auth.uid()::text,0));
 if p_active then
  if (select count(*) from public.community_message_reactions where message_id=p_id and user_id=auth.uid() and active)>=20 and not exists(select 1 from public.community_message_reactions where message_id=p_id and user_id=auth.uid() and emoji=p_emoji and active) then raise exception 'Use up to 20 reactions per message' using errcode='22023'; end if;
  insert into public.community_message_reactions(message_id,room_id,user_id,emoji) values(p_id,v_room,auth.uid(),p_emoji) on conflict(message_id,user_id,emoji) do update set active=true;
 else update public.community_message_reactions set active=false where message_id=p_id and user_id=auth.uid() and emoji=p_emoji; end if;
end; $$;

create or replace function public.community_messages(p_room uuid,p_before bigint default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_room_access(p_room) then raise exception 'Conversation access required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(m) order by m.id) from (
 select m.id,m.room_id,m.author_id,m.created_at,m.removed_at,m.deleted_by_author,m.edited_at,m.reply_to,
 case when m.removed_at is null then m.body else case when m.deleted_by_author then 'Message deleted' else 'Message removed by moderation' end end as body,
 case when m.removed_at is null then m.media_path end as media_path,
 case when m.removed_at is null then m.gif_url end as gif_url,
 case when m.removed_at is null then m.emoji_id end as emoji_id,
 case when m.removed_at is null then m.mentioned_ids else '{}'::uuid[] end as mentioned_ids,
 m.removed_at is null and m.ping_everyone as ping_everyone,
 case when q.id is not null then jsonb_build_object('id',q.id,'author_id',q.author_id,'body',case when q.removed_at is null then left(q.body,240) else 'Message unavailable' end) end as reply,
 case when m.removed_at is null then coalesce((select jsonb_agg(jsonb_build_object('emoji',r.emoji,'count',r.total,'mine',r.mine)) from (select emoji,count(*) as total,bool_or(user_id=auth.uid()) as mine from public.community_message_reactions where message_id=m.id and active group by emoji order by emoji) r),'[]') else '[]'::jsonb end as reactions
 from public.community_messages m left join public.community_messages q on q.id=m.reply_to and q.room_id=m.room_id
 where m.room_id=p_room and (p_before is null or m.id<p_before) order by m.id desc limit 100) m),'[]');
end; $$;
revoke all on function school_private.community_mention_allowed(uuid,uuid),school_private.community_parse_mentions(uuid,text) from public,anon,authenticated;
revoke all on function public.community_mention_directory(uuid),public.community_send_message(uuid,text,text,uuid,text,bigint),public.community_edit_message(bigint,text),public.community_delete_message(bigint),public.community_react_message(bigint,text,boolean) from public,anon;
grant execute on function public.community_mention_directory(uuid),public.community_send_message(uuid,text,text,uuid,text,bigint),public.community_edit_message(bigint,text),public.community_delete_message(bigint),public.community_react_message(bigint,text,boolean) to authenticated;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then alter publication supabase_realtime add table public.community_message_reactions; end if;
end; $$;
create or replace function public.community_activity(p_after bigint default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_max bigint; v_cursor bigint; v_events jsonb;
begin
 v_actor:=school_private.community_assert_actor(); perform school_private.community_limit('activity',30,60);
 if p_after is not null and p_after<0 then raise exception 'Invalid activity cursor' using errcode='22023'; end if;
 select coalesce(max(m.id),0) into v_max from public.community_messages m where m.removed_at is null
 and school_private.community_room_access(m.room_id) and m.author_id is distinct from v_actor
 and not school_private.community_pair_blocked(v_actor,m.author_id);
 if p_after is null then return jsonb_build_object('cursor',v_max,'maxeligibleid',v_max,'events','[]'::jsonb); end if;
 select coalesce(jsonb_agg(to_jsonb(e.*) order by e.id),'[]'),coalesce(max(e.id),p_after) into v_events,v_cursor
 from (select m.id,m.room_id,m.author_id,m.created_at,(v_actor=any(m.mentioned_ids) or m.ping_everyone) as mentioned from public.community_messages m
 where m.id>p_after and m.removed_at is null and m.author_id is distinct from v_actor
 and school_private.community_room_access(m.room_id) and not school_private.community_pair_blocked(v_actor,m.author_id)
 order by m.id limit 100) e;
 return jsonb_build_object('cursor',v_cursor,'maxeligibleid',v_max,'events',v_events);
end; $$;

notify pgrst,'reload schema';
commit;
