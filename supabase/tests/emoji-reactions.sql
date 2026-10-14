begin;
insert into auth.users(id,email,email_confirmed_at) values('0c190000-0000-4000-8000-000000000001','emoji-test@example.invalid',now());
insert into public.community_profiles(user_id,real_name,audience,class_group,space_onboarded,cosmetic_roles) values('0c190000-0000-4000-8000-000000000001','Emoji Tester','student','3CS',true,'{gaming}');
insert into public.community_emojis(name,media_path,submitted_by,status) values('joeshrug','0c190000-0000-4000-8000-000000000001/emoji/shrug.gif','0c190000-0000-4000-8000-000000000001','approved'),('unreviewed','0c190000-0000-4000-8000-000000000001/emoji/pending.gif','0c190000-0000-4000-8000-000000000001','pending');
set local role authenticated;
select set_config('request.jwt.claim.sub','0c190000-0000-4000-8000-000000000001',true);
do $$ declare v_room uuid; v_message bigint; begin
 select (c->>'id')::uuid into v_room from jsonb_array_elements(public.school_space_get_state()->'channels') c where c->>'school_channel'='welcome';
 v_message:=public.community_send_message(v_room,'Emoji test');
 perform public.community_react_message(v_message,':joeshrug:',true);
 perform public.community_react_message(v_message,'❤️',true);
 if not exists(select 1 from public.community_message_reactions where message_id=v_message and emoji=':joeshrug:' and active) then raise exception 'Approved emoji reaction missing'; end if;
 begin perform public.community_react_message(v_message,':unreviewed:',true);raise exception 'Pending emoji allowed';exception when invalid_parameter_value then null;end;
 begin perform public.community_react_message(v_message,':unknown:',true);raise exception 'Unknown emoji allowed';exception when invalid_parameter_value then null;end;
 begin perform public.community_react_message(v_message,'plain text',true);raise exception 'Plain text reaction allowed';exception when invalid_parameter_value then null;end;
 perform public.community_react_message(v_message,':joeshrug:',false);
end $$;
reset role;
rollback;
