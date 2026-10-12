-- 006 school-space access and authority fixtures. All changes roll back.
begin;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='community_messages') then raise exception 'FAIL: authorized realtime table was not published'; end if;
end $$;
insert into auth.users(id,email,email_confirmed_at) select
 ('0c700000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'space-'||i||'@example.invalid',case when i=8 then null else now() end from generate_series(1,8) i;
insert into public.community_profiles(user_id,real_name,display_name,audience,class_group,bio,space_onboarded) select
 ('0c700000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'Space Private '||i,'Space Display '||i,
 case when i in (3,7,8) then 'parent' when i=5 then 'teacher' else 'student' end,
 case when i not in (3,5,7,8) then '3CS' end,'School consent bio '||i,i<7 from generate_series(1,8) i;
update public.community_profiles set class_group='3EM' where user_id='0c700000-0000-4000-8000-000000000002';
insert into public.school_members(user_id,role,groups) values
 ('0c700000-0000-4000-8000-000000000005','teacher','{3CS}'),
 ('0c700000-0000-4000-8000-000000000006','developer','{*}');
insert into public.community_emojis(id,name,media_path,status) values
 ('0c720000-0000-4000-8000-000000000001','approved_status_fixture','fixture/not-a-real-upload.gif','approved'),
 ('0c720000-0000-4000-8000-000000000002','pending_status_fixture','fixture/not-a-real-upload-2.gif','pending');
insert into public.community_rooms(id,kind,title,status) values('0c710000-0000-4000-8000-000000000001','dm','Unrelated DM','approved');
insert into public.community_room_members(room_id,user_id) values
 ('0c710000-0000-4000-8000-000000000001','0c700000-0000-4000-8000-000000000001'),
 ('0c710000-0000-4000-8000-000000000001','0c700000-0000-4000-8000-000000000002');
insert into public.community_messages(room_id,author_id,body) values('0c710000-0000-4000-8000-000000000001','0c700000-0000-4000-8000-000000000001','Private DM realtime fixture');
create temporary table space_test_ctx(key text primary key,value text);
insert into space_test_ctx values
 ('general',(select id::text from public.community_rooms where school_channel='general')),
 ('announcements',(select id::text from public.community_rooms where school_channel='announcements'));
grant select,insert,update on space_test_ctx to authenticated;

set local role anon;
do $$ begin
 begin perform public.school_space_get_state(); raise exception 'FAIL: anonymous space access allowed'; exception when insufficient_privilege then null; end;
 begin perform * from public.community_messages; raise exception 'FAIL: anonymous realtime table access allowed'; exception when insufficient_privilege then null; end;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','0c700000-0000-4000-8000-000000000008',true);
do $$ begin
 begin perform public.school_space_get_state(); raise exception 'FAIL: unverified school space allowed'; exception when insufficient_privilege then null; end;
 if exists(select 1 from public.community_messages) then raise exception 'FAIL: unverified realtime messages readable'; end if;
end $$;
select set_config('request.jwt.claim.sub','0c700000-0000-4000-8000-000000000007',true);
do $$ declare v_state jsonb; begin
 v_state:=public.school_space_get_state();
 if jsonb_array_length(v_state->'channels')<>0 or jsonb_array_length(v_state->'members')<>0 then raise exception 'FAIL: no-consent profile exposed school space'; end if;
 if school_private.community_profile_access('0c700000-0000-4000-8000-000000000002') then raise exception 'FAIL: nonjoined account sees crossclass private school profile'; end if;
 begin perform public.community_messages((select value::uuid from pg_temp.space_test_ctx where key='general')); raise exception 'FAIL: nonjoined school channel readable'; exception when insufficient_privilege then null; end;
 v_state:=public.school_space_preferences('{"status_text":"Waiting to join","theme":"dark"}');
 if v_state#>>'{profile,space_onboarded}'<>'false' then raise exception 'FAIL: partial profile edit granted school consent'; end if;
 v_state:=public.school_space_preferences('{"cosmetic_roles":["music"],"name_color":"#123456","space_onboarded":true}');
 if v_state#>>'{profile,status_text}'<>'Waiting to join' or v_state#>>'{profile,theme}'<>'dark' then raise exception 'FAIL: partial onboarding erased preferences'; end if;
 -- Restore fixture consent state so later member-visibility assertions remain meaningful.
 perform public.school_space_preferences('{"space_onboarded":false}');
end $$;
select set_config('request.jwt.claim.sub','0c700000-0000-4000-8000-000000000001',true);
do $$ declare v_state jsonb; v_id bigint; begin
 v_state:=public.school_space_get_state();
 if jsonb_array_length(v_state->'channels')<>3 then raise exception 'FAIL: joined school channels missing'; end if;
 if exists(select 1 from jsonb_array_elements(v_state->'members') m where m->>'user_id'='0c700000-0000-4000-8000-000000000007') then raise exception 'FAIL: nonconsenting member appears schoolwide'; end if;
 if exists(select 1 from jsonb_array_elements(v_state->'members') m where (m->>'online')::boolean) then raise exception 'FAIL: fabricated online presence'; end if;
 if not school_private.community_profile_access('0c700000-0000-4000-8000-000000000002') then raise exception 'FAIL: consenting crossclass school profile unavailable'; end if;
 begin perform public.school_space_preferences('{"cosmetic_roles":["Developer"],"space_onboarded":true}'); raise exception 'FAIL: authority role chosen cosmetically'; exception when invalid_parameter_value then null; end;
 begin perform public.school_space_preferences('{"cosmetic_roles":[],"space_onboarded":true,"permissions":["kick_members"]}'); raise exception 'FAIL: self granted preferences permissions'; exception when invalid_parameter_value then null; end;
 begin perform public.school_space_preferences('{"cosmetic_roles":[],"space_onboarded":true,"status_emoji":"<script>"}'); raise exception 'FAIL: arbitrary text accepted as emoji'; exception when invalid_parameter_value then null; end;
 begin perform public.school_space_preferences('{"cosmetic_roles":[],"space_onboarded":true,"status_emoji_id":"0c720000-0000-4000-8000-000000000002"}'); raise exception 'FAIL: pending emoji used for status'; exception when invalid_parameter_value then null; end;
 v_state:=public.school_space_preferences('{"cosmetic_roles":["creative","night-owl"],"space_onboarded":true,"status_text":"Doing homework","status_emoji":"📚","name_color":"#147855","theme":"dark"}');
 if v_state#>>'{profile,status_emoji}'<>'📚' or v_state#>>'{profile,theme}'<>'dark' or jsonb_array_length(v_state#>'{authority,permissions}')<>0 then raise exception 'FAIL: cosmetic preferences changed authority or did not persist'; end if;
 v_state:=public.school_space_preferences('{"status_text":"Finished homework"}');
 if v_state#>>'{profile,status_emoji}'<>'📚' or v_state#>>'{profile,theme}'<>'dark' or v_state#>>'{profile,space_onboarded}'<>'true' then raise exception 'FAIL: partial status edit erased preferences or consent'; end if;
 begin perform public.school_space_preferences('{"theme":null}'); raise exception 'FAIL: null theme accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.school_space_preferences('{"space_onboarded":null}'); raise exception 'FAIL: null consent accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.school_space_save_profile('{"realName":"Should roll back","displayName":"Changed","audience":"student","classGroup":"3CS"}','{"name_color":"invalid"}'); raise exception 'FAIL: invalid combined preferences accepted'; exception when invalid_parameter_value then null; end;
 if public.community_get_profile()->>'real_name'<>'Space Private 1' then raise exception 'FAIL: atomic profile edit partially persisted'; end if;
 if exists(select 1 from jsonb_array_elements(public.community_profiles_directory()) p where p ? 'theme') then raise exception 'FAIL: account theme leaked through directory'; end if;
 begin perform public.school_space_assign_moderator('0c700000-0000-4000-8000-000000000004',array['kick_members']); raise exception 'FAIL: student assigned Moderator'; exception when insufficient_privilege then null; end;
 begin perform public.community_send_message((select value::uuid from pg_temp.space_test_ctx where key='announcements'),'Student announcement'); raise exception 'FAIL: student posted staff announcement'; exception when insufficient_privilege then null; end;
 v_id:=public.community_send_message((select value::uuid from pg_temp.space_test_ctx where key='general'),'School realtime fixture');
 insert into pg_temp.space_test_ctx values('school_message',v_id::text);
 if not exists(select 1 from public.community_messages where id=v_id) then raise exception 'FAIL: authorized realtime message missing'; end if;
 perform public.school_space_heartbeat();
 if not exists(select 1 from jsonb_array_elements(public.school_space_members()) m where m->>'user_id'='0c700000-0000-4000-8000-000000000001' and (m->>'online')::boolean) then raise exception 'FAIL: real heartbeat missing online status'; end if;
end $$;

-- Friends can share scoped status independently of school-space consent; themes remain private.
select public.community_request_friend('0c700000-0000-4000-8000-000000000007');
select set_config('request.jwt.claim.sub','0c700000-0000-4000-8000-000000000007',true);
do $$ declare v_id uuid; begin
 select (f->>'id')::uuid into v_id from jsonb_array_elements(public.community_list_friends()) f where f->>'other_id'='0c700000-0000-4000-8000-000000000001';
 perform public.community_respond_friend(v_id,true);
end $$;
select set_config('request.jwt.claim.sub','0c700000-0000-4000-8000-000000000001',true);
do $$ begin
 if not exists(select 1 from jsonb_array_elements(public.community_list_friends()) f where f->>'other_id'='0c700000-0000-4000-8000-000000000007' and f->>'status_text'='Waiting to join' and not f ? 'theme') then raise exception 'FAIL: scoped friend status missing or private theme exposed'; end if;
end $$;

select set_config('request.jwt.claim.sub','0c700000-0000-4000-8000-000000000005',true);
do $$ begin
 if public.school_space_get_state()#>>'{authority,role}'<>'Teacher' then raise exception 'FAIL: staff-derived Teacher role missing'; end if;
 perform public.community_send_message((select value::uuid from pg_temp.space_test_ctx where key='announcements'),'Approved teacher announcement');
 begin perform public.school_space_kick('0c700000-0000-4000-8000-000000000002',true); raise exception 'FAIL: Teacher gained kick permission implicitly'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','0c700000-0000-4000-8000-000000000006',true);
do $$ begin
 if exists(select 1 from public.community_messages where room_id='0c710000-0000-4000-8000-000000000001') then raise exception 'FAIL: realtime grant bypassed Developer private DM boundary'; end if;
 perform public.school_space_assign_moderator('0c700000-0000-4000-8000-000000000004',array['manage_messages','upload_emojis','kick_members']);
end $$;
select set_config('request.jwt.claim.sub','0c700000-0000-4000-8000-000000000004',true);
do $$ begin
 if public.school_space_get_state()#>>'{authority,role}'<>'Moderator' then raise exception 'FAIL: approved Moderator authority missing'; end if;
 perform public.school_space_remove_message((select value::bigint from pg_temp.space_test_ctx where key='school_message'));
 if exists(select 1 from public.community_messages where id=(select value::bigint from pg_temp.space_test_ctx where key='school_message')) then raise exception 'FAIL: removed content exposed through realtime grant'; end if;
 begin perform public.school_space_remove_message((select min(id) from public.community_messages where room_id='0c710000-0000-4000-8000-000000000001')); raise exception 'FAIL: Moderator removed private DM'; exception when invalid_parameter_value then null; end;
 begin perform public.school_space_kick('0c700000-0000-4000-8000-000000000005',true); raise exception 'FAIL: Moderator kicked staff'; exception when insufficient_privilege then null; end;
 perform public.school_space_kick('0c700000-0000-4000-8000-000000000002',true);
end $$;
select set_config('request.jwt.claim.sub','0c700000-0000-4000-8000-000000000002',true);
do $$ declare v_state jsonb; begin
 v_state:=public.school_space_get_state();
 if jsonb_array_length(v_state->'channels')<>0 or v_state#>>'{authority,kicked}'<>'true' then raise exception 'FAIL: excluded user still has school space'; end if;
 begin perform public.community_messages((select value::uuid from pg_temp.space_test_ctx where key='general')); raise exception 'FAIL: excluded school history readable'; exception when insufficient_privilege then null; end;
 perform public.community_messages('0c710000-0000-4000-8000-000000000001');
 perform public.community_list_posts('class','3EM');
end $$;
select set_config('request.jwt.claim.sub','0c700000-0000-4000-8000-000000000003',true);
do $$ begin
 if public.school_space_get_state()#>>'{authority,role}'<>'Member' then raise exception 'FAIL: parent falsely labeled Student'; end if;
end $$;
select set_config('request.jwt.claim.sub','0c700000-0000-4000-8000-000000000001',true);
do $$ declare v_denied boolean:=false; begin
 for i in 2..6 loop perform public.school_space_heartbeat(); end loop;
 begin perform public.school_space_heartbeat(); exception when sqlstate 'P0001' then v_denied:=true; end;
 if not v_denied then raise exception 'FAIL: heartbeat server rate limit absent'; end if;
end $$;
reset role;
rollback;
