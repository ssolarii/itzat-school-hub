-- Schedule Assistant community. No browser role/cookie is an authorization source.
-- Apply as a single transaction after the school backend migrations.
begin;

create table public.community_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 real_name text not null check(length(trim(real_name)) between 1 and 120),
 display_name text not null default '' check(length(display_name)<=60),
 audience text not null check(audience in ('student','teacher','parent')),
 class_group text,
 bio text not null default '' check(length(bio)<=500),
 accent text not null default '#6546b5' check(accent ~ '^#[0-9a-fA-F]{6}$'),
 accent_end text check(accent_end is null or accent_end ~ '^#[0-9a-fA-F]{6}$'),
 avatar_path text, banner_path text,
 blocked_until timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(audience <> 'student' or class_group is not null)
);
create table public.community_rooms (
 id uuid primary key default gen_random_uuid(), kind text not null check(kind in ('class','dm','group')),
 title text not null check(length(trim(title)) between 1 and 100), class_group text,
 created_by uuid references auth.users(id) on delete set null,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(), reviewed_by uuid references auth.users(id) on delete set null,
 reviewed_at timestamptz, check((kind='class')=(class_group is not null))
);
create unique index community_class_room on public.community_rooms(class_group) where kind='class';
insert into public.community_rooms(kind,title,class_group,status)
 select 'class',g.key||' class chat',g.key,'approved' from
 (select document from public.school_versions order by revision desc limit 1) s,
 lateral jsonb_each(s.document->'groups') g
 where not coalesce(s.document->'archivedGroups','[]') ? g.key;
create table public.community_room_members (
 room_id uuid references public.community_rooms(id) on delete cascade,
 user_id uuid references auth.users(id) on delete cascade,
 primary key(room_id,user_id)
);
create table public.community_messages (
 id bigint generated always as identity primary key,
 room_id uuid not null references public.community_rooms(id) on delete cascade,
 author_id uuid references auth.users(id) on delete set null,
 body text not null default '' check(length(body)<=4000),
 media_path text, gif_url text check(gif_url is null or gif_url ~ '^https://(media\.tenor\.com|media\.giphy\.com|i\.giphy\.com)/[^?#[:space:]]+\.gif$'), emoji_id uuid,
 created_at timestamptz not null default now(), removed_at timestamptz,
 check(length(trim(body))>0 or media_path is not null or gif_url is not null or emoji_id is not null)
);
create index community_messages_room_time on public.community_messages(room_id,id desc);
create table public.community_posts (
 id uuid primary key default gen_random_uuid(), author_id uuid references auth.users(id) on delete set null,
 scope text not null check(scope in ('class','site')), class_group text,
 kind text not null default 'poll' check(kind in ('poll','announcement')),
 title text not null check(length(trim(title)) between 1 and 160),
 body text not null default '' check(length(body)<=4000),
 target text not null default 'student' check(target in ('student','teacher','parent','all')),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 decision text not null default 'unreviewed' check(decision in ('unreviewed','planned','yes','no','implemented')),
 decision_note text not null default '' check(length(decision_note)<=1000),
 created_at timestamptz not null default now(), reviewed_by uuid references auth.users(id) on delete set null,
 reviewed_at timestamptz,
 check((scope='class')=(class_group is not null)), check(kind<>'announcement' or scope='site')
);
create table public.community_votes (
 post_id uuid references public.community_posts(id) on delete cascade,
 user_id uuid references auth.users(id) on delete cascade,
 vote boolean not null, updated_at timestamptz not null default now(), primary key(post_id,user_id)
);
create table public.community_likes (
 post_id uuid references public.community_posts(id) on delete cascade,
 user_id uuid references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(), primary key(post_id,user_id)
);
create table public.community_emojis (
 id uuid primary key default gen_random_uuid(), submitted_by uuid references auth.users(id) on delete set null,
 name text not null check(name ~ '^[a-z0-9_]{2,32}$'), media_path text not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(), reviewed_by uuid references auth.users(id) on delete set null,
 reviewed_at timestamptz
);
create unique index community_emoji_approved_name on public.community_emojis(name) where status='approved';
alter table public.community_messages add foreign key(emoji_id) references public.community_emojis(id) on delete set null;
create table public.community_reports (
 id uuid primary key default gen_random_uuid(), message_id bigint not null references public.community_messages(id) on delete cascade,
 reported_by uuid not null references auth.users(id) on delete cascade,
 reason text not null check(length(trim(reason)) between 1 and 1000),
 status text not null default 'open' check(status in ('open','resolved','dismissed')),
 created_at timestamptz not null default now(), reviewed_by uuid references auth.users(id) on delete set null,
 unique(message_id,reported_by)
);
create table school_private.community_limits (
 user_id uuid references auth.users(id) on delete cascade, action text not null,
 window_start timestamptz not null, hits integer not null, primary key(user_id,action)
);

