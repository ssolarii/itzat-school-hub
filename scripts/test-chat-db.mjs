import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs/promises';
const db = new PGlite();
await db.exec(`
 create role anon nologin; create role authenticated nologin;
 create schema auth; create schema storage;
 create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema auth to anon,authenticated;
 grant execute on function auth.uid() to anon,authenticated;
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets(id),name text,owner_id text,metadata jsonb);
 alter table storage.objects enable row level security;
 grant usage on schema storage to authenticated;
 grant select,insert,update,delete on storage.objects to authenticated;
 create publication supabase_realtime;
`);
for (const path of [
 'supabase/migrations/202610100001_school_backend.sql',
 'supabase/migrations/202610100002_teacher_requests.sql',
 'supabase/migrations/202610100003_review_identity.sql',
 'supabase/seed.sql',
 'supabase/migrations/202610110004_community.sql',
 'supabase/migrations/202610120005_friends.sql',
 'supabase/migrations/202610120006_school_space.sql',
 'supabase/tests/community.sql',
 'supabase/tests/friends.sql',
 'supabase/tests/school-space.sql',
]) {
 console.log('Executing',path);
 try { await db.exec(await fs.readFile(path,'utf8')); }
 catch(error) { console.error(JSON.stringify({message:error.message,code:error.code,position:error.position,where:error.where,detail:error.detail},null,2)); for (const path of ['supabase/migrations/202610130010_staff_access_and_badges.sql','supabase/migrations/202610130011_message_interactions.sql','supabase/migrations/202610140019_emoji_reactions_founder.sql','supabase/tests/emoji-reactions.sql']) { console.log('Executing',path); try { await db.exec(await fs.readFile(path,'utf8')); } catch(e) { console.error(JSON.stringify({message:e.message,code:e.code,where:e.where})); process.exit(1); } console.log('PASS',path); }
await db.close(); process.exit(1); }
 console.log('PASS',path);
}
console.log('Community PostgreSQL migration and rollback security fixtures passed.');
await db.exec(`
 begin;
 insert into auth.users(id,email,email_confirmed_at) values
 ('0c500000-0000-4000-8000-000000000001','media-a@example.invalid',now()),
 ('0c500000-0000-4000-8000-000000000002','media-b@example.invalid',now()),
 ('0c500000-0000-4000-8000-000000000003','media-other@example.invalid',now()),
 ('0c500000-0000-4000-8000-000000000004','media-dev@example.invalid',now());
 insert into public.community_profiles(user_id,real_name,audience,class_group) values
 ('0c500000-0000-4000-8000-000000000001','Media A','student','3CS'),
 ('0c500000-0000-4000-8000-000000000002','Media B','student','3CS'),
 ('0c500000-0000-4000-8000-000000000003','Media Other','student','3EM');
 insert into public.school_members(user_id,role,groups) values('0c500000-0000-4000-8000-000000000004','developer','{*}');
 set local role authenticated;
 select set_config('request.jwt.claim.sub','0c500000-0000-4000-8000-000000000001',true);
 insert into storage.objects(bucket_id,name,owner_id) values
 ('community-media','0c500000-0000-4000-8000-000000000001/avatar/a.gif','0c500000-0000-4000-8000-000000000001'),
 ('community-media','0c500000-0000-4000-8000-000000000001/emoji/a.gif','0c500000-0000-4000-8000-000000000001');
 select public.community_save_profile('{"realName":"Media A","audience":"student","classGroup":"3CS","avatarPath":"0c500000-0000-4000-8000-000000000001/avatar/a.gif"}');
 select public.community_submit_emoji('media_fixture','0c500000-0000-4000-8000-000000000001/emoji/a.gif');
 do $$ begin
  begin insert into storage.objects(bucket_id,name,owner_id) values('community-media','0c500000-0000-4000-8000-000000000002/avatar/foreign.gif','0c500000-0000-4000-8000-000000000001'); raise exception 'FAIL: foreign folder upload allowed'; exception when insufficient_privilege then null; end;
  begin insert into storage.objects(bucket_id,name,owner_id) values('community-media','0c500000-0000-4000-8000-000000000001/unknown/a.gif','0c500000-0000-4000-8000-000000000001'); raise exception 'FAIL: arbitrary upload folder allowed'; exception when insufficient_privilege then null; end;
 end $$;
 select set_config('request.jwt.claim.sub','0c500000-0000-4000-8000-000000000002',true);
 do $$ begin
  if not exists(select 1 from storage.objects where name='0c500000-0000-4000-8000-000000000001/avatar/a.gif') then raise exception 'FAIL: classmate profile media not readable'; end if;
  if exists(select 1 from storage.objects where name='0c500000-0000-4000-8000-000000000001/emoji/a.gif') then raise exception 'FAIL: pending emoji publicly readable'; end if;
 end $$;
 select set_config('request.jwt.claim.sub','0c500000-0000-4000-8000-000000000003',true);
 do $$ begin
  if exists(select 1 from storage.objects where name='0c500000-0000-4000-8000-000000000001/avatar/a.gif') then raise exception 'FAIL: unrelated profile media readable'; end if;
 end $$;
 select set_config('request.jwt.claim.sub','0c500000-0000-4000-8000-000000000004',true);
 do $$ declare v_id uuid; begin
  if not exists(select 1 from storage.objects where name='0c500000-0000-4000-8000-000000000001/emoji/a.gif') then raise exception 'FAIL: Developer pending emoji image hidden'; end if;
  select (e->>'id')::uuid into v_id from jsonb_array_elements(public.community_list_emojis(true)) e where e->>'name'='media_fixture';
  perform public.community_review_emoji(v_id,true);
 end $$;
 select set_config('request.jwt.claim.sub','0c500000-0000-4000-8000-000000000003',true);
 do $$ begin
  if not exists(select 1 from storage.objects where name='0c500000-0000-4000-8000-000000000001/emoji/a.gif') then raise exception 'FAIL: approved emoji unavailable'; end if;
 end $$;
 select set_config('request.jwt.claim.sub','0c500000-0000-4000-8000-000000000001',true);
 do $$ begin
  for i in 3..10 loop insert into storage.objects(bucket_id,name,owner_id) values('community-media','0c500000-0000-4000-8000-000000000001/chat/'||i||'.gif','0c500000-0000-4000-8000-000000000001'); end loop;
  begin insert into storage.objects(bucket_id,name,owner_id) values('community-media','0c500000-0000-4000-8000-000000000001/chat/limit.gif','0c500000-0000-4000-8000-000000000001'); raise exception 'FAIL: upload rate limit not enforced'; exception when sqlstate 'P0001' then null; end;
 end $$;
 reset role;
 rollback;
`);
console.log('PASS mocked storage RLS: ownership, private profile media, pending/approved emoji access, upload limits.');
console.log('Mocked storage schema: real Supabase upload policy semantics require separate live verification.');
for (const path of ['supabase/migrations/202610120007_chat_identity_and_channels.sql','supabase/migrations/202610120008_production_chat.sql','supabase/tests/production-chat.sql']) {
 console.log('Executing',path); try { await db.exec(await fs.readFile(path,'utf8')); } catch(e) { console.error(JSON.stringify({message:e.message,code:e.code,where:e.where,detail:e.detail})); process.exit(1); } console.log('PASS',path);
}
for (const path of ['supabase/migrations/202610130009_chat_controls.sql','supabase/tests/chat-controls.sql']) {
 console.log('Executing',path); await db.exec(await fs.readFile(path,'utf8')); console.log('PASS',path);
}
await db.exec("create function storage.foldername(name text) returns text[] language sql immutable as $$ select (string_to_array(name,'/'))[1:array_length(string_to_array(name,'/'),1)-1] $$;");
await db.exec("insert into auth.users(id,email,email_confirmed_at) values('0c190000-0000-4000-8000-000000000002','developer-fixture@example.invalid',now()); insert into public.school_members(user_id,role,groups) values('0c190000-0000-4000-8000-000000000002','developer','{*}');");
for (const path of ['supabase/migrations/202610130010_staff_access_and_badges.sql','supabase/migrations/202610130011_message_interactions.sql']) { console.log('Executing',path); try { await db.exec(await fs.readFile(path,'utf8')); } catch(e) { console.error(JSON.stringify({message:e.message,code:e.code,where:e.where})); process.exit(1); } console.log('PASS',path); }
for (const path of ['supabase/migrations/202610130012_teacher_timetables.sql','supabase/migrations/202610130015_teacher_approval_messages.sql','supabase/migrations/202610130016_teacher_digitization_status.sql','supabase/tests/teacher-intake.sql']) {
 console.log('Executing',path); await db.exec(await fs.readFile(path,'utf8')); console.log('PASS',path);
}
for (const path of ['supabase/migrations/202610130013_isa_updates_sync.sql','supabase/migrations/202610130014_isa_auto_publish.sql','supabase/migrations/202610130017_isa_attachments.sql']) {
 console.log('Executing',path); await db.exec(await fs.readFile(path,'utf8')); console.log('PASS',path);
}
for (const path of ['supabase/migrations/202610130018_auto_join_schoolwide.sql','supabase/tests/auto-schoolwide.sql']) {
 console.log('Executing',path); try { await db.exec(await fs.readFile(path,'utf8')); } catch(e) { console.error(JSON.stringify({message:e.message,code:e.code,where:e.where,detail:e.detail})); process.exit(1); } console.log('PASS',path);
}
for (const path of ['supabase/migrations/202610140019_emoji_reactions_founder.sql','supabase/tests/emoji-reactions.sql']) { console.log('Executing',path); try { await db.exec(await fs.readFile(path,'utf8')); } catch(e) { console.error(JSON.stringify({message:e.message,code:e.code,where:e.where})); process.exit(1); } console.log('PASS',path); }
await db.close();


