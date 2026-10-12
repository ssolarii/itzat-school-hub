-- Run after migration 004 and the school seed. Test identities and all changes roll back.
-- No real account is granted a role, no storage object is uploaded, and nothing is committed.
begin;

insert into auth.users(id,email,email_confirmed_at) values
 ('0c400000-0000-4000-8000-000000000001','community-a@example.invalid',now()),
 ('0c400000-0000-4000-8000-000000000002','community-b@example.invalid',now()),
 ('0c400000-0000-4000-8000-000000000003','community-other@example.invalid',now()),
 ('0c400000-0000-4000-8000-000000000004','community-parent@example.invalid',now()),
 ('0c400000-0000-4000-8000-000000000005','community-principal@example.invalid',now()),
 ('0c400000-0000-4000-8000-000000000006','community-developer@example.invalid',now()),
 ('0c400000-0000-4000-8000-000000000007','community-unverified@example.invalid',null);
insert into public.school_members(user_id,role,capabilities,groups) values
 ('0c400000-0000-4000-8000-000000000005','principal','{}','{*}'),
 ('0c400000-0000-4000-8000-000000000006','developer','{}','{*}');
insert into public.community_profiles(user_id,real_name,display_name,audience,class_group,bio) values
 ('0c400000-0000-4000-8000-000000000001','Private Student A','Student A','student','3CS','Private biography A'),
 ('0c400000-0000-4000-8000-000000000002','Private Student B','Student B','student','3CS','Private biography B'),
 ('0c400000-0000-4000-8000-000000000003','Private Other Student','','student','3EM','Private other biography'),
 ('0c400000-0000-4000-8000-000000000004','Private Parent','','parent',null,'Private parent biography');
insert into public.community_rooms(id,kind,title,class_group,status,created_by) values
 ('0c410000-0000-4000-8000-000000000001','class','Fixture class chat','3CS','approved',null),
 ('0c410000-0000-4000-8000-000000000002','dm','Fixture private conversation',null,'approved','0c400000-0000-4000-8000-000000000001'),
 ('0c410000-0000-4000-8000-000000000003','group','Fixture pending conversation',null,'pending','0c400000-0000-4000-8000-000000000001')
 on conflict do nothing;
create temporary table community_test_ctx(key text primary key,value text);
insert into community_test_ctx values('classroom',(select id::text from public.community_rooms where kind='class' and class_group='3CS'));
grant select on community_test_ctx to authenticated;
insert into public.community_room_members(room_id,user_id) values
 ('0c410000-0000-4000-8000-000000000002','0c400000-0000-4000-8000-000000000001'),
 ('0c410000-0000-4000-8000-000000000002','0c400000-0000-4000-8000-000000000002'),
 ('0c410000-0000-4000-8000-000000000003','0c400000-0000-4000-8000-000000000001'),
 ('0c410000-0000-4000-8000-000000000003','0c400000-0000-4000-8000-000000000002');
insert into public.community_posts(id,author_id,scope,class_group,title,status) values
 ('0c420000-0000-4000-8000-000000000001','0c400000-0000-4000-8000-000000000001','site',null,'Fixture public suggestion','approved'),
 ('0c420000-0000-4000-8000-000000000002','0c400000-0000-4000-8000-000000000001','site',null,'Fixture pending suggestion','pending'),
 ('0c420000-0000-4000-8000-000000000003','0c400000-0000-4000-8000-000000000001','class','3CS','Fixture private class poll','approved');

set local role anon;
do $$ declare v_posts jsonb; begin
 v_posts:=public.community_list_posts('site');
 if not exists(select 1 from jsonb_array_elements(v_posts) p where p->>'id'='0c420000-0000-4000-8000-000000000001') then raise exception 'FAIL: public approved suggestion missing'; end if;
 if exists(select 1 from jsonb_array_elements(v_posts) p where p->>'id'='0c420000-0000-4000-8000-000000000002' or p->>'author_id' is not null or p->>'author_name' like 'Private%') then raise exception 'FAIL: anonymous feed leaks pending post or identity'; end if;
 begin perform public.community_vote('0c420000-0000-4000-8000-000000000001',true); raise exception 'FAIL: anonymous vote allowed'; exception when insufficient_privilege then null; end;
 begin perform public.community_get_profile(); raise exception 'FAIL: anonymous profile lookup allowed'; exception when insufficient_privilege then null; end;
 begin perform public.community_list_posts('class','3CS'); raise exception 'FAIL: anonymous class feed allowed'; exception when insufficient_privilege then null; end;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','0c400000-0000-4000-8000-000000000007',true);
