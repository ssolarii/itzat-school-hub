begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('0c980000-0000-4000-8000-000000000001','auto-student@example.invalid',now()),
 ('0c980000-0000-4000-8000-000000000002','auto-teacher@example.invalid',now()),
 ('0c980000-0000-4000-8000-000000000003','auto-dev@example.invalid',now());
insert into public.community_profiles(user_id,real_name,audience,class_group) values
 ('0c980000-0000-4000-8000-000000000001','New Student','student','3CS'),
 ('0c980000-0000-4000-8000-000000000002','Teacher','teacher',null),
 ('0c980000-0000-4000-8000-000000000003','Developer','student','3CS');
insert into public.school_members(user_id,role,groups) values
 ('0c980000-0000-4000-8000-000000000002','teacher','{3CS}'),
 ('0c980000-0000-4000-8000-000000000003','developer','{*}');
insert into storage.objects(bucket_id,name,owner_id) values
 ('community-media','0c980000-0000-4000-8000-000000000001/emoji/hello.gif','0c980000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','0c980000-0000-4000-8000-000000000001',true);
do $$ declare v_state jsonb; v_welcome uuid; begin
 v_state:=public.school_space_get_state();
 if not exists(select 1 from jsonb_array_elements(v_state->'channels') c where c->>'school_channel'='welcome') then raise exception 'Welcome channel missing'; end if;
 if not exists(select 1 from jsonb_array_elements(v_state->'members') m where m->>'user_id'='0c980000-0000-4000-8000-000000000001') then raise exception 'New student was not added automatically'; end if;
 if exists(select 1 from jsonb_array_elements(v_state->'members') m where m->>'user_id'='0c980000-0000-4000-8000-000000000002') then raise exception 'Teacher appeared in chat'; end if;
 select (c->>'id')::uuid into v_welcome from jsonb_array_elements(v_state->'channels') c where c->>'school_channel'='welcome';
 begin perform public.community_send_message(v_welcome,'Too early'); raise exception 'Student posted before choosing interests'; exception when insufficient_privilege then null; end;
 perform public.school_space_preferences('{"cosmetic_roles":["gaming"],"name_color":"#512393","space_onboarded":true}');
 perform public.community_send_message(v_welcome,'Hello from a new member');
 if public.school_space_submit_emoji('welcome_wave','0c980000-0000-4000-8000-000000000001/emoji/hello.gif')->>'pending_review'<>'true' then raise exception 'Emoji did not enter review'; end if;
end $$;
select set_config('request.jwt.claim.sub','0c980000-0000-4000-8000-000000000003',true);
do $$ begin
 if not exists(select 1 from jsonb_array_elements(public.community_list_emojis(true)) e where e->>'name'='welcome_wave') then raise exception 'Developer cannot review emoji'; end if;
end $$;
select set_config('request.jwt.claim.sub','0c980000-0000-4000-8000-000000000002',true);
do $$ begin
 if jsonb_array_length(public.school_space_get_state()->'channels')<>0 then raise exception 'Teacher gained chat access'; end if;
end $$;
reset role;
rollback;
