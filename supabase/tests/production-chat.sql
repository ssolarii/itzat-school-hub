-- Rollback fixtures for admission, consent, profile visibility and channel permissions.
begin;
insert into auth.users(id,email,email_confirmed_at) select ('0c800000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'chat-'||i||'@example.invalid',case when i=8 then null else now() end from generate_series(1,8) i;
insert into public.school_members(user_id,role,groups) values ('0c800000-0000-4000-8000-000000000001','developer','{*}'),('0c800000-0000-4000-8000-000000000002','principal','{*}');
insert into public.community_admissions(user_id,name,status) select ('0c800000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'Member '||i,'approved' from unnest(array[3,5,7]) i;
insert into public.community_profiles(user_id,real_name,display_name,audience,class_group,space_onboarded,cosmetic_roles,discovery_opt_in) select ('0c800000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'Member '||i,'Display '||i,'student',case when i=5 then '3EM' else '3CS' end,true,'{music}',i=3 from unnest(array[1,2,3,5,7]) i;
create temporary table chat_test_ctx(key text primary key,value text);
grant select,insert,update on chat_test_ctx to authenticated;
insert into chat_test_ctx values ('announcements',(select id::text from public.community_rooms where school_channel='announcements'));
set local role authenticated;
select set_config('request.jwt.claim.sub','0c800000-0000-4000-8000-000000000004',true);
do $$ begin
 if (public.community_admission_state()->>'admitted')::boolean then raise exception 'FAIL: unknown account admitted'; end if;
 begin perform public.community_profiles_directory(); raise exception 'FAIL: unadmitted directory'; exception when insufficient_privilege then null; end;
 begin perform public.community_list_rooms(); raise exception 'FAIL: unadmitted rooms'; exception when insufficient_privilege then null; end;
 begin insert into storage.objects(bucket_id,name,owner_id) values('community-media',auth.uid()::text||'/chat/a.gif',auth.uid()::text); raise exception 'FAIL: unadmitted upload'; exception when insufficient_privilege then null; end;
 if exists(select 1 from public.community_messages) then raise exception 'FAIL: unadmitted realtime reads'; end if;
 insert into pg_temp.chat_test_ctx values('request',public.community_request_admission('New member','At school')::text);
end $$;
select set_config('request.jwt.claim.sub','0c800000-0000-4000-8000-000000000002',true);
do $$ begin
 begin perform public.community_review_admission((select value::uuid from pg_temp.chat_test_ctx where key='request'),true); raise exception 'FAIL: principal admission control'; exception when insufficient_privilege then null; end;
 begin perform public.community_create_invite(); raise exception 'FAIL: principal invite creation'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','0c800000-0000-4000-8000-000000000001',true);
select public.community_review_admission((select value::uuid from pg_temp.chat_test_ctx where key='request'),true);
insert into chat_test_ctx values ('invite',public.community_create_invite()->>'token');
select set_config('request.jwt.claim.sub','0c800000-0000-4000-8000-000000000006',true);
select public.community_redeem_invite((select value from chat_test_ctx where key='invite'));
do $$ begin
 if not (public.community_admission_state()->>'admitted')::boolean then raise exception 'FAIL: invite did not admit'; end if;
 begin perform public.community_redeem_invite((select value from pg_temp.chat_test_ctx where key='invite')); raise exception 'FAIL: invite reused'; exception when invalid_parameter_value then null; end;
end $$;
select set_config('request.jwt.claim.sub','0c800000-0000-4000-8000-000000000004',true);
select public.community_save_profile('{"realName":"New member","displayName":"New member","audience":"student","classGroup":"3CS"}');
select set_config('request.jwt.claim.sub','0c800000-0000-4000-8000-000000000003',true);
select public.school_space_preferences('{"status_emoji":"👩🏾‍💻","discovery_opt_in":true,"personal_tag":"Music maker"}');
select public.school_space_preferences('{"status_emoji":"🇧🇿"}');
select public.school_space_preferences('{"status_emoji":"©️"}');
select public.school_space_preferences('{"status_icon":"headphones"}');
do $$ begin
 begin perform public.school_space_preferences('{"status_emoji":"<script>","status_icon":null}'); raise exception 'FAIL: markup accepted as emoji'; exception when check_violation then null; end;
 begin perform public.school_space_preferences('{"status_icon":"evil-svg"}'); raise exception 'FAIL: unknown icon accepted'; exception when invalid_parameter_value then null; end;
 if jsonb_array_length(public.community_discover())<>0 then raise exception 'FAIL: opt-out members discovered'; end if;
end $$;
select set_config('request.jwt.claim.sub','0c800000-0000-4000-8000-000000000005',true);
select public.school_space_preferences('{"discovery_opt_in":true}');
select set_config('request.jwt.claim.sub','0c800000-0000-4000-8000-000000000003',true);
do $$ declare v jsonb; begin
 v:=public.community_discover();if jsonb_array_length(v)<>1 or v::text like '%email%' or v::text like '%Member 5%' then raise exception 'FAIL: Discovery consent or privacy'; end if;
end $$;
insert into chat_test_ctx values ('friend',public.community_request_friend('0c800000-0000-4000-8000-000000000005')::text);
select set_config('request.jwt.claim.sub','0c800000-0000-4000-8000-000000000005',true);
select public.community_respond_friend((select value::uuid from chat_test_ctx where key='friend'),true);
select set_config('request.jwt.claim.sub','0c800000-0000-4000-8000-000000000003',true);
insert into chat_test_ctx values ('friend_dm',public.community_request_room('dm','Friends','{0c800000-0000-4000-8000-000000000005}')::text);
select public.community_send_message((select value::uuid from chat_test_ctx where key='friend_dm'),'Friend DM is immediate');
insert into chat_test_ctx values ('request_dm',public.community_request_room('dm','Invitation','{0c800000-0000-4000-8000-000000000007}')::text);
do $$ begin
 begin perform public.community_send_message((select value::uuid from pg_temp.chat_test_ctx where key='request_dm'),'Before consent'); raise exception 'FAIL: pending DM send'; exception when insufficient_privilege then null; end;
 begin perform public.community_respond_room((select value::uuid from pg_temp.chat_test_ctx where key='request_dm'),true); raise exception 'FAIL: sender accepted own request'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','0c800000-0000-4000-8000-000000000007',true);
do $$ begin
 begin perform public.community_messages((select value::uuid from pg_temp.chat_test_ctx where key='request_dm')); raise exception 'FAIL: pending DM history'; exception when insufficient_privilege then null; end;
end $$;
select public.community_respond_room((select value::uuid from chat_test_ctx where key='request_dm'),true);
select public.community_send_message((select value::uuid from chat_test_ctx where key='request_dm'),'After consent');
select set_config('request.jwt.claim.sub','0c800000-0000-4000-8000-000000000003',true);
insert into chat_test_ctx values ('group',public.community_request_room('group','Friend group','{0c800000-0000-4000-8000-000000000005,0c800000-0000-4000-8000-000000000004}')::text);
select public.community_send_message((select value::uuid from chat_test_ctx where key='group'),'Group live');
select set_config('request.jwt.claim.sub','0c800000-0000-4000-8000-000000000004',true);
do $$ begin
 begin perform public.community_messages((select value::uuid from pg_temp.chat_test_ctx where key='group')); raise exception 'FAIL: unaccepted group readable'; exception when insufficient_privilege then null; end;
end $$;
select public.community_respond_room((select value::uuid from chat_test_ctx where key='group'),true);
select public.community_leave_room((select value::uuid from chat_test_ctx where key='group'));
do $$ begin
 begin perform public.community_messages((select value::uuid from pg_temp.chat_test_ctx where key='group')); raise exception 'FAIL: left group readable'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','0c800000-0000-4000-8000-000000000001',true);
insert into chat_test_ctx values ('badge',public.school_space_create_badge('Contributor','Helps people','rosette','#512393')::text);
select public.school_space_award_badge('0c800000-0000-4000-8000-000000000003',(select value::uuid from chat_test_ctx where key='badge'));
select public.school_space_save_channel((select value::uuid from chat_test_ctx where key='announcements'),'Official news','Staff updates','News','staff');
select set_config('request.jwt.claim.sub','0c800000-0000-4000-8000-000000000003',true);
do $$ begin
 begin perform public.community_send_message((select value::uuid from pg_temp.chat_test_ctx where key='announcements'),'After rename'); raise exception 'FAIL: renamed announcements lost protection'; exception when insufficient_privilege then null; end;
 perform public.school_space_preferences(jsonb_build_object('featured_badge_id',(select value from pg_temp.chat_test_ctx where key='badge')));
 if jsonb_array_length(public.school_space_get_state()#>'{profile,badges}')<>1 then raise exception 'FAIL: badge missing'; end if;
 begin perform public.school_space_create_badge('Cheater','','crown','#512393'); raise exception 'FAIL: student badge creation'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','0c800000-0000-4000-8000-000000000005',true);
do $$ begin
 begin perform public.school_space_preferences(jsonb_build_object('featured_badge_id',(select value from pg_temp.chat_test_ctx where key='badge'))); raise exception 'FAIL: unawarded badge featured'; exception when invalid_parameter_value then null; end;
 if public.community_profiles_directory()::text not like '%Contributor%' then raise exception 'FAIL: friend badges absent'; end if;
end $$;
select set_config('request.jwt.claim.sub','0c800000-0000-4000-8000-000000000001',true);
select public.school_space_set_channel_archived((select value::uuid from chat_test_ctx where key='announcements'),true);
select public.school_space_award_badge('0c800000-0000-4000-8000-000000000003',(select value::uuid from chat_test_ctx where key='badge'),false);
select set_config('request.jwt.claim.sub','0c800000-0000-4000-8000-000000000003',true);
do $$ begin
 if public.community_list_rooms()::text like '%Official news%' then raise exception 'FAIL: archive listed'; end if;
 if public.school_space_get_state()#>>'{profile,featured_badge_id}' is not null then raise exception 'FAIL: revoked badge still featured'; end if;
 begin perform school_private.school_space_get_state_v7(); raise exception 'FAIL: private alias callable'; exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
