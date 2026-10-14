begin;
create function public.complete_teacher_timetable(p_teacher uuid,p_path text,p_revision bigint) returns void language plpgsql security definer set search_path='' as $$
declare v_document jsonb;
begin
 if not school_private.is_leadership() then raise exception 'School leadership required' using errcode='42501'; end if;
 select document into v_document from public.school_versions where revision=p_revision;
 if v_document is null or not exists(select 1 from jsonb_array_elements(v_document->'teacherAssignments') a where a->>'teacher'=p_teacher::text) then raise exception 'Publish this teacher’s lessons first' using errcode='22023'; end if;
 update public.teacher_timetable_uploads set status='digitized',reviewed_at=now() where teacher_id=p_teacher and image_path=p_path;
 if not found then raise exception 'The teacher uploaded a newer image. Review it before marking complete' using errcode='40001'; end if;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'teacher.timetable.digitized',jsonb_build_object('teacher',p_teacher,'revision',p_revision));
end; $$;
revoke all on function public.complete_teacher_timetable(uuid,text,bigint) from public,anon,authenticated;
grant execute on function public.complete_teacher_timetable(uuid,text,bigint) to authenticated;
notify pgrst,'reload schema';
commit;