select set_config('request.jwt.claims','{"sub":"0c400000-0000-4000-8000-000000000007","role":"authenticated","user_metadata":{"email_verified":true}}',true);
do $$ begin
 begin perform public.community_get_profile(); raise exception 'FAIL: forged metadata verified an unconfirmed account'; exception when insufficient_privilege then null; end;
 begin perform public.community_vote('0c420000-0000-4000-8000-000000000001',true); raise exception 'FAIL: unverified vote allowed'; exception when insufficient_privilege then null; end;
 begin perform public.community_profiles_directory(); raise exception 'FAIL: unverified directory allowed'; exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','0c400000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"0c400000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ declare v_message bigint; v_room uuid; v_post uuid; begin
 if jsonb_array_length(public.community_list_posts('class','3CS'))<1 then raise exception 'FAIL: own class feed missing'; end if;
 begin perform * from public.community_profiles; raise exception 'FAIL: direct profile table read granted'; exception when insufficient_privilege then null; end;
 begin update public.community_rooms set status='approved'; raise exception 'FAIL: direct room self approval allowed'; exception when insufficient_privilege then null; end;
 begin perform public.community_messages('0c410000-0000-4000-8000-000000000003'); raise exception 'FAIL: pending group readable'; exception when insufficient_privilege then null; end;
 begin perform public.community_review_room('0c410000-0000-4000-8000-000000000003',true); raise exception 'FAIL: student approved group'; exception when insufficient_privilege then null; end;
 begin perform public.community_announce('Unauthorized','Body'); raise exception 'FAIL: student developer announcement allowed'; exception when insufficient_privilege then null; end;
 begin perform public.community_set_decision('0c420000-0000-4000-8000-000000000001','yes'); raise exception 'FAIL: student implementation decision allowed'; exception when insufficient_privilege then null; end;
 begin perform public.community_save_profile('{"realName":"Fake Teacher","audience":"teacher"}'); raise exception 'FAIL: student self granted teacher profile'; exception when insufficient_privilege then null; end;
 begin perform public.community_save_profile('{"realName":"Student A","audience":"student","classGroup":"UNKNOWN"}'); raise exception 'FAIL: nonexistent class allowed'; exception when invalid_parameter_value then null; end;
 v_message:=public.community_send_message('0c410000-0000-4000-8000-000000000002','Reported fixture message');
 perform public.community_send_message('0c410000-0000-4000-8000-000000000002','Unreported fixture secret');
 perform public.community_report_message(v_message,'Fixture report');
 v_room:=public.community_request_room('dm','New fixture request',array['0c400000-0000-4000-8000-000000000002']::uuid[]);
 begin perform public.community_send_message(v_room,'Premature message'); raise exception 'FAIL: requested DM usable before review'; exception when insufficient_privilege then null; end;
 v_post:=public.community_create_post('site','New fixture suggestion','Needs developer review');
 if not exists(select 1 from jsonb_array_elements(public.community_list_posts('site')) p where p->>'id'=v_post::text and p->>'status'='pending') then raise exception 'FAIL: author cannot see pending suggestion'; end if;
 perform public.community_vote('0c420000-0000-4000-8000-000000000001',true);
 perform public.community_like('0c420000-0000-4000-8000-000000000001',true);
 perform public.community_vote('0c420000-0000-4000-8000-000000000001',false);
 if not exists(select 1 from jsonb_array_elements(public.community_list_posts('site')) p where p->>'id'='0c420000-0000-4000-8000-000000000001' and p->>'my_vote'='false' and p->>'my_like'='true' and (p->>'yes_count')::int=0 and (p->>'no_count')::int=1 and (p->>'like_count')::int=1) then raise exception 'FAIL: vote replacement and likes were conflated'; end if;
 begin perform public.community_send_message('0c410000-0000-4000-8000-000000000002','', '0c400000-0000-4000-8000-000000000002/chat/not-owned.gif'); raise exception 'FAIL: foreign media path accepted'; exception when insufficient_privilege then null; end;
 begin perform public.community_send_message('0c410000-0000-4000-8000-000000000002','',null,null,'https://tracker.example.invalid/a.gif'); raise exception 'FAIL: arbitrary remote GIF URL accepted'; exception when check_violation then null; end;
end $$;

select set_config('request.jwt.claim.sub','0c400000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"0c400000-0000-4000-8000-000000000002","role":"authenticated"}',true);
do $$ declare v_denied boolean:=false; begin
 for i in 1..30 loop perform public.community_send_message('0c410000-0000-4000-8000-000000000002','Rate fixture message'); end loop;
 begin perform public.community_send_message('0c410000-0000-4000-8000-000000000002','Over limit'); exception when sqlstate 'P0001' then v_denied:=true; end;
 if not v_denied then raise exception 'FAIL: message rate limit missing'; end if;
end $$;

