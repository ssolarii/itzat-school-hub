-- Run after both migrations and seed. All test identities/data roll back.
begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('0b200000-0000-4000-8000-000000000001','isa-teacher-request-leader@example.invalid',now()),
 ('0b200000-0000-4000-8000-000000000002','isa-teacher-request-unverified@example.invalid',null),
 ('0b200000-0000-4000-8000-000000000003','isa-teacher-request-applicant@example.invalid',now()),
 ('0b200000-0000-4000-8000-000000000004','isa-teacher-request-other@example.invalid',now()),
 ('0b200000-0000-4000-8000-000000000005','isa-teacher-request-codeveloper@example.invalid',now());
insert into public.school_members(user_id,role,capabilities,groups) values
 ('0b200000-0000-4000-8000-000000000001','principal','{}','{*}'),
 ('0b200000-0000-4000-8000-000000000005','codeveloper','{notices.publish}','{*}');

set local role anon;
do $$ begin
  begin
    perform * from public.school_teacher_requests;
    raise exception 'FAIL: anonymous request records readable';
  exception when insufficient_privilege then null; end;
  begin
    perform public.request_teacher_access('Anonymous',array['3CS'],'Test');
    raise exception 'FAIL: anonymous teacher request allowed';
  exception when insufficient_privilege then null; end;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','0b200000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"0b200000-0000-4000-8000-000000000002","role":"authenticated","user_metadata":{"email_verified":true}}',true);
do $$ begin
  begin
    perform public.request_teacher_access('Unverified account',array['3CS'],'Metadata must not establish verification');
    raise exception 'FAIL: unverified account requested access using forged metadata';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','0b200000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"0b200000-0000-4000-8000-000000000003","role":"authenticated"}',true);
do $$ declare v_id uuid; v_repeat uuid; begin
  begin
    perform public.request_teacher_access('Applicant',array['*'],'Schoolwide teacher scope must fail');
    raise exception 'FAIL: wildcard teacher request accepted';
  exception when invalid_parameter_value then null; end;
  v_id:=public.request_teacher_access('Applicant',array['3CS'],'School staff request');
  v_repeat:=public.request_teacher_access('Applicant revised',array['3CS'],'Update pending request');
  if v_id<>v_repeat or public.get_my_school_membership() is not null then raise exception 'FAIL: duplicate pending request or premature membership'; end if;
  if (select status from public.school_teacher_requests where id=v_id)<>'pending' then raise exception 'FAIL: request not pending'; end if;
  begin
    insert into public.school_teacher_requests(user_id,name,requested_groups,status) values(auth.uid(),'Self approval',array['3CS'],'approved');
    raise exception 'FAIL: direct request self approval allowed';
  exception when insufficient_privilege then null; end;
  begin
    perform public.review_teacher_access(v_id,true,array['3CS']);
    raise exception 'FAIL: applicant approved own teacher access';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','0b200000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"0b200000-0000-4000-8000-000000000004","role":"authenticated"}',true);
do $$ begin
  if exists(select 1 from public.school_teacher_requests where user_id='0b200000-0000-4000-8000-000000000003') then raise exception 'FAIL: other account read private request'; end if;
end $$;

select set_config('request.jwt.claim.sub','0b200000-0000-4000-8000-000000000005',true);
select set_config('request.jwt.claims','{"sub":"0b200000-0000-4000-8000-000000000005","role":"authenticated"}',true);
do $$ begin
  begin
    perform public.review_teacher_access('0b200000-1111-4000-8000-000000000000',true,array['3CS']);
    raise exception 'FAIL: Codeveloper approved teacher accounts';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','0b200000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"0b200000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ declare v_id uuid; v_result jsonb; v_member public.school_members; begin
  select id into v_id from public.school_teacher_requests where user_id='0b200000-0000-4000-8000-000000000003' and status='pending';
  if v_id is null then raise exception 'FAIL: principal cannot read pending request'; end if;
  begin
    perform public.review_teacher_access(v_id,true,array['*']);
    raise exception 'FAIL: principal granted schoolwide teacher scope';
  exception when invalid_parameter_value then null; end;
  v_result:=public.review_teacher_access(v_id,true,array['3CS']);
  select * into v_member from public.school_members where user_id='0b200000-0000-4000-8000-000000000003';
  if v_result->>'status'<>'approved' or v_member.role<>'teacher' or v_member.capabilities is distinct from array['notices.submit']::text[] or
    v_member.groups is distinct from array['3CS']::text[] then raise exception 'FAIL: approval produced unbounded membership'; end if;
  begin
    perform public.review_teacher_access(v_id,true,array['1A']);
    raise exception 'FAIL: reviewed request replayed';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.set_school_member('0b200000-0000-4000-8000-000000000004','developer','{}','{*}',true);
    raise exception 'FAIL: teacher review expanded principal general grant authority';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','0b200000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"0b200000-0000-4000-8000-000000000003","role":"authenticated"}',true);
do $$ begin
  if public.get_my_school_membership()->>'role'<>'teacher' then raise exception 'FAIL: approved teacher cannot load membership'; end if;
  perform public.submit_school_notice('{"title":"Approved teacher class notice","body":"Draft test","audience":"3CS"}');
  begin
    perform public.submit_school_notice('{"title":"Unauthorized audience","body":"Must fail","audience":"1A"}');
    raise exception 'FAIL: approved teacher posted outside approved audience';
  exception when insufficient_privilege then null; end;
  begin
    perform public.submit_school_notice('{"title":"Unauthorized school audience","body":"Must fail","audience":"school"}');
    raise exception 'FAIL: approved teacher posted schoolwide';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
select 'PASS: verified requests, private RLS, pending isolation, bounded principal approval, reviewer restrictions, approved teacher audience scopes; all fixtures rolled back' as teacher_requests_test_result;
