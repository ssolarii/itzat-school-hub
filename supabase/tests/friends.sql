-- Rollback fixtures for 005; no real user grants or persisted relationships.
begin;
insert into auth.users(id,email,email_confirmed_at)
 select ('0c600000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'friend-'||i||'@example.invalid',case when i=20 then null else now() end from generate_series(1,20) i;
insert into public.community_profiles(user_id,real_name,display_name,audience,class_group,bio)
 select ('0c600000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'Private Friend '||i,'Friend '||i,
 case when i in (1,2) then 'student' else 'parent' end,
 case when i=1 then '3CS' when i=2 then '3EM' end,'Private bio '||i from generate_series(1,19) i;
insert into public.school_members(user_id,role,groups) values('0c600000-0000-4000-8000-000000000019','developer','{*}');
create temporary table friends_test_ctx(key text primary key,value text);
grant select,insert,update on friends_test_ctx to authenticated;

set local role anon;
do $$ begin
 begin perform public.community_list_friends(); raise exception 'FAIL: anonymous friends allowed'; exception when insufficient_privilege then null; end;
 begin perform public.community_activity(); raise exception 'FAIL: anonymous activity allowed'; exception when insufficient_privilege then null; end;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','0c600000-0000-4000-8000-000000000020',true);
do $$ begin
 begin perform public.community_list_friends(); raise exception 'FAIL: unverified friends allowed'; exception when insufficient_privilege then null; end;
 begin perform public.community_request_friend('0c600000-0000-4000-8000-000000000001'); raise exception 'FAIL: unverified request allowed'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','0c600000-0000-4000-8000-000000000001',true);
do $$ declare v_id uuid; begin
 v_id:=public.community_request_friend('0c600000-0000-4000-8000-000000000002');
 insert into pg_temp.friends_test_ctx values('friend',v_id::text);
 if school_private.community_profile_access('0c600000-0000-4000-8000-000000000002') then raise exception 'FAIL: pending request exposes private cross-class profile'; end if;
 begin perform public.community_respond_friend(v_id,true); raise exception 'FAIL: requester self accepted'; exception when insufficient_privilege then null; end;
 begin perform public.community_request_friend('0c600000-0000-4000-8000-000000000002'); raise exception 'FAIL: duplicate request allowed'; exception when invalid_parameter_value then null; end;
 begin update public.community_friendships set status='accepted'; raise exception 'FAIL: raw friendship update allowed'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','0c600000-0000-4000-8000-000000000003',true);
do $$ begin
 begin perform public.community_respond_friend((select value::uuid from pg_temp.friends_test_ctx where key='friend'),true); raise exception 'FAIL: third party accepted'; exception when insufficient_privilege then null; end;
 if jsonb_array_length(public.community_list_friends())<>0 then raise exception 'FAIL: unrelated friendship leaked'; end if;
end $$;
select set_config('request.jwt.claim.sub','0c600000-0000-4000-8000-000000000002',true);
do $$ begin
 perform public.community_respond_friend((select value::uuid from pg_temp.friends_test_ctx where key='friend'),true);
 if not school_private.community_profile_access('0c600000-0000-4000-8000-000000000001') then raise exception 'FAIL: accepted cross-class profile unavailable'; end if;
 if not exists(select 1 from jsonb_array_elements(public.community_profiles_directory()) p where p->>'user_id'='0c600000-0000-4000-8000-000000000001' and p->>'bio'='Private bio 1') then raise exception 'FAIL: accepted friend directory not enriched'; end if;
 perform public.community_remove_friend((select value::uuid from pg_temp.friends_test_ctx where key='friend'));
 if school_private.community_profile_access('0c600000-0000-4000-8000-000000000001') then raise exception 'FAIL: removed friendship retained private profile'; end if;
end $$;
select set_config('request.jwt.claim.sub','0c600000-0000-4000-8000-000000000001',true);
select public.community_request_friend('0c600000-0000-4000-8000-000000000002');
select set_config('request.jwt.claim.sub','0c600000-0000-4000-8000-000000000002',true);
select public.community_respond_friend((select value::uuid from pg_temp.friends_test_ctx where key='friend'),false);
select set_config('request.jwt.claim.sub','0c600000-0000-4000-8000-000000000001',true);
do $$ begin
 begin perform public.community_remove_friend((select value::uuid from pg_temp.friends_test_ctx where key='friend')); raise exception 'FAIL: declined request removal bypasses cooldown'; exception when invalid_parameter_value then null; end;
 begin perform public.community_request_friend('0c600000-0000-4000-8000-000000000002'); raise exception 'FAIL: decline cooldown missing'; exception when invalid_parameter_value then null; end;
 perform public.community_block_user('0c600000-0000-4000-8000-000000000002');
 perform public.community_unblock_user('0c600000-0000-4000-8000-000000000002');
 begin perform public.community_request_friend('0c600000-0000-4000-8000-000000000002'); raise exception 'FAIL: block/unblock bypasses decline cooldown'; exception when invalid_parameter_value then null; end;
end $$;

reset role;
insert into public.community_rooms(id,kind,title,status) values
 ('0c610000-0000-4000-8000-000000000001','dm','Friend fixture DM','approved'),
 ('0c610000-0000-4000-8000-000000000002','group','Friend fixture group','approved'),
 ('0c610000-0000-4000-8000-000000000003','group','Friend pending group','pending');
insert into public.community_room_members(room_id,user_id) values
 ('0c610000-0000-4000-8000-000000000001','0c600000-0000-4000-8000-000000000001'),
 ('0c610000-0000-4000-8000-000000000001','0c600000-0000-4000-8000-000000000002'),
 ('0c610000-0000-4000-8000-000000000002','0c600000-0000-4000-8000-000000000001'),
 ('0c610000-0000-4000-8000-000000000002','0c600000-0000-4000-8000-000000000002'),
 ('0c610000-0000-4000-8000-000000000002','0c600000-0000-4000-8000-000000000003'),
 ('0c610000-0000-4000-8000-000000000003','0c600000-0000-4000-8000-000000000001'),
 ('0c610000-0000-4000-8000-000000000003','0c600000-0000-4000-8000-000000000002');
insert into public.community_messages(room_id,author_id,body)
 select '0c610000-0000-4000-8000-000000000001','0c600000-0000-4000-8000-000000000002','Notification secret '||i from generate_series(1,101) i;
insert into public.community_messages(room_id,author_id,body) values
 ('0c610000-0000-4000-8000-000000000002','0c600000-0000-4000-8000-000000000003','Group notification secret'),
 ('0c610000-0000-4000-8000-000000000001','0c600000-0000-4000-8000-000000000001','Own notification secret');
set local role authenticated;
select set_config('request.jwt.claim.sub','0c600000-0000-4000-8000-000000000001',true);
do $$ declare v_first jsonb; v_page jsonb; v_second jsonb; begin
 v_first:=public.community_activity();
 if jsonb_array_length(v_first->'events')<>0 or (v_first->>'cursor')::bigint<101 then raise exception 'FAIL: initial activity replayed history'; end if;
 v_page:=public.community_activity(0);
 if jsonb_array_length(v_page->'events')<>100 or v_page->>'cursor'=v_page->>'maxeligibleid' then raise exception 'FAIL: activity pagination skipped unseen records'; end if;
 if exists(select 1 from jsonb_array_elements(v_page->'events') e where e ? 'body' or e ? 'media_path') then raise exception 'FAIL: notification activity leaked message contents'; end if;
 v_second:=public.community_activity((v_page->>'cursor')::bigint);
 if jsonb_array_length(v_second->'events')<>2 then raise exception 'FAIL: next activity page missing or includes own messages'; end if;
 perform public.community_block_user('0c600000-0000-4000-8000-000000000002');
 if not exists(select 1 from jsonb_array_elements(public.community_list_blocks()) b where b->>'user_id'='0c600000-0000-4000-8000-000000000002') then raise exception 'FAIL: block list unavailable'; end if;
 if school_private.community_profile_access('0c600000-0000-4000-8000-000000000002') then raise exception 'FAIL: blocked cross-class DM profile remains available'; end if;
 if jsonb_array_length(public.community_activity(0)->'events')<>1 then raise exception 'FAIL: blocked sender still triggers notifications'; end if;
 begin perform public.community_send_message('0c610000-0000-4000-8000-000000000001','Blocked DM'); raise exception 'FAIL: blocker can send DM'; exception when insufficient_privilege then null; end;
 begin perform public.community_request_room('group','Blocked group',array['0c600000-0000-4000-8000-000000000002','0c600000-0000-4000-8000-000000000003']::uuid[]); raise exception 'FAIL: blocked pair can form group'; exception when insufficient_privilege then null; end;
 perform public.community_send_message('0c610000-0000-4000-8000-000000000002','Existing shared group remains available');
 if jsonb_array_length(public.community_messages('0c610000-0000-4000-8000-000000000001'))<1 then raise exception 'FAIL: block removed reportable DM history'; end if;
end $$;
select set_config('request.jwt.claim.sub','0c600000-0000-4000-8000-000000000002',true);
do $$ begin
 begin perform public.community_send_message('0c610000-0000-4000-8000-000000000001','Blocked other direction'); raise exception 'FAIL: blocked recipient can send DM'; exception when insufficient_privilege then null; end;
 begin perform public.community_request_friend('0c600000-0000-4000-8000-000000000001'); raise exception 'FAIL: blocked recipient can request friend'; exception when insufficient_privilege then null; end;
 if jsonb_array_length(public.community_list_blocks())<>0 then raise exception 'FAIL: another users blocks leaked'; end if;
end $$;
select set_config('request.jwt.claim.sub','0c600000-0000-4000-8000-000000000019',true);
do $$ begin
 begin perform public.community_review_room('0c610000-0000-4000-8000-000000000003',true); raise exception 'FAIL: leadership approved blocked pair'; exception when insufficient_privilege then null; end;
 if jsonb_array_length(public.community_activity(0)->'events')<>0 then raise exception 'FAIL: Developer receives unrelated DM/group activity'; end if;
end $$;
select set_config('request.jwt.claim.sub','0c600000-0000-4000-8000-000000000001',true);
select public.community_unblock_user('0c600000-0000-4000-8000-000000000002');
do $$ begin
 if jsonb_array_length(public.community_list_friends())<>0 then raise exception 'FAIL: unblock restored friendship automatically'; end if;
end $$;

select set_config('request.jwt.claim.sub','0c600000-0000-4000-8000-000000000003',true);
do $$ declare v_denied boolean:=false; begin
 for i in 4..13 loop perform public.community_request_friend(('0c600000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid); end loop;
 begin perform public.community_request_friend('0c600000-0000-4000-8000-000000000014'); exception when sqlstate 'P0001' then v_denied:=true; end;
 if not v_denied then raise exception 'FAIL: friend request rate limit missing'; end if;
 v_denied:=false;
 for i in 1..30 loop perform public.community_activity(); end loop;
 begin perform public.community_activity(); exception when sqlstate 'P0001' then v_denied:=true; end;
 if not v_denied then raise exception 'FAIL: notification activity rate limit missing'; end if;
end $$;
reset role;
rollback;
