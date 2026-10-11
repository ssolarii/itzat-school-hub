-- Run in the Dashboard SQL editor AFTER migration + seed. All fixtures roll back.
-- Errors abort and roll back the transaction; success returns a PASS result row.
begin;
insert into auth.users(id,email) values
 ('0a100000-0000-4000-8000-000000000001','isa-test-developer@example.invalid'),
 ('0a100000-0000-4000-8000-000000000002','isa-test-principal@example.invalid'),
 ('0a100000-0000-4000-8000-000000000003','isa-test-teacher@example.invalid'),
 ('0a100000-0000-4000-8000-000000000004','isa-test-codeveloper@example.invalid'),
 ('0a100000-0000-4000-8000-000000000005','isa-test-viewer@example.invalid');
insert into public.school_members(user_id,role,capabilities,groups) values
 ('0a100000-0000-4000-8000-000000000001','developer','{}','{*}'),
 ('0a100000-0000-4000-8000-000000000002','principal','{}','{*}'),
 ('0a100000-0000-4000-8000-000000000003','teacher','{notices.submit}','{3CS}'),
 ('0a100000-0000-4000-8000-000000000004','codeveloper','{notices.publish}','{3CS}');

set local role anon;
do $$ begin
  if (select count(revision) from public.school_versions) < 1 then raise exception 'FAIL: no public schedule'; end if;
  begin
    perform * from public.school_members;
    raise exception 'FAIL: anonymous membership read allowed';
  exception when insufficient_privilege then null; end;
  begin
    perform public.get_my_school_membership();
    raise exception 'FAIL: anonymous membership RPC allowed';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.school_versions(document) values('{}');
    raise exception 'FAIL: anonymous direct publish allowed';
  exception when insufficient_privilege then null; end;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','0a100000-0000-4000-8000-000000000005',true);
select set_config('request.jwt.claims','{"sub":"0a100000-0000-4000-8000-000000000005","role":"authenticated"}',true);
do $$ declare v_document jsonb; v_revision bigint; begin
  if public.get_my_school_membership() is not null or (select count(*) from public.school_members) <> 0 then raise exception 'FAIL: unsigned member granted access'; end if;
  if (select count(*) from public.school_audit_events) <> 0 then raise exception 'FAIL: viewer can read audit'; end if;
  select document,revision into v_document,v_revision from public.school_versions order by revision desc limit 1;
  begin
    perform public.publish_school_document(v_document,v_revision);
    raise exception 'FAIL: ordinary account published';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.school_members(user_id,role) values(auth.uid(),'developer');
    raise exception 'FAIL: self elevation allowed';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','0a100000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"0a100000-0000-4000-8000-000000000003","role":"authenticated"}',true);
do $$ declare v_document jsonb; v_revision bigint; v_id uuid; begin
  if public.get_my_school_membership()->>'role' <> 'teacher' or (select count(*) from public.school_members) <> 1 then raise exception 'FAIL: own teacher membership'; end if;
  v_id := public.submit_school_notice('{"title":"Test class notice","body":"Draft only","audience":"3CS"}');
  if (select status from public.school_notice_drafts where id=v_id) <> 'pending' then raise exception 'FAIL: teacher draft missing'; end if;
  begin
    perform public.submit_school_notice('{"title":"Out of scope","body":"Should fail","audience":"1A"}');
    raise exception 'FAIL: teacher posted outside scope';
  exception when insufficient_privilege then null; end;
  select document,revision into v_document,v_revision from public.school_versions order by revision desc limit 1;
  begin
    perform public.publish_school_document(v_document,v_revision);
    raise exception 'FAIL: teacher directly published';
  exception when insufficient_privilege then null; end;
  begin
    perform public.set_school_member('0a100000-0000-4000-8000-000000000005','developer','{}','{*}',true);
    raise exception 'FAIL: teacher granted developer';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','0a100000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"0a100000-0000-4000-8000-000000000004","role":"authenticated"}',true);
do $$ declare v_document jsonb; v_revision bigint; v_published bigint; v_id uuid; begin
  select id into v_id from public.school_notice_drafts where notice->>'title'='Test class notice' and status='pending' order by created_at desc limit 1;
  select document,revision into v_document,v_revision from public.school_versions order by revision desc limit 1;
  select revision into v_published from public.approve_school_notice(v_id,v_revision);
  if v_published <= v_revision then raise exception 'FAIL: scoped reviewer could not publish class notice'; end if;
  begin
    perform public.publish_school_document(v_document,v_revision);
    raise exception 'FAIL: stale revision overwrote changes';
  exception when serialization_failure then null; end;
  select document,revision into v_document,v_revision from public.school_versions order by revision desc limit 1;
  begin
    perform public.publish_school_document(jsonb_set(v_document,'{settings,anchorDay}','2'),v_revision);
    raise exception 'FAIL: notice reviewer edited schedules';
  exception when insufficient_privilege then null; end;
  begin
    perform public.publish_school_document(jsonb_set(v_document,'{announcements}',v_document->'announcements' || jsonb_build_array(jsonb_build_object('id','out-of-scope-test','title','Unauthorized school notice','body','Test','audience','school','approved',true,'publishedAt',now()))),v_revision);
    raise exception 'FAIL: scoped reviewer published schoolwide';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','0a100000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"0a100000-0000-4000-8000-000000000002","role":"authenticated"}',true);
do $$ declare v_document jsonb; v_revision bigint; v_archived jsonb; begin
  select document,revision into v_document,v_revision from public.school_versions order by revision desc limit 1;
  perform public.publish_school_document(v_document,v_revision);
  select document,revision into v_document,v_revision from public.school_versions order by revision desc limit 1;
  begin
    perform public.publish_school_document(jsonb_set(v_document,'{bellProfiles,regular,slots,0,end}','"07:00"'),v_revision);
    raise exception 'FAIL: invalid bell times accepted';
  exception when invalid_parameter_value then null; end;
  select jsonb_agg(key) into v_archived from jsonb_object_keys(v_document->'groups') key;
  begin
    perform public.publish_school_document(jsonb_set(v_document,'{archivedGroups}',v_archived),v_revision);
    raise exception 'FAIL: every class could be archived';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.set_school_member('0a100000-0000-4000-8000-000000000005','developer','{}','{*}',true);
    raise exception 'FAIL: principal granted developer';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','0a100000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"0a100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ begin
  perform public.set_school_member('0a100000-0000-4000-8000-000000000005','teacher','{notices.submit}','{1A}',true);
  begin
    perform public.set_school_member('0a100000-0000-4000-8000-000000000005','teacher','{schedules.manage}','{1A}',true);
    raise exception 'FAIL: unbounded teacher grant allowed';
  exception when invalid_parameter_value then null; end;
end $$;
reset role;
rollback;
select 'PASS: public read, account isolation, teacher scopes, reviewer scopes, concurrency, validation, grants; all fixtures rolled back' as authorization_test_result;