create function school_private.community_developer() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.school_members m where m.user_id=auth.uid() and m.active and m.role='developer');
$$;
create function school_private.community_verified() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null);
$$;
create function school_private.community_assert_actor() returns uuid language plpgsql security definer set search_path='' as $$
begin
 if not school_private.community_verified() then raise exception 'Sign in with a verified email account first' using errcode='42501'; end if;
 if exists(select 1 from public.community_profiles p where p.user_id=auth.uid() and p.blocked_until>now()) then
  raise exception 'Community posting is temporarily paused for this account' using errcode='42501'; end if;
 return auth.uid();
end; $$;
create function school_private.community_limit(p_action text,p_max integer,p_seconds integer) returns void language plpgsql security definer set search_path='' as $$
declare v_hits integer;
begin
 insert into school_private.community_limits(user_id,action,window_start,hits) values(auth.uid(),p_action,now(),1)
 on conflict(user_id,action) do update set
 hits=case when school_private.community_limits.window_start<now()-make_interval(secs=>p_seconds) then 1 else school_private.community_limits.hits+1 end,
 window_start=case when school_private.community_limits.window_start<now()-make_interval(secs=>p_seconds) then now() else school_private.community_limits.window_start end
 returning hits into v_hits;
 if v_hits>p_max then raise exception 'Please wait before trying again' using errcode='P0001'; end if;
end; $$;
create function school_private.community_class_access(p_group text) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.community_verified() and exists(select 1 from public.school_versions s where s.revision=(select max(revision) from public.school_versions)
 and s.document->'groups' ? p_group and not coalesce(s.document->'archivedGroups','[]') ? p_group) and (
 exists(select 1 from public.community_profiles p where p.user_id=auth.uid() and p.audience='student' and p.class_group=p_group)
 or exists(select 1 from public.school_members m where m.user_id=auth.uid() and m.active and
  (m.role in ('developer','principal') or p_group=any(m.groups) or '*'=any(m.groups))));
$$;
create function school_private.community_room_access(p_room uuid) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.community_verified() and exists(select 1 from public.community_rooms r where r.id=p_room and r.status='approved' and
 ((r.kind='class' and school_private.community_class_access(r.class_group)) or
 (r.kind<>'class' and exists(select 1 from public.community_room_members m where m.room_id=r.id and m.user_id=auth.uid()))));
