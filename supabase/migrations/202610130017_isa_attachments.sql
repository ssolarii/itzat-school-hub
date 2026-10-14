begin;
alter table school_private.isa_imports add column content_hash bytea;
create or replace function school_private.validate_notice(p_notice jsonb, p_groups jsonb)
returns void language plpgsql immutable set search_path = '' as $$
declare v_attachment jsonb;
begin
  perform school_private.assert_keys(p_notice, array['id','title','body','audience','subject','publishedAt','expiresAt','approved','classroomUrl','attachments'], 'Notice');
  if coalesce(length(p_notice->>'id'),0) = 0 or coalesce(length(trim(p_notice->>'title')),0) not between 1 and 160 or
    coalesce(length(trim(p_notice->>'body')),0) not between 1 and 10000 or
    not coalesce((p_notice->>'audience' = 'school' or p_groups ? (p_notice->>'audience')),false) or
    p_notice->'approved' is distinct from 'true'::jsonb or p_notice->>'publishedAt' is null then
    raise exception 'Notice requires ID, title, body, valid audience, approval and publication time' using errcode = '22023';
  end if;
  perform (p_notice->>'publishedAt')::timestamptz;
  if p_notice->>'expiresAt' is not null and (p_notice->>'expiresAt')::timestamptz <= (p_notice->>'publishedAt')::timestamptz then
    raise exception 'Notice expiry must follow publication' using errcode = '22023';
  end if;
  if coalesce(p_notice->>'classroomUrl','')<>'' and p_notice->>'classroomUrl' !~ '^https://classroom[.]google[.]com/' then raise exception 'Invalid Classroom link' using errcode='22023'; end if;
  if p_notice ? 'attachments' then
    if jsonb_typeof(p_notice->'attachments') is distinct from 'array' or jsonb_array_length(p_notice->'attachments')>20 then raise exception 'Invalid attachments' using errcode='22023'; end if;
    for v_attachment in select value from jsonb_array_elements(p_notice->'attachments') loop
      perform school_private.assert_keys(v_attachment,array['title','url','imageUrl','kind'],'Attachment');
      if coalesce(length(v_attachment->>'title'),0) not between 1 and 200 or coalesce(v_attachment->>'url','') !~ '^https://' or length(v_attachment->>'url')>4096 or coalesce(v_attachment->>'kind','') not in ('file','video','link') then raise exception 'Invalid attachment link' using errcode='22023'; end if;
      if coalesce(v_attachment->>'imageUrl','')<>'' and (v_attachment->>'imageUrl' !~ '^https://' or length(v_attachment->>'imageUrl')>4096) then raise exception 'Invalid image link' using errcode='22023'; end if;
    end loop;
  end if;
end; $$;

create or replace function public.import_isa_updates(p_token text,p_course text,p_items jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_config school_private.isa_sync_config; v_item jsonb; v_old school_private.isa_imports;
 v_updated timestamptz; v_notice uuid; v_draft uuid; v_document jsonb; v_payload jsonb; v_count integer:=0; v_public_count integer:=0; v_notices jsonb; v_hash bytea;
begin
 select * into v_config from school_private.isa_sync_config where id and enabled and course_id=p_course;
 if not found or p_token is null or length(p_token) not between 32 and 256 or v_config.token_hash is distinct from sha256(convert_to(p_token,'UTF8')) or not exists(select 1 from public.school_members where user_id=v_config.owner_id and active and role='developer') then raise exception 'Sync authorization failed' using errcode='42501'; end if;
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 50 then raise exception 'Send 1 to 50 announcements' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('isa.sync:'||p_course,0));
 if v_config.auto_publish then perform pg_advisory_xact_lock(742617092); end if;
 select document into v_document from public.school_versions order by revision desc limit 1;
 for v_item in select value from jsonb_array_elements(p_items) loop
  perform school_private.assert_keys(v_item,array['id','updated_at','title','body','classroomUrl','attachments'],'ISA import');
  if v_item->>'id' is null or length(v_item->>'id') not between 1 and 100 or v_item->>'updated_at' is null then raise exception 'Source ID and update time required' using errcode='22023'; end if;
  v_updated:=(v_item->>'updated_at')::timestamptz;
  v_hash:=sha256(convert_to(((v_item-'updated_at'-'attachments') || jsonb_build_object('attachments',(select coalesce(jsonb_agg(a-'imageUrl'),'[]'::jsonb) from jsonb_array_elements(coalesce(v_item->'attachments','[]'::jsonb)) a)))::text,'UTF8')); 
  select * into v_old from school_private.isa_imports where course_id=p_course and post_id=v_item->>'id' for update;
  if found and (v_old.source_updated_at>v_updated or (v_old.source_updated_at=v_updated and v_old.content_hash=v_hash)) then continue; end if;
  v_notice:=coalesce(v_old.notice_id,gen_random_uuid());
  v_payload:=jsonb_build_object('id',v_notice::text,'title',v_item->>'title','body',v_item->>'body','audience','school','approved',true,'publishedAt',v_updated,'classroomUrl',coalesce(v_item->>'classroomUrl',''),'attachments',coalesce(v_item->'attachments','[]'::jsonb));
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
  insert into school_private.isa_imports(course_id,post_id,source_updated_at,notice_id,draft_id,content_hash) values(p_course,v_item->>'id',v_updated,v_notice,v_draft,v_hash)
  on conflict(course_id,post_id) do update set source_updated_at=excluded.source_updated_at,draft_id=excluded.draft_id,content_hash=excluded.content_hash,imported_at=now();
  v_count:=v_count+1;
 end loop;
 if v_public_count>0 then
  perform school_private.validate_school_document(v_document);
  insert into public.school_versions(document,published_by) values(v_document,v_config.owner_id);
 end if;
 insert into public.school_audit_events(actor,action,details) values(v_config.owner_id,'isa.sync.import',jsonb_build_object('courseId',p_course,'imported',v_count,'published',v_public_count));
 return jsonb_build_object('imported',v_count,'published',v_public_count);
end; $$;
notify pgrst,'reload schema';
commit;
