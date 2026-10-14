begin;
create table school_private.isa_sync_config (
 id boolean primary key default true check(id), course_id text not null,
 token_hash bytea not null, owner_id uuid not null references auth.users(id),
 enabled boolean not null default true, updated_at timestamptz not null default now()
);
create table school_private.isa_imports (
 course_id text not null, post_id text not null, source_updated_at timestamptz not null,
 notice_id uuid not null default gen_random_uuid(), draft_id uuid references public.school_notice_drafts(id),
 imported_at timestamptz not null default now(), primary key(course_id,post_id)
);
alter table school_private.isa_sync_config enable row level security;
alter table school_private.isa_imports enable row level security;
revoke all on school_private.isa_sync_config,school_private.isa_imports from public,anon,authenticated;
create function public.configure_isa_sync(p_course text,p_token text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not school_private.community_developer() then raise exception 'Developer access required' using errcode='42501'; end if;
 if p_course is null or p_course !~ '^[0-9]{1,32}$' or p_token is null or length(p_token) not between 32 and 256 then raise exception 'Use a numeric course ID and a long random sync token' using errcode='22023'; end if;
 insert into school_private.isa_sync_config(id,course_id,token_hash,owner_id) values(true,p_course,sha256(convert_to(p_token,'UTF8')),auth.uid()) on conflict(id) do update set course_id=excluded.course_id,token_hash=excluded.token_hash,owner_id=excluded.owner_id,enabled=true,updated_at=now();
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'isa.sync.configure',jsonb_build_object('courseId',p_course));
end; $$;
create function public.disable_isa_sync() returns void language plpgsql security definer set search_path='' as $$
begin
 if not school_private.community_developer() then raise exception 'Developer access required' using errcode='42501'; end if;
 update school_private.isa_sync_config set enabled=false,updated_at=now() where id;
end; $$;
create function public.import_isa_updates(p_token text,p_course text,p_items jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_config school_private.isa_sync_config; v_item jsonb; v_old school_private.isa_imports;
 v_updated timestamptz; v_notice uuid; v_draft uuid; v_document jsonb; v_payload jsonb; v_count integer:=0;
begin
 select * into v_config from school_private.isa_sync_config where id and enabled and course_id=p_course;
 if not found or p_token is null or length(p_token) not between 32 and 256 or v_config.token_hash is distinct from sha256(convert_to(p_token,'UTF8')) or not exists(select 1 from public.school_members where user_id=v_config.owner_id and active and role='developer') then raise exception 'Sync authorization failed' using errcode='42501'; end if;
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 50 then raise exception 'Send 1 to 50 announcements' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('isa.sync:'||p_course,0));
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
  if v_old.draft_id is not null then select id into v_draft from public.school_notice_drafts where id=v_old.draft_id and status='pending' for update; end if;
  if v_draft is null then
   v_draft:=gen_random_uuid();insert into public.school_notice_drafts(id,submitted_by,notice) values(v_draft,v_config.owner_id,v_payload);
  else update public.school_notice_drafts set notice=v_payload where id=v_draft; end if;
  insert into school_private.isa_imports(course_id,post_id,source_updated_at,notice_id,draft_id) values(p_course,v_item->>'id',v_updated,v_notice,v_draft)
  on conflict(course_id,post_id) do update set source_updated_at=excluded.source_updated_at,draft_id=excluded.draft_id,imported_at=now();
  v_count:=v_count+1;
 end loop;
 insert into public.school_audit_events(actor,action,details) values(v_config.owner_id,'isa.sync.import',jsonb_build_object('courseId',p_course,'drafts',v_count));
 return jsonb_build_object('imported',v_count);
end; $$;
create or replace function public.approve_school_notice(p_id uuid,p_expected_revision bigint)
returns table(revision bigint,document jsonb,published_at timestamptz) language plpgsql security definer set search_path='' as $$
declare v_draft public.school_notice_drafts; v_document jsonb; v_notices jsonb;
begin
 if not school_private.has_capability('notices.publish') then raise exception 'Notice review permission required' using errcode='42501'; end if;
 select * into v_draft from public.school_notice_drafts where id=p_id for update;
 if v_draft.id is null or v_draft.status<>'pending' or not school_private.in_scope(v_draft.notice->>'audience') then raise exception 'Pending notice not found in assigned scope' using errcode='42501'; end if;
 select s.document into v_document from public.school_versions s order by s.revision desc limit 1;
 select coalesce(jsonb_agg(n),'[]') into v_notices from jsonb_array_elements(v_document->'announcements') n where n->>'id' is distinct from v_draft.notice->>'id';
 v_document:=jsonb_set(v_document,'{announcements}',v_notices||jsonb_build_array(v_draft.notice||jsonb_build_object('publishedAt',now())));
 return query select * from public.publish_school_document(v_document,p_expected_revision);
 update public.school_notice_drafts set status='approved',reviewed_at=now(),reviewed_by=auth.uid() where id=p_id;
end; $$;
revoke all on function public.configure_isa_sync(text,text),public.disable_isa_sync(),public.import_isa_updates(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.configure_isa_sync(text,text),public.disable_isa_sync() to authenticated;
grant execute on function public.import_isa_updates(text,text,jsonb) to anon;
notify pgrst,'reload schema';
commit;