$$;
create function school_private.community_profile_access(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.community_verified() and (p_user=auth.uid() or school_private.is_leadership()
 or exists(select 1 from public.community_profiles p where p.user_id=p_user and p.audience='student' and school_private.community_class_access(p.class_group))
 or exists(select 1 from public.community_room_members m where m.user_id=p_user and school_private.community_room_access(m.room_id)));
$$;
create function school_private.community_post_access(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.community_posts p where p.id=p_id and
 ((p.scope='site' and p.status='approved') or (school_private.community_verified() and
 (p.author_id=auth.uid() or school_private.community_developer() or (p.scope='class' and p.status='approved' and school_private.community_class_access(p.class_group))))));
$$;
create function school_private.community_owns_media(p_path text) returns boolean language sql stable security definer set search_path='' as $$
 select p_path is null or (p_path ~ ('^'||auth.uid()::text||'/(avatar|banner|emoji|chat)/[a-zA-Z0-9_.-]+$') and
 exists(select 1 from storage.objects o where o.bucket_id='community-media' and o.name=p_path and o.owner_id=auth.uid()::text));
$$;

alter table public.community_profiles enable row level security;
alter table public.community_rooms enable row level security;
alter table public.community_room_members enable row level security;
alter table public.community_messages enable row level security;
alter table public.community_posts enable row level security;
alter table public.community_votes enable row level security;
alter table public.community_likes enable row level security;
alter table public.community_emojis enable row level security;
alter table public.community_reports enable row level security;
alter table school_private.community_limits enable row level security;
revoke all on public.community_profiles,public.community_rooms,public.community_room_members,public.community_messages,
 public.community_posts,public.community_votes,public.community_likes,public.community_emojis,public.community_reports from public,anon,authenticated;
-- Tables have RLS as a second barrier; bounded RPCs are the only application entry points.
create policy community_profiles_read on public.community_profiles for select to authenticated using(school_private.community_profile_access(user_id));
create policy community_rooms_read on public.community_rooms for select to authenticated using(school_private.community_room_access(id) or created_by=auth.uid() or school_private.is_leadership());
create policy community_members_read on public.community_room_members for select to authenticated using(school_private.community_room_access(room_id));
create policy community_messages_read on public.community_messages for select to authenticated using(school_private.community_room_access(room_id));
create policy community_posts_read on public.community_posts for select to anon,authenticated using(school_private.community_post_access(id));
create policy community_votes_read on public.community_votes for select to authenticated using(user_id=auth.uid());
create policy community_likes_read on public.community_likes for select to authenticated using(user_id=auth.uid());
create policy community_emojis_read on public.community_emojis for select to authenticated using(school_private.community_verified() and (status='approved' or submitted_by=auth.uid() or school_private.community_developer()));
create policy community_reports_read on public.community_reports for select to authenticated using(reported_by=auth.uid() or school_private.community_developer());

create function public.community_save_profile(p_profile jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_audience text; v_group text; v_document jsonb; v_result jsonb;
begin
 v_actor:=school_private.community_assert_actor(); perform school_private.community_limit('profile',30,3600);
 perform school_private.assert_keys(p_profile,array['realName','displayName','audience','classGroup','bio','accent','accentEnd','avatarPath','bannerPath'],'Profile');
 v_audience:=p_profile->>'audience'; v_group:=nullif(p_profile->>'classGroup','');
 if v_audience='teacher' and not exists(select 1 from public.school_members m where m.user_id=v_actor and m.active) then
  raise exception 'Teacher access requires an approved staff account' using errcode='42501'; end if;
 if v_audience='student' then
  select s.document into v_document from public.school_versions s order by s.revision desc limit 1;
  if v_group is null or not coalesce(v_document->'groups' ? v_group,false) or coalesce(v_document->'archivedGroups','[]') ? v_group then
   raise exception 'Choose an active school class' using errcode='22023'; end if;
 else v_group:=null; end if;
 if not school_private.community_owns_media(p_profile->>'avatarPath') or not school_private.community_owns_media(p_profile->>'bannerPath') then
  raise exception 'Profile pictures must be your own uploaded files' using errcode='42501'; end if;
 insert into public.community_profiles(user_id,real_name,display_name,audience,class_group,bio,accent,accent_end,avatar_path,banner_path)
 values(v_actor,trim(p_profile->>'realName'),coalesce(p_profile->>'displayName',''),v_audience,v_group,coalesce(p_profile->>'bio',''),coalesce(p_profile->>'accent','#6546b5'),nullif(p_profile->>'accentEnd',''),p_profile->>'avatarPath',p_profile->>'bannerPath')
 on conflict(user_id) do update set real_name=excluded.real_name,display_name=excluded.display_name,audience=excluded.audience,
 class_group=excluded.class_group,bio=excluded.bio,accent=excluded.accent,accent_end=excluded.accent_end,avatar_path=excluded.avatar_path,banner_path=excluded.banner_path,updated_at=now()
 returning to_jsonb(community_profiles.*) into v_result;
 if v_group is not null then
  insert into public.community_rooms(kind,title,class_group,status) values('class',v_group||' class chat',v_group,'approved')
  on conflict(class_group) where kind='class' do nothing;
 end if;
 return v_result;
end; $$;
create function public.community_get_profile() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_verified() then raise exception 'Verified sign-in required' using errcode='42501'; end if;
 return (select to_jsonb(p.*) from public.community_profiles p where p.user_id=auth.uid());
end; $$;
create function public.community_profiles_directory() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_verified() then raise exception 'Verified sign-in required' using errcode='42501'; end if;
 -- Account holders may discover names for reviewed DMs; richer profile details stay scoped.
 return coalesce((select jsonb_agg(jsonb_build_object('user_id',p.user_id,'real_name',case when school_private.community_profile_access(p.user_id) then p.real_name else 'School member' end,'display_name',p.display_name,
 'class_group',case when school_private.community_profile_access(p.user_id) then p.class_group end,
 'avatar_path',case when school_private.community_profile_access(p.user_id) then p.avatar_path end,
 'banner_path',case when school_private.community_profile_access(p.user_id) then p.banner_path end,
 'bio',case when school_private.community_profile_access(p.user_id) then p.bio end,
 'accent',p.accent,'accent_end',p.accent_end))
 from public.community_profiles p where exists(select 1 from auth.users u where u.id=p.user_id and u.email_confirmed_at is not null)),'[]');
end; $$;

create function public.community_list_rooms(p_pending boolean default false) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_verified() then raise exception 'Verified sign-in required' using errcode='42501'; end if;
 if p_pending and not school_private.is_leadership() then raise exception 'Leadership review required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(r.*)||jsonb_build_object('participants',coalesce((select jsonb_agg(m.user_id) from public.community_room_members m where m.room_id=r.id),'[]')) order by r.created_at)
 from public.community_rooms r where case when p_pending then r.status='pending' else school_private.community_room_access(r.id) or r.created_by=auth.uid() or exists(select 1 from public.community_room_members m where m.room_id=r.id and m.user_id=auth.uid()) end),'[]');
