-- Run only in the trusted Dashboard SQL editor after verifying the owner's
-- exact Authentication → Users UUID. This placeholder intentionally fails.
-- Never grant an account based on an unverified or guessed email address.
begin;
insert into public.school_members(user_id,role,capabilities,groups,active)
values ('REPLACE_WITH_VERIFIED_AUTH_USER_UUID'::uuid,'developer','{}','{*}',true);
insert into public.school_audit_events(action,details)
values ('member.bootstrap',jsonb_build_object('userId','REPLACE_WITH_VERIFIED_AUTH_USER_UUID'));
commit;
