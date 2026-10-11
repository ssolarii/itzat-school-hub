# School backend

The dedicated school project is configured at `https://rssshitgdspbqjtqxvmr.supabase.co`. This is a public project URL, not a credential. The original `scheduleassistant` project is separate.

Run `migrations/202610100001_school_backend.sql` in the **separate school project**, then generate and run `seed.sql`. The seed validates the canonical uploaded timetable document and skips insertion if any published version already exists.

For the already-seeded project, run the updated migration and then `import-holidays.sql` to add the verified 2026 government calendar in an atomic publication. It preserves existing calendar entries and skips publication if no calendar changes are needed. Fresh installations obtain the same dates directly from the regenerated seed. The validator also prevents archiving every class, so the public selector always has at least one active group.

```text
python supabase/generate_seed.py school-data.json
```

The browser uses the project URL and **publishable/anon key** only. Never embed a service-role key, database password, session token, or privileged credentials in the website. A signed-in account has no publishing permissions until membership is explicitly granted.

## Teacher password accounts and approval

After the base migration, install `migrations/202610100002_teacher_requests.sql`. Keep Supabase email confirmation enabled. Teachers create their account using Supabase Auth email/password signup, verify their email, and sign in with their password; the website never stores passwords in application tables. A verified account may request teacher access but remains an ordinary reader while pending.

The requester sees only their own private requests. Developer, Principal, and Vice Principal can review requests and approve explicit active class scopes. This bounded approval creates only `teacher` membership with `notices.submit`; it cannot grant leadership, schoolwide scope, general publishing, or moderation rights. The general staff grant API stays Developer-only. Existing privileged memberships cannot be replaced through teacher approval.

Client adapter methods: `requestTeacherAccess({name,groups,note})`, `reviewTeacherAccess({id,approve,groups})`, and `listTeacherRequests()`. The request record includes `id`, `user_id`, `name`, `requested_groups`, `note`, `status`, `approved_groups`, and review timestamps. Requesting or updating one pending request does not approve it. After confirmation and sign-in, show the request form or pending status according to the server response.

Run `tests/teacher-requests.sql` after both migrations to check trusted email verification, private reads, pending account isolation, reviewer permissions, bounded Principal approval, and class announcement scopes. Test data rolls back. Apply migrations in date order; replaying the base migration afterward requires replaying the teacher migration too so its account grant concurrency lock remains installed.

## Client API

- Read: `school_versions.select('revision,document,published_at').order('revision',{ascending:false}).limit(1)`.
- Membership: `rpc('get_my_school_membership')` returns the signed-in member or null.
- Publish: `rpc('publish_school_document',{p_document,p_expected_revision})`. Revision conflict is SQLSTATE `40001`; reload and review instead of silently overwriting. All edits publish one atomic new version.
- Teacher draft: `rpc('submit_school_notice',{p_notice:{title,body,audience,subject?,expiresAt?}})` returns a draft UUID. It does not publish. Teacher scopes must contain the selected group.
- Review: select `school_notice_drafts` (RLS filters records); `rpc('approve_school_notice',{p_id,p_expected_revision})` approves a pending permitted draft and creates a new public version atomically.
- Developer grants: `rpc('set_school_member',{p_user_id,p_role,p_capabilities,p_groups,p_active})`. Account must already exist in Supabase Auth. Developers cannot modify their own membership through this API.

Roles are `developer`, `principal` (principal or vice principal), `teacher`, `codeveloper`. Developer and principal have all publishing capabilities; only Developer can grant members. Codeveloper capabilities and scopes must be explicit. `groups:['*']` grants schoolwide scope for delegated operations; empty groups grant none. Teacher scope is explicit groups only and allowed capability is `notices.submit`.

Available delegated capabilities: `schedules.manage`, `classes.manage`, `subjects.manage`, `calendar.manage`, `substitutions.manage`, `notices.submit`, `notices.publish`, `banners.manage`. Creating/archiving groups additionally requires `classes.manage`. Private membership/audit records are never part of the public JSON. Teacher assignment identifiers are public display names, not auth identities.

## First Developer bootstrap

This is a trusted Dashboard SQL operation after the owner signs up through the website. Verify the exact account UUID in **Authentication → Users**. Do not guess an email or silently bootstrap an arbitrary account.

```sql
insert into public.school_members(user_id, role, capabilities, groups)
values ('REPLACE_WITH_VERIFIED_AUTH_USER_UUID'::uuid, 'developer', '{}', '{*}');
```

The placeholder is intentional. Authentication creation does not imply membership. Subsequent membership grants use the Developer API.

## Validation and security checks

Run `tests/authorization.sql` after seeding. It temporarily adds fictional test accounts, exercises anonymous and authenticated identities, validates membership isolation, teacher draft permissions, scoped approval, stale revision rejection, invalid bell times, all-class archive rejection, and bounded grants, then **rolls back every fixture and test publication**. A success result is emitted only if every assertion passes. Direct writes are denied to all browser roles; only permission-checked RPCs mutate data.

Security-definer functions have fixed empty search paths, fully qualified data references, explicit auth checks, and restricted execute grants. Helper validation and capability functions are outside the exposed API schema. RLS policies protect all public-schema tables. Public reads are granted only the schedule projection columns, excluding publisher auth UUIDs.

Primary references: [Supabase database functions](https://supabase.com/docs/guides/database/functions), [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).