select set_config('request.jwt.claim.sub','0c400000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"0c400000-0000-4000-8000-000000000003","role":"authenticated"}',true);
do $$ begin
 begin perform public.community_list_posts('class','3CS'); raise exception 'FAIL: unrelated class feed readable'; exception when insufficient_privilege then null; end;
 begin perform public.community_messages('0c410000-0000-4000-8000-000000000002'); raise exception 'FAIL: unrelated DM readable'; exception when insufficient_privilege then null; end;
 begin perform public.community_vote('0c420000-0000-4000-8000-000000000003',true); raise exception 'FAIL: unrelated class vote allowed'; exception when insufficient_privilege then null; end;
 if exists(select 1 from jsonb_array_elements(public.community_list_posts('site')) p where p->>'id'='0c420000-0000-4000-8000-000000000002') then raise exception 'FAIL: unrelated account sees pending suggestion'; end if;
end $$;

select set_config('request.jwt.claim.sub','0c400000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"0c400000-0000-4000-8000-000000000004","role":"authenticated"}',true);
do $$ begin
 if exists(select 1 from jsonb_array_elements(public.community_list_posts('site')) p where p->>'id'='0c420000-0000-4000-8000-000000000001' and (p->>'author_id' is not null or p->>'author_name' like 'Private%')) then raise exception 'FAIL: site feed bypassed profile identity scope'; end if;
 if exists(select 1 from jsonb_array_elements(public.community_profiles_directory()) p where p->>'user_id'='0c400000-0000-4000-8000-000000000001' and (p->>'bio' is not null or p->>'avatar_path' is not null or p->>'banner_path' is not null)) then raise exception 'FAIL: directory exposes unrelated private profile customization'; end if;
end $$;

select set_config('request.jwt.claim.sub','0c400000-0000-4000-8000-000000000005',true);
select set_config('request.jwt.claims','{"sub":"0c400000-0000-4000-8000-000000000005","role":"authenticated"}',true);
do $$ begin
 perform public.community_review_room('0c410000-0000-4000-8000-000000000003',true);
 begin perform public.community_messages('0c410000-0000-4000-8000-000000000002'); raise exception 'FAIL: principal reads unrelated DM archive'; exception when insufficient_privilege then null; end;
 begin perform public.community_review_post('0c420000-0000-4000-8000-000000000002',true); raise exception 'FAIL: principal developer suggestion approval allowed'; exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','0c400000-0000-4000-8000-000000000006',true);
select set_config('request.jwt.claims','{"sub":"0c400000-0000-4000-8000-000000000006","role":"authenticated"}',true);
do $$ declare v_reports jsonb; begin
 perform public.community_review_post('0c420000-0000-4000-8000-000000000002',true);
 perform public.community_set_decision('0c420000-0000-4000-8000-000000000002','planned','Fixture plan');
 v_reports:=public.community_reports();
 if not exists(select 1 from jsonb_array_elements(v_reports) r where r->>'body'='Reported fixture message') then raise exception 'FAIL: developer cannot see reported message'; end if;
 if exists(select 1 from jsonb_array_elements(v_reports) r where r->>'body'='Unreported fixture secret') then raise exception 'FAIL: report disclosed adjacent DM archive'; end if;
 begin perform public.community_messages('0c410000-0000-4000-8000-000000000002'); raise exception 'FAIL: Developer reads unrelated DM archive'; exception when insufficient_privilege then null; end;
 perform public.community_pause_user('0c400000-0000-4000-8000-000000000001',now()+interval '1 hour');
end $$;

select set_config('request.jwt.claim.sub','0c400000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"0c400000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ begin
 begin perform public.community_send_message('0c410000-0000-4000-8000-000000000002','Paused message'); raise exception 'FAIL: paused member can post'; exception when insufficient_privilege then null; end;
end $$;

reset role;
update public.community_profiles set blocked_until=null where user_id='0c400000-0000-4000-8000-000000000001';
update public.school_versions set document=jsonb_set(document,'{archivedGroups}',coalesce(document->'archivedGroups','[]'::jsonb)||'["3CS"]'::jsonb) where revision=(select max(revision) from public.school_versions);
set local role authenticated;
do $$ begin
 begin perform public.community_list_posts('class','3CS'); raise exception 'FAIL: archived class feed still accessible'; exception when insufficient_privilege then null; end;
 begin perform public.community_send_message((select value::uuid from pg_temp.community_test_ctx where key='classroom'),'Archived message'); raise exception 'FAIL: archived class posting allowed'; exception when insufficient_privilege then null; end;
 begin perform public.community_save_profile('{"realName":"Student A","audience":"student","classGroup":"3CS"}'); raise exception 'FAIL: archived class selection allowed'; exception when invalid_parameter_value then null; end;
end $$;
reset role;
rollback;
