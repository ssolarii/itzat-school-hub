begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('0b300000-0000-4000-8000-000000000001','review-leader@example.invalid',now()),
 ('0b300000-0000-4000-8000-000000000002','verified-applicant@example.invalid',now());
insert into public.school_members(user_id,role,capabilities,groups) values
 ('0b300000-0000-4000-8000-000000000001','principal','{}','{*}');
insert into public.school_teacher_requests(user_id,name,requested_groups) values
 ('0b300000-0000-4000-8000-000000000002','Claimed name','{3CS}');
set local role anon;
do $$ begin
 begin perform public.list_teacher_requests_for_review(); raise exception 'FAIL: anon identity access';
 exception when insufficient_privilege then null; end;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','0b300000-0000-4000-8000-000000000002',true);
do $$ begin
 begin perform public.list_teacher_requests_for_review(); raise exception 'FAIL: applicant identity list access';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','0b300000-0000-4000-8000-000000000001',true);
do $$ begin
 if not exists(select 1 from public.list_teacher_requests_for_review() where email='verified-applicant@example.invalid' and email_verified) then
 raise exception 'FAIL: leadership did not receive Auth verified identity'; end if;
end $$;
rollback;
select 'PASS: leadership-only verified identity; anonymous/applicant denied; fixtures rolled back' as review_identity_test_result;