end; $$;
create function public.community_request_room(p_kind text,p_title text,p_participants uuid[]) returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_id uuid; v_people uuid[];
begin
 v_actor:=school_private.community_assert_actor(); perform school_private.community_limit('room',5,3600);
 if p_kind is null or p_kind not in ('dm','group') or coalesce(length(trim(p_title)),0) not between 1 and 100 or p_participants is null then raise exception 'Choose a room type, title and participants' using errcode='22023'; end if;
 select array_agg(distinct u) into v_people from unnest(array_append(p_participants,v_actor)) u;
 if cardinality(v_people) not between 2 and 30 or (p_kind='dm' and cardinality(v_people)<>2) or
 exists(select 1 from unnest(v_people) u where u is null or not exists(select 1 from public.community_profiles p join auth.users a on a.id=p.user_id where p.user_id=u and a.email_confirmed_at is not null)) then
 raise exception 'Choose available community members; direct messages require two people' using errcode='22023'; end if;
 insert into public.community_rooms(kind,title,created_by) values(p_kind,trim(p_title),v_actor) returning id into v_id;
 insert into public.community_room_members(room_id,user_id) select v_id,u from unnest(v_people) u;
 return v_id;
end; $$;
create function public.community_review_room(p_id uuid,p_approve boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if not school_private.is_leadership() then raise exception 'Leadership review required' using errcode='42501'; end if;
 if p_approve is null then raise exception 'Choose approve or reject' using errcode='22023'; end if;
 update public.community_rooms set status=case when p_approve then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=now() where id=p_id and status='pending' and kind<>'class';
 if not found then raise exception 'Pending conversation not found' using errcode='22023'; end if;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'community.room.review',jsonb_build_object('roomId',p_id,'approved',p_approve));
end; $$;
create function public.community_messages(p_room uuid,p_before bigint default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_room_access(p_room) then raise exception 'This conversation is private or awaiting review' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(m.*) order by m.id) from (select id,room_id,author_id,
 case when removed_at is null then body else 'Message removed by moderation' end as body,
 case when removed_at is null then media_path end as media_path,case when removed_at is null then gif_url end as gif_url,case when removed_at is null then emoji_id end as emoji_id,created_at,removed_at
 from public.community_messages where room_id=p_room and (p_before is null or id<p_before) order by id desc limit 100) m),'[]');
