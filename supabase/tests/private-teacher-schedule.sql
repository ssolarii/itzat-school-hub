begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('0c200000-0000-4000-8000-000000000001','private-teacher@example.invalid',now()),
 ('0c200000-0000-4000-8000-000000000002','unrelated@example.invalid',now());
insert into public.teacher_timetable_uploads(teacher_id,image_path,status,digitized_schedule) values('0c200000-0000-4000-8000-000000000001','private/source.png','digitized','{"version":1,"entries":[{"day":7,"session":5,"span":2,"subject":"PLC","room":"MS","groups":[]}]}');
do $$ begin
 begin update public.teacher_timetable_uploads set digitized_schedule='{"entries":[]}' where teacher_id='0c200000-0000-4000-8000-000000000001'; raise exception 'Missing version accepted'; exception when check_violation then null; end;
 begin update public.teacher_timetable_uploads set digitized_schedule='{"version":1,"entries":[{"day":8,"session":1,"subject":"BS","groups":[]}]}' where teacher_id='0c200000-0000-4000-8000-000000000001'; raise exception 'Invalid day accepted'; exception when check_violation then null; end;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','0c200000-0000-4000-8000-000000000001',true);
do $$ begin if not exists(select 1 from public.teacher_timetable_uploads where digitized_schedule->>'version'='1') then raise exception 'Own schedule unavailable'; end if; end $$;
select set_config('request.jwt.claim.sub','0c200000-0000-4000-8000-000000000002',true);
do $$ begin if exists(select 1 from public.teacher_timetable_uploads) then raise exception 'Unrelated account can see private teacher schedule'; end if; end $$;
reset role;
rollback;
