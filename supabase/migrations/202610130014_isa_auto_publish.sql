begin;
alter table school_private.isa_sync_config add column auto_publish boolean not null default false;
drop function public.configure_isa_sync(text,text);
create function public.configure_isa_sync(p_course text,p_token text,p_auto_publish boolean default false) returns void language plpgsql security definer set search_path='' as $$
begin
 if not school_private.community_developer() then raise exception 'Developer access required' using errcode='42501'; end if;
 if p_course is null or p_course !~ '^[0-9]{1,32}$' or p_auto_publish is null or p_token is null or length(p_token) not between 32 and 256 then raise exception 'Use a numeric course ID and a long random sync token' using errcode='22023'; end if;
 insert into school_private.isa_sync_config(id,course_id,token_hash,owner_id,auto_publish) values(true,p_course,sha256(convert_to(p_token,'UTF8')),auth.uid(),p_auto_publish) on conflict(id) do update set course_id=excluded.course_id,token_hash=excluded.token_hash,owner_id=excluded.owner_id,enabled=true,auto_publish=excluded.auto_publish,updated_at=now();
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'isa.sync.configure',jsonb_build_object('courseId',p_course,'autoPublish',p_auto_publish));
end; $$;
create or replace function public.import_isa_updates(p_token text,p_course text,p_items jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_config school_private.isa_sync_config; v_item jsonb; v_old school_private.isa_imports;
 v_updated timestamptz; v_notice uuid; v_draft uuid; v_document jsonb; v_payload jsonb; v_count integer:=0; v_public_count integer:=0; v_notices jsonb;
begin
 select * into v_config from school_private.isa_sync_config where id and enabled and course_id=p_course;
 if not found or p_token is null or length(p_token) not between 32 and 256 or v_config.token_hash is distinct from sha256(convert_to(p_token,'UTF8')) or not exists(select 1 from public.school_members where user_id=v_config.owner_id and active and role='developer') then raise exception 'Sync authorization failed' using errcode='42501'; end if;
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 50 then raise exception 'Send 1 to 50 announcements' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('isa.sync:'||p_course,0));
 if v_config.auto_publish then perform pg_advisory_xact_lock(742617092); end if;
 select document into v_document from public.school_versions order by revision desc limit 1;
 for v_item in select value from jsonb_array_elements(p_items) loop
  perform school_private.assert_keys(v_item,array['id','updated_at','title','body'],'ISA import');
  if v_item->>'id' is null or length(v_item->>'id') not between 1 and 100 or v_item->>'updated_at' is null then raise exception 'Source ID and update time required' using errcode='22023'; end if;
  v_updated:=(v_item->>'updated_at')::timestamptz;
  select * into v_old from school_private.isa_imports where course_id=p_course and post_id=v_item->>'id' for update;
  if found and v_old.source_updated_at>=v_updated then continue; end if;
  v_notice:=coalesce(v_old.notice_id,gen_random_uuid());
  v_payload:=jsonb_build_object('id',v_notice::text,'title',v_item->>'title','body',v_item->>'body','audience','school','approved',true,'publishedAt',v_updated);
  perform school_private.validate_notice(v_payload,v_document->'groups');
  v_draft:=null;
  if v_config.auto_publish then
   select coalesce(jsonb_agg(n),'[]') into v_notices from jsonb_array_elements(v_document->'announcements') n where n->>'id' is distinct from v_notice::text;
   v_document:=jsonb_set(v_document,'{announcements}',v_notices||jsonb_build_array(v_payload));
   v_public_count:=v_public_count+1;
   -- Previously pending revisions are superseded, not left as duplicate approvals.
   if v_old.draft_id is not null then update public.school_notice_drafts set status='approved',reviewed_by=v_config.owner_id,reviewed_at=now() where id=v_old.draft_id and status='pending'; end if;
  else
  v_draft:=null;
  if v_old.draft_id is not null then select id into v_draft from public.school_notice_drafts where id=v_old.draft_id and status='pending' for update; end if;
  if v_draft is null then
   v_draft:=gen_random_uuid();insert into public.school_notice_drafts(id,submitted_by,notice) values(v_draft,v_config.owner_id,v_payload);
  else update public.school_notice_drafts set notice=v_payload where id=v_draft; end if;
  end if;
  insert into school_private.isa_imports(course_id,post_id,source_updated_at,notice_id,draft_id) values(p_course,v_item->>'id',v_updated,v_notice,v_draft)
  on conflict(course_id,post_id) do update set source_updated_at=excluded.source_updated_at,draft_id=excluded.draft_id,imported_at=now();
  v_count:=v_count+1;
 end loop;
 if v_public_count>0 then
  perform school_private.validate_school_document(v_document);
  insert into public.school_versions(document,published_by) values(v_document,v_config.owner_id);
 end if;
 insert into public.school_audit_events(actor,action,details) values(v_config.owner_id,'isa.sync.import',jsonb_build_object('courseId',p_course,'imported',v_count,'published',v_public_count));
 return jsonb_build_object('imported',v_count,'published',v_public_count);
end; $$;
revoke all on function public.configure_isa_sync(text,text,boolean) from public,anon;
grant execute on function public.configure_isa_sync(text,text,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
