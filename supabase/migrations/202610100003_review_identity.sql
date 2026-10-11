-- Leadership sees the email verified by Auth, never a claimant-supplied email.
-- Applicants continue to read only their own request through the existing RLS.
begin;
create or replace function public.list_teacher_requests_for_review()
returns table(id uuid,user_id uuid,name text,requested_groups text[],note text,status text,approved_groups text[],created_at timestamptz,updated_at timestamptz,reviewed_at timestamptz,email text,email_verified boolean)
language plpgsql stable security definer set search_path='' as $$
begin
  if not school_private.is_leadership() then
    raise exception 'Only school leadership may review verified applicant identities' using errcode='42501';
  end if;
  return query select r.id,r.user_id,r.name,r.requested_groups,r.note,r.status,r.approved_groups,r.created_at,r.updated_at,r.reviewed_at,u.email::text,(u.email_confirmed_at is not null)
    from public.school_teacher_requests r join auth.users u on u.id=r.user_id order by r.created_at desc;
end; $$;
revoke all on function public.list_teacher_requests_for_review() from public,anon,authenticated;
grant execute on function public.list_teacher_requests_for_review() to authenticated;
commit;