end; $$;
create function public.community_send_message(p_room uuid,p_body text,p_media_path text default null,p_emoji uuid default null,p_gif_url text default null) returns bigint language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_id bigint;
begin
 v_actor:=school_private.community_assert_actor();
 if not school_private.community_room_access(p_room) then raise exception 'This conversation is private or awaiting review' using errcode='42501'; end if;
 perform school_private.community_limit('message',30,60);
 if not school_private.community_owns_media(p_media_path) then raise exception 'Use your own uploaded media' using errcode='42501'; end if;
 if p_emoji is not null and not exists(select 1 from public.community_emojis e where e.id=p_emoji and e.status='approved') then raise exception 'Emoji is not approved' using errcode='22023'; end if;
 insert into public.community_messages(room_id,author_id,body,media_path,emoji_id,gif_url) values(p_room,v_actor,trim(coalesce(p_body,'')),p_media_path,p_emoji,p_gif_url) returning id into v_id;
 return v_id;
end; $$;
create function public.community_report_message(p_message bigint,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor(); perform school_private.community_limit('report',10,3600);
 if not exists(select 1 from public.community_messages m where m.id=p_message and school_private.community_room_access(m.room_id)) then raise exception 'Message unavailable' using errcode='42501'; end if;
 insert into public.community_reports(message_id,reported_by,reason) values(p_message,auth.uid(),trim(p_reason)) on conflict(message_id,reported_by) do update set reason=excluded.reason;
end; $$;

create function public.community_list_posts(p_scope text default 'site',p_class_group text default null,p_pending boolean default false) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if p_pending and not school_private.community_developer() then raise exception 'Developer review required' using errcode='42501'; end if;
 if p_scope='class' and not school_private.community_class_access(p_class_group) then raise exception 'This class feed is private' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'scope',p.scope,'class_group',p.class_group,'kind',p.kind,'title',p.title,'body',p.body,'target',p.target,'status',p.status,'decision',p.decision,'decision_note',p.decision_note,'created_at',p.created_at,
 'author_id',case when school_private.community_profile_access(p.author_id) then p.author_id end,
 'author_name',case when p.kind='announcement' then 'Developer' when school_private.community_profile_access(p.author_id) then coalesce(nullif(pr.display_name,''),pr.real_name,'Community member') when school_private.community_verified() then coalesce(nullif(pr.display_name,''),'Community member') else 'Student suggestion' end,
 'yes_count',(select count(*) from public.community_votes v where v.post_id=p.id and v.vote),
 'no_count',(select count(*) from public.community_votes v where v.post_id=p.id and not v.vote),
 'like_count',(select count(*) from public.community_likes l where l.post_id=p.id),
 'my_vote',(select v.vote from public.community_votes v where v.post_id=p.id and v.user_id=auth.uid()),
 'my_like',exists(select 1 from public.community_likes l where l.post_id=p.id and l.user_id=auth.uid())) order by p.created_at desc)
 from public.community_posts p left join public.community_profiles pr on pr.user_id=p.author_id
 where p.scope=p_scope and (p_scope<>'class' or p.class_group=p_class_group) and
 case when p_pending then p.status='pending' else school_private.community_post_access(p.id) end),'[]');
end; $$;
create function public.community_create_post(p_scope text,p_title text,p_body text,p_target text default 'student') returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_group text; v_id uuid; v_developer boolean;
begin
 v_actor:=school_private.community_assert_actor(); perform school_private.community_limit('post',5,3600);
 v_developer:=school_private.community_developer();
 if p_scope='class' then
  select p.class_group into v_group from public.community_profiles p where p.user_id=v_actor and p.audience='student';
  if v_group is null or not school_private.community_class_access(v_group) then raise exception 'Choose your student class first' using errcode='42501'; end if;
 end if;
 insert into public.community_posts(author_id,scope,class_group,title,body,target,status)
 values(v_actor,p_scope,v_group,trim(p_title),coalesce(p_body,''),p_target,case when p_scope='class' or v_developer then 'approved' else 'pending' end) returning id into v_id;
 return v_id;
