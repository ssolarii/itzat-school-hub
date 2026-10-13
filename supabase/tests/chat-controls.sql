begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('0c900000-0000-4000-8000-000000000001','controls-dev@example.invalid',now()),
 ('0c900000-0000-4000-8000-000000000002','controls-student@example.invalid',now()),
 ('0c900000-0000-4000-8000-000000000003','controls-other@example.invalid',now());
insert into public.school_members(user_id,role,groups) values('0c900000-0000-4000-8000-000000000001','developer','{*}');
insert into public.community_profiles(user_id,real_name,audience,class_group,space_onboarded) values
 ('0c900000-0000-4000-8000-000000000001','Controls Dev','student','3CS',true),
 ('0c900000-0000-4000-8000-000000000002','Controls Student','student','3CS',true),
 ('0c900000-0000-4000-8000-000000000003','Controls Other','student','3CS',true);
create temporary table controls_fixture(room uuid,report uuid);
grant all on controls_fixture to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','0c900000-0000-4000-8000-000000000001',true);
insert into controls_fixture(room) select public.school_space_save_channel_controls(null,'controls-test','Temporary','Tests','members',array['Developer','Teacher'],0);
select set_config('request.jwt.claim.sub','0c900000-0000-4000-8000-000000000002',true);
do $$ begin
 if not (public.community_admission_state()->>'admitted')::boolean then raise exception 'Verified entry remained gated'; end if;
 begin perform public.community_send_message((select room from controls_fixture),'Denied student message'); raise exception 'Student bypassed role restriction'; exception when insufficient_privilege then null; end;
 begin perform public.school_space_set_rate_limit(true,1,60); raise exception 'Student changed server rate'; exception when insufficient_privilege then null; end;
 begin perform public.community_list_user_reports(); raise exception 'Student read private reports'; exception when insufficient_privilege then null; end;
 perform public.community_report_user('0c900000-0000-4000-8000-000000000003','spam','Repeated unwanted messages.');
end; $$;
select set_config('request.jwt.claim.sub','0c900000-0000-4000-8000-000000000001',true);
do $$ begin
 if jsonb_array_length(public.community_list_user_reports())<>1 then raise exception 'Developer report queue missing'; end if;
 perform public.school_space_save_channel_controls((select room from controls_fixture),'controls-test','Temporary','Tests','members',array['Developer','Student'],10);
end; $$;
select set_config('request.jwt.claim.sub','0c900000-0000-4000-8000-000000000002',true);
do $$ begin
 perform public.community_send_message((select room from controls_fixture),'Allowed student message');
 begin perform public.community_send_message((select room from controls_fixture),'Too soon'); raise exception 'Slow mode bypassed'; exception when sqlstate 'P0001' then if sqlerrm not like 'Slow mode:%' then raise; end if; end;
end; $$;
select set_config('request.jwt.claim.sub','0c900000-0000-4000-8000-000000000001',true);
do $$ begin
 perform public.school_space_save_channel_controls((select room from controls_fixture),'controls-test','Temporary','Tests','members',null,0);
 perform public.school_space_set_rate_limit(true,1,60);
 update controls_fixture set report=(public.community_list_user_reports()->0->>'id')::uuid;
 perform public.community_review_user_report((select report from controls_fixture),'dismiss');
 if jsonb_array_length(public.community_list_user_reports())<>0 then raise exception 'Dismissed report remained open'; end if;
end; $$;
select set_config('request.jwt.claim.sub','0c900000-0000-4000-8000-000000000003',true);
do $$ begin
 perform public.community_send_message((select room from controls_fixture),'First custom-limited message');
 begin perform public.community_send_message((select room from controls_fixture),'Over custom limit'); raise exception 'Custom rate bypassed'; exception when sqlstate 'P0001' then null; end;
end; $$;
reset role;
rollback;
