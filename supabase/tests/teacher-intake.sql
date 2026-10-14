begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('f1500000-0000-4000-8000-000000000001','teacher-fixture@example.invalid',now()),
 ('f1500000-0000-4000-8000-000000000002','developer-fixture@example.invalid',now()),
 ('f1500000-0000-4000-8000-000000000003','student-fixture@example.invalid',now());
insert into public.school_members(user_id,role,capabilities,groups,active) values
 ('f1500000-0000-4000-8000-000000000002','developer','{}','{*}',true);
insert into public.school_teacher_requests(id,user_id,name,requested_groups) values
 ('f1500000-0000-4000-8000-000000000010','f1500000-0000-4000-8000-000000000001','Teacher fixture','{3CS}');
set local role authenticated;
select set_config('request.jwt.claim.sub','f1500000-0000-4000-8000-000000000002',true);
select public.review_teacher_access('f1500000-0000-4000-8000-000000000010',true,array['3CS'],'Welcome. Please upload your timetable.');
select set_config('request.jwt.claim.sub','f1500000-0000-4000-8000-000000000001',true);
do $$ begin
 if not exists(select 1 from public.school_teacher_requests where approval_message='Welcome. Please upload your timetable.') then raise exception 'Approval message missing'; end if;
 if school_private.community_room_access(gen_random_uuid()) then raise exception 'Teacher chat access'; end if;
 begin perform public.set_teacher_approval_message('f1500000-0000-4000-8000-000000000010','Tamper'); raise exception 'Teacher changed approval message'; exception when insufficient_privilege then null; end;
 begin perform public.submit_teacher_timetable(auth.uid()::text||'/missing.png'); raise exception 'Missing image accepted'; exception when invalid_parameter_value then null; end;
end $$;
insert into storage.objects(bucket_id,name,owner_id) values('teacher-timetables','f1500000-0000-4000-8000-000000000001/timetable.png',auth.uid()::text);
select public.submit_teacher_timetable('f1500000-0000-4000-8000-000000000001/timetable.png');
do $$ begin
 if not exists(select 1 from public.teacher_timetable_uploads where status='pending') then raise exception 'Upload not queued'; end if;
 if not exists(select 1 from storage.objects where bucket_id='teacher-timetables') then raise exception 'Own image hidden'; end if;
end $$;
select set_config('request.jwt.claim.sub','f1500000-0000-4000-8000-000000000003',true);
do $$ begin
 if exists(select 1 from public.teacher_timetable_uploads) then raise exception 'Student can read teacher uploads'; end if;
 if exists(select 1 from public.school_teacher_requests where approval_message<>'') then raise exception 'Student can read teacher approval'; end if;
 if exists(select 1 from storage.objects where bucket_id='teacher-timetables') then raise exception 'Student can read teacher image'; end if;
 begin insert into storage.objects(bucket_id,name,owner_id) values('teacher-timetables',auth.uid()::text||'/unauthorized.png',auth.uid()::text); raise exception 'Student can upload teacher image'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','f1500000-0000-4000-8000-000000000002',true);
do $$ begin
 if not exists(select 1 from public.teacher_timetable_uploads) then raise exception 'Leadership queue unavailable'; end if;
 if not exists(select 1 from storage.objects where bucket_id='teacher-timetables') then raise exception 'Leadership image unavailable'; end if;
end $$;
reset role;
insert into public.school_versions(document,published_by)
 select jsonb_set(document,'{teacherAssignments}','[{"teacher":"f1500000-0000-4000-8000-000000000001","group":"3CS","day":1,"session":1}]'::jsonb),'f1500000-0000-4000-8000-000000000002'::uuid from public.school_versions order by revision desc limit 1;
set local role authenticated;
select set_config('request.jwt.claim.sub','f1500000-0000-4000-8000-000000000002',true);
do $$ declare v_revision bigint; begin
 select max(revision) into v_revision from public.school_versions;
 begin perform public.complete_teacher_timetable('f1500000-0000-4000-8000-000000000001','stale.png',v_revision); raise exception 'Stale image accepted'; exception when serialization_failure then null; end;
 perform public.complete_teacher_timetable('f1500000-0000-4000-8000-000000000001','f1500000-0000-4000-8000-000000000001/timetable.png',v_revision);
 if not exists(select 1 from public.teacher_timetable_uploads where status='digitized') then raise exception 'Digitization status missing'; end if;
end $$;
reset role;
rollback;
