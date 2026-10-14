begin;
alter table public.school_teacher_requests add column approval_message text not null default '' check(length(approval_message)<=2000);
create function public.set_teacher_approval_message(p_id uuid,p_message text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not school_private.is_leadership() then raise exception 'School leadership required' using errcode='42501'; end if;
 if p_message is null or length(p_message)>2000 then raise exception 'Message must be at most 2000 characters' using errcode='22023'; end if;
 update public.school_teacher_requests set approval_message=trim(p_message),updated_at=now() where id=p_id and status='approved';
 if not found then raise exception 'Approved teacher request not found' using errcode='22023'; end if;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'teacher.approval.message',jsonb_build_object('requestId',p_id));
end; $$;
create function public.review_teacher_access(p_id uuid,p_approve boolean,p_groups text[],p_message text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;
begin
 if p_message is null or length(p_message)>2000 then raise exception 'Message must be at most 2000 characters' using errcode='22023'; end if;
 v_result:=public.review_teacher_access(p_id,p_approve,p_groups);
 if p_approve then perform public.set_teacher_approval_message(p_id,p_message); end if;
 return v_result;
end; $$;
revoke all on function public.set_teacher_approval_message(uuid,text),public.review_teacher_access(uuid,boolean,text[],text) from public,anon,authenticated;
grant execute on function public.set_teacher_approval_message(uuid,text),public.review_teacher_access(uuid,boolean,text[],text) to authenticated;
notify pgrst,'reload schema';
commit;
