# School administration and audience planning

This plan extends the schedule concept without turning the student page into an admin dashboard. Public schedules and approved schoolwide notices remain usable without an account. Signing in unlocks the user's actual permissions; choosing Student, Teacher or Parent on the landing page changes navigation, never authorization.

## Audiences

| Audience | First screen | Main information | Appearance |
| --- | --- | --- | --- |
| Student | Current lesson and next lesson, or next school day | Selected class timetable, cycle picker, approved notices | Purple and orange with stable class palette variants |
| Teacher | Personal teaching day | Assigned lessons across class groups, rooms, substitutions, own-class notices | Mainly yellow |
| Parent | School and selected-class updates | Approved ISA Updates, expandable notices, dates and upcoming school events | Mainly gray |
| Staff administrator | Changes requiring attention | Schedule editing, exceptions, notices and permitted administrative work | Purple and orange workspace |

Teacher lessons require an explicit teacher-to-lesson assignment list. Subject and room alone cannot identify the teacher. Until that list is supplied, the teacher page displays an unassigned state. The parent calendar remains a pending input until the school calendar is supplied.

## Roles and proposed permissions

Use four role families with explicit permissions and class scopes. Principal and Vice Principal are separate account titles within the same role family. Developer and Codeveloper are roles in the application; neither needs a database service key in the browser.

| Capability | Developer | Principal or Vice Principal | Teacher | Admin or Codeveloper |
| --- | --- | --- | --- | --- |
| Invite admins and grant or revoke permissions | All | No by default | No | Only if explicitly delegated; cannot grant beyond their authority |
| Edit and publish school schedules | All | Yes | Scoped draft changes if granted | As delegated |
| Create or archive class groups | All | Yes | No | Only if expressly delegated |
| Add subjects and manage rooms | All | Yes | Request additions | As delegated |
| Add a substitute override | All | Publish | Draft/request for assigned classes by default | As delegated |
| Create holidays, day types and bell profiles | All | Yes | No | As delegated |
| Post ISA Updates schoolwide | All | Yes | Only if separately granted | As delegated |
| Post notices for assigned classes | All | Yes | Yes within assigned scope | As delegated |
| Set a schoolwide banner | All | Yes | No | As delegated |
| Moderate chat | All | Only with a moderation grant | Only with a moderation grant | Only with a moderation grant |
| Manage moderation permissions and filters | All | Only if delegated | No by default | As delegated |
| Review audit history | All | School administrative changes | Own changes | Granted areas |

These are proposed defaults. Teacher schedule publication and schoolwide announcement authority can be adjusted by the Developer. A user's job title must not silently grant all administrative permissions.

## Schedule and class management

Store year level and subclass separately from the display name. Existing groups are 1A, 1B, 2A, 2B, 2C, 3CS, 3EM, 3HST, 4CS, 4EM and 4HST. No 1C timetable was supplied. Permit new subclasses without hardcoding HST, CS or EM in the database.

Schedules have effective dates and immutable published versions. Administrators edit a draft, inspect affected dates and groups, then publish one coherent revision. Archiving a group removes it from current selectors while retaining historical schedules and notices. A preview should identify conflicts before publication: overlapping teacher assignments, reused rooms, missing subjects and invalid bell times. A blank room in an uploaded timetable remains unassigned rather than inferred from other rows.

## Substitute lessons

A substitution is an overlay on one dated lesson occurrence. It preserves the underlying rotating timetable. Choose the date, class, session or session span, replacement subject if needed, room, substitute teacher, and optional note. Set an expiry or date range explicitly. Preview the student and teacher result before publication.

The student sees a labeled Substitute flair, replacement room beneath the subject, and substitute teacher. Expanded details can show the original lesson and reason. The teacher agenda includes the assignment and any original assignment replaced. Reverting the overlay restores the base lesson without changing every future occurrence of that cycle day.

## Calendar and bells

Separate three dimensions so one setting cannot accidentally shift the cycle:

| Dimension | Examples | Effect |
| --- | --- | --- |
| Cycle advancement | Advances or pauses | Holidays and weekends pause; asynchronous days and parades advance |
| Attendance or arrangement | On campus, independent work, event, closed | Determines the student instructions and whether a class timer applies |
| Bell profile | Regular, Quick Exit, Half-day, custom | Determines lesson times, number of sessions and dismissal |

