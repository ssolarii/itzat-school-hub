begin;

-- Reversible maintenance switch. No messages, memberships or files are deleted.
create table school_private.chat_runtime (
 id boolean primary key default true check(id),
 paused boolean not null default true
);
alter table school_private.chat_runtime enable row level security;
revoke all on school_private.chat_runtime from public,anon,authenticated;
insert into school_private.chat_runtime(id,paused) values(true,true);

create function public.school_chat_paused() returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce((select paused from school_private.chat_runtime where id),true);
$$;
revoke all on function public.school_chat_paused() from public;
grant execute on function public.school_chat_paused() to anon,authenticated;

-- Shared by class chats, DMs, school channels and their Realtime read policies.
create or replace function school_private.chat_audience_allowed() returns boolean
language sql stable security definer set search_path='' as $$
 select not public.school_chat_paused() and auth.uid() is not null and
 (school_private.community_developer() or
 (not exists(select 1 from public.school_members where user_id=auth.uid() and active and role in ('teacher','principal'))
 and not exists(select 1 from public.community_profiles where user_id=auth.uid() and audience='parent')));
$$;

-- Stop new chat-media uploads and signed URLs, including from older clients.
-- Other buckets, including private teacher timetable uploads, are unaffected.
create policy community_media_maintenance on storage.objects as restrictive
for all to authenticated
using(bucket_id<>'community-media' or not public.school_chat_paused())
with check(bucket_id<>'community-media' or not public.school_chat_paused());

notify pgrst,'reload schema';
commit;