end; $$;
create function public.community_vote(p_post uuid,p_vote boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor(); perform school_private.community_limit('reaction',120,60);
 if not school_private.community_post_access(p_post) or not exists(select 1 from public.community_posts p where p.id=p_post and p.kind='poll' and p.status='approved') then raise exception 'This poll is unavailable' using errcode='42501'; end if;
 if p_vote is null then delete from public.community_votes where post_id=p_post and user_id=auth.uid(); else
 insert into public.community_votes(post_id,user_id,vote) values(p_post,auth.uid(),p_vote) on conflict(post_id,user_id) do update set vote=excluded.vote,updated_at=now(); end if;
end; $$;
create function public.community_like(p_post uuid,p_liked boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor(); perform school_private.community_limit('reaction',120,60);
 if p_liked is null or not school_private.community_post_access(p_post) or not exists(select 1 from public.community_posts p where p.id=p_post and p.status='approved') then raise exception 'This post is unavailable' using errcode='42501'; end if;
 if p_liked then insert into public.community_likes(post_id,user_id) values(p_post,auth.uid()) on conflict do nothing; else delete from public.community_likes where post_id=p_post and user_id=auth.uid(); end if;
end; $$;
create function public.community_review_post(p_id uuid,p_approve boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer review required' using errcode='42501'; end if;
 if p_approve is null then raise exception 'Choose approve or reject' using errcode='22023'; end if;
 update public.community_posts set status=case when p_approve then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=now() where id=p_id and scope='site' and status='pending';
 if not found then raise exception 'Pending suggestion not found' using errcode='22023'; end if;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'community.post.review',jsonb_build_object('postId',p_id,'approved',p_approve));
end; $$;
create function public.community_set_decision(p_id uuid,p_decision text,p_note text default '') returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer access required' using errcode='42501'; end if;
 update public.community_posts set decision=p_decision,decision_note=coalesce(p_note,'') where id=p_id and scope='site' and kind='poll' and status='approved';
 if not found then raise exception 'Approved site suggestion not found' using errcode='22023'; end if;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'community.post.decision',jsonb_build_object('postId',p_id,'decision',p_decision));
end; $$;
create function public.community_announce(p_title text,p_body text,p_target text default 'all') returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer access required' using errcode='42501'; end if;
 insert into public.community_posts(author_id,scope,kind,title,body,target,status) values(auth.uid(),'site','announcement',trim(p_title),coalesce(p_body,''),p_target,'approved') returning id into v_id;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'community.announcement',jsonb_build_object('postId',v_id));
 return v_id;
end; $$;

create function public.community_list_emojis(p_pending boolean default false) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_verified() then raise exception 'Verified sign-in required' using errcode='42501'; end if;
 if p_pending and not school_private.community_developer() then raise exception 'Developer review required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(e.*) order by e.name) from public.community_emojis e where case when p_pending then e.status='pending' else e.status='approved' or e.submitted_by=auth.uid() end),'[]');
end; $$;
create function public.community_submit_emoji(p_name text,p_media_path text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 perform school_private.community_assert_actor(); perform school_private.community_limit('emoji',10,3600);
 if p_media_path is null or not school_private.community_owns_media(p_media_path) then raise exception 'Upload your emoji first' using errcode='42501'; end if;
 insert into public.community_emojis(submitted_by,name,media_path) values(auth.uid(),lower(trim(p_name)),p_media_path) returning id into v_id;
 return v_id;
end; $$;
create function public.community_review_emoji(p_id uuid,p_approve boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer review required' using errcode='42501'; end if;
 if p_approve is null then raise exception 'Choose approve or reject' using errcode='22023'; end if;
 update public.community_emojis set status=case when p_approve then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=now() where id=p_id and status='pending';
 if not found then raise exception 'Pending emoji not found' using errcode='22023'; end if;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'community.emoji.review',jsonb_build_object('emojiId',p_id,'approved',p_approve));
end; $$;

-- A report grants the Developer access to that reported message only, not a DM archive.
create function public.community_reports() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.community_verified() or not school_private.community_developer() then raise exception 'Developer moderation required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(r.*)||jsonb_build_object('body',m.body,'media_path',m.media_path,'gif_url',m.gif_url,'emoji_id',m.emoji_id,'room_id',m.room_id,'author_id',m.author_id)) from public.community_reports r join public.community_messages m on m.id=r.message_id where r.status='open'),'[]');
end; $$;
create function public.community_moderate_report(p_id uuid,p_remove boolean) returns void language plpgsql security definer set search_path='' as $$
declare v_message bigint;
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() then raise exception 'Developer moderation required' using errcode='42501'; end if;
 if p_remove is null then raise exception 'Choose remove or dismiss' using errcode='22023'; end if;
 update public.community_reports set status=case when p_remove then 'resolved' else 'dismissed' end,reviewed_by=auth.uid() where id=p_id and status='open' returning message_id into v_message;
 if v_message is null then raise exception 'Open report not found' using errcode='22023'; end if;
 if p_remove then update public.community_messages set removed_at=now() where id=v_message; end if;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'community.report.review',jsonb_build_object('reportId',p_id,'removed',p_remove));