Day 7 has four student sessions and dismissal at **12:20 PM schoolwide**, as confirmed by the user; this supersedes the 12:05 text in lower-year images. PLC is staff planning. Quick Exit is six shortened sessions with dismissal at 2:10 PM. Changing a bell profile does not itself pause the cycle. Show the next several school dates in the publishing preview so an administrator can see the effect of a holiday or asynchronous date.

Public holiday imports enter a review queue before affecting the school calendar. Manual events have start and end dates, audience, cycle advancement and optional bell profile. Existing published schedules remain cached offline as a complete version with the calendar exceptions they depend on.

## Notices and banners

An announcement has title, body, author, audience, class scope or scopes, optional subject label, publish date, expiry and attachment/link fields. Teachers can select only assigned class scopes. Parent and student pages share approved public notices but present different levels of detail. ISA Updates imported by Apps Script should be deduplicated by source ID and retain source/edit timestamps. Only approved schoolwide copies become public; class assignments and private source content stay in Classroom.

A banner has an audience, start/end time, severity and optional link. Use one prominent active banner; ordinary notices belong below the schedule. Allow an administrator to preview long text and narrow screens before publishing. Expired banners disappear automatically.

## Accounts and chat planning

Email and Google are appropriate first sign-in options. Supabase also supports Discord OAuth, but provider sign-in alone does not prove school membership. Chat membership should require a verified class assignment or school invitation. [Supabase social login](https://supabase.com/docs/guides/auth/social-login).

Keep class channels and student-created groups private to authorized members. Plan member invitations, group ownership, reporting, blocking, rate limits, slow mode, message removal, timeouts, account chat suspension, and a staff moderation queue. Moderators act only within granted scopes. Log moderation actions with actor, reason, target, timestamp and duration. Show the affected student an understandable reason and an appeal/contact route. Renaming a display name should not rewrite historical authorship.

A cookie ban can provide a local deterrent, but clearing cookies or using another browser defeats it. It must not be presented as a reliable cross-account ban. Use server-side account restrictions, school membership checks and controlled invitations as the primary controls. Shared school computers also make device-wide bans prone to affecting other students. Cookies and storage are explicitly clearable browser data. [OWASP session guidance](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html).

Word filters should support review, blocked sends and timeouts as distinct outcomes. Start with moderator review and temporary measures; ambiguous keyword matches should not automatically produce permanent bans. Let authorized staff manage the list, inspect the matched rule and undo a mistaken action.

## Supabase model

Proposed tables: class_groups, subjects, rooms, people, teacher_assignments, schedule_versions, schedule_lessons, bell_profiles, bell_slots, calendar_dates, lesson_overrides, announcements, announcement_audiences, banners, role_assignments, permission_grants and audit_events. Chat adds channels, channel_members, messages, reports, moderation_actions and filter_rules. Model permission scope as school, selected classes or selected channels.

Enforce capabilities and membership in Row Level Security policies and privileged server operations. Hiding a button is presentation, not permission enforcement. Do not let clients assign themselves an admin role. Publish schedule/version/calendar data atomically so readers and offline caches cannot receive mismatched revisions. [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [role-based access guidance](https://supabase.com/docs/guides/api/custom-claims-and-role-based-access-control-rbac).

## Suggested delivery order

1. Student schedules, compact cycle picker, real bell profiles, exceptions, offline published snapshots and staff schedule publishing.
2. Announcements, class-specific audiences, banners, substitutions, granular roles and audit history.
3. Teacher assignments and yellow teacher view; gray parent view and supplied school calendar; role landing page.
4. Verified accounts, private chat and moderation tools after the schedule and permission foundations are stable.

## Outstanding inputs

A is confirmed as Assembly. Teacher identities and lesson assignments are not supplied. The school calendar is pending. Regular dismissal is provisionally 3:15 PM from the existing hub; confirm it before implementation. Some rooms are omitted from the uploaded schedules. Permission defaults and chat retention/reporting arrangements remain planning decisions.