end; $$;
create function public.community_pause_user(p_user uuid,p_until timestamptz) returns void language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if not school_private.community_developer() or p_user=auth.uid() then raise exception 'Developer moderation of another account required' using errcode='42501'; end if;
 if p_until is not null and (p_until<=now() or p_until>now()+interval '30 days') then raise exception 'Choose a pause of up to 30 days, or clear it' using errcode='22023'; end if;
 update public.community_profiles set blocked_until=p_until where user_id=p_user;
 if not found then raise exception 'Community profile not found' using errcode='22023'; end if;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'community.user.pause',jsonb_build_object('userId',p_user,'until',p_until));
end; $$;

-- Private storage. No public URLs, SVG/HTML uploads, arbitrary tracking URLs or cacheable identities.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('community-media','community-media',false,5242880,array['image/jpeg','image/png','image/webp','image/gif'])
 on conflict(id) do nothing;
create function school_private.community_media_read(p_path text) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.community_verified() and (
 p_path like auth.uid()::text||'/%'
 or exists(select 1 from public.community_profiles p where (p.avatar_path=p_path or p.banner_path=p_path) and school_private.community_profile_access(p.user_id))
 or exists(select 1 from public.community_emojis e where e.media_path=p_path and (e.status='approved' or school_private.community_developer()))
 or exists(select 1 from public.community_messages m where m.media_path=p_path and m.removed_at is null and school_private.community_room_access(m.room_id))
 or (school_private.community_developer() and exists(select 1 from public.community_reports r join public.community_messages m on m.id=r.message_id where r.status='open' and m.media_path=p_path)));
$$;
create function school_private.community_upload_allowed(p_path text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform school_private.community_assert_actor();
 if p_path !~ ('^'||auth.uid()::text||'/(avatar|banner|emoji|chat)/[a-zA-Z0-9_.-]+$') then return false; end if;
 -- Storage insert checks serialize per account, bounding uploads as well as posted messages.
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,110004));
 perform school_private.community_limit('upload',10,3600);
 if (select count(*) from storage.objects o where o.bucket_id='community-media' and o.owner_id=auth.uid()::text)>=100 then
  raise exception 'Your community image limit has been reached; contact the Developer' using errcode='22023'; end if;
 return true;
end; $$;
create policy community_media_insert on storage.objects for insert to authenticated with check(bucket_id='community-media' and school_private.community_upload_allowed(name));
create policy community_media_select on storage.objects for select to authenticated using(bucket_id='community-media' and school_private.community_media_read(name));
-- No overwrite/delete permission: signed media already attached to messages cannot be silently replaced.

-- Pin privileges for every new function, including implicit PUBLIC EXECUTE defaults.
do $$ declare f record; begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where (n.nspname='public' and p.proname like 'community_%') or (n.nspname='school_private' and p.proname like 'community_%') loop
 execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 if f.signature::text like 'community_%' or f.signature::text like 'public.community_%' then
  execute format('grant execute on function %s to authenticated',f.signature);
 end if;
 end loop;
end; $$;
-- Internal helpers referenced by RLS need EXECUTE; they expose booleans only.
grant execute on function school_private.community_verified(),school_private.community_developer(),school_private.community_class_access(text),school_private.community_room_access(uuid),school_private.community_profile_access(uuid),school_private.community_post_access(uuid),school_private.community_media_read(text),school_private.community_upload_allowed(text) to authenticated;
grant execute on function school_private.community_post_access(uuid) to anon;
grant execute on function public.community_list_posts(text,text,boolean) to anon;
commit;
