# Itz’at schoolwide website build plan

Build a desktop schedule tool around the approved purple and orange direction. Students should immediately see their current lesson and next destination. Administrative publishing should produce a coherent schedule revision that every reader can use, including a saved offline copy. The desktop concepts are the visual baseline; the operational decisions listed at the end remain inputs to implementation.

## Desktop screens

| View | Primary task | Composition |
|---|---|---|
| Student today | Identify now, room and next class | Purple rail, white header, horizontal current-class strip, daily agenda |
| Student after school | Prepare for the next school day | Next date and schedule first, expandable replay of today |
| Student weekend | Prepare for the next attending day | Next school day first, accessible week view including closures |
| Cycle calendar | Look up Day 1–7 | One dropdown, one labeled repeating timetable |
| Admin | Publish or review a change | Lavender rail, white forms, affected lesson/date preview |
| Teacher | Know which group to teach next | Yellow rail/header, assignment-driven agenda; unassigned until supplied |
| Parent | Read notices and future dates | Gray navigation, approved school/class notices, expandable calendar |
| Landing | Choose a useful view | Student, teacher and parent choices; optional sign-in |

The image guides layout, proportions and surfaces. Uploaded timetables supply the lessons and rooms. Keep additional chat, assignment and resource navigation out of the schedule release.

## Calendar and time model

Model each school date using three independent fields: cycle advancement, attendance arrangement and bell profile. A holiday pauses the cycle and has no lessons. An asynchronous date advances the cycle but presents independent work with no campus or live online classes. A parade advances the cycle and displays its published event arrangements. Quick Exit and Half-day change bells; they do not pause the cycle.

Use an administrator-confirmed date and cycle-day anchor, explicit term dates, and the America/Belize timezone. Resolve date overrides before deriving the rolling day. Proposed precedence: a confirmed closure wins over an asynchronous/event arrangement; conflicting arrangements require administrative review. Reject ambiguous unpublished combinations rather than silently guessing. Term reset/resume behavior still needs a school decision.

Day 7 always contains four student lessons, followed by dismissal at 12:20 PM. The last lesson ends at noon. Quick Exit lessons finish at 1:55 PM, dismissal at 2:10 PM. Show the interval between lessons ending and dismissal as dismissal preparation, rather than an active class. Regular dismissal is provisionally 3:15 PM and needs confirmation. Between periods, show the transition or break and the next class. Before school, show the first class and time to start.

Special bells and substitutions belong to dated occurrences. Changing one Friday must not change tomorrow, every cycle day, or a future week. Merged Super Teams/Seminar lessons use a start session and session span; the data contains Sessions 5–6 blocks. Staff PLC entries do not become student lessons.

## Publishing and permissions

Store drafts separately from immutable published schedule versions. Every version has effective dates, author and change history. Publication reviews affected groups and downstream dates, validates session spans and bell ordering, checks assigned teacher/room conflicts, and commits the complete revision. Use rollback through a new revision, retaining the previous history. Archived class groups disappear from new selections while historical records remain readable.

Supabase authorization must exist before the first administrative publish path. Public readers can read only published schedules and approved public notices. Authenticated writers receive explicit capabilities and scopes; browser role labels are presentation only. Use database policies and server-controlled grants. Never put privileged service credentials in the frontend.

Proposed defaults to confirm:

| Role | Schedule and calendar | Notices | Accounts and moderation |
|---|---|---|---|
| Developer | Full access | Full access | Grants administrators and scoped capabilities; full moderation control |
| Principal / Vice Principal | Publish schedules, manage dates and create/archive classes | Schoolwide and class notices | Account grants remain Developer-only unless explicitly delegated |
| Teacher | Assigned teaching view; substitute requests/drafts | Assigned class notices; schoolwide notices require a grant | Moderation only when separately granted |
| Admin / Codeveloper | Explicit delegated capabilities | Explicit delegated scopes | Grants cannot exceed delegated authority |

Teacher assignments determine the classes they can manage. Selecting Teacher on the landing page never grants an administrator role. Class membership for private features must be verified independently from a selected public timetable.

## Administrative workflows

Substitute: choose a dated occurrence, retain the base lesson, add replacement subject if needed, room, substitute teacher and optional note. Preview a labeled Substitute row for students and an assignment for staff. Apply only for its stated date/range; expiry and reversal are explicit.

Calendar: add a holiday or event, choose advancement/arrangement/bells and preview the resulting upcoming cycle. Government holiday imports enter a review queue. Administrators can add school closures in advance. Keep an edit history and show date impact before publication.

Announcements: title, body, author, school/class scope, optional subject label, publication date and expiry. Apps Script imports eligible ISA Updates posts as drafts using source IDs for deduplication. Only approved copies become public. Keep Classroom assignment/private source content within Classroom. A custom banner has audience, priority and expiry, with one prominent active banner to avoid crowding.

Directories: expandable year/subclass records rather than hardcoded subclass lists; create/archive groups, add subjects, manage rooms and assign teachers. The uploaded set has 11 groups; no 1C schedule has been supplied. Missing rooms stay explicitly unassigned.

## Offline and delivery

Cache one published snapshot containing timetable, calendar exceptions, bell profiles, subject definitions, substitutions and revision identity together. Calculate the visible day and countdown from that snapshot; show the last successful update and a clear stale/offline state. New announcements and schedule changes require connectivity. Administrative publication requires an online path initially. The present Offline preview is a design state, not a functioning cache.

Design desktop now. Mobile browser layouts, touch interactions and installation are later work. Publishing an Android app does not make an unfinished mobile layout usable; mobile acceptance is a separate milestone before distribution. Choose PWA/Android packaging and foreground versus background notifications during that phase. Class-ending reminders must respect notification consent, quiet hours and offline behavior.

## Build sequence

| Phase | Deliverable | Completion condition |
|---|---|---|
| 0 Planning | Desktop concepts, design tokens, calendar rules and permission matrix | Visual baseline recorded; required operational inputs resolved |
| 1 Publishing foundation | Supabase schema, auth/capabilities, scopes, calendar resolver, versioned schedules and audit events | Authorized editors can review and publish a coherent revision; readers see published data only |
| 2 Student desktop | Now/next, agenda, mode switching, 11 groups, cycle picker, week, offline snapshot | Schedules and all date/time states are correct; class changes are clear; cached revision is identifiable |
| 3 Admin operations | Substitutions, groups/subjects/rooms, holidays, bells, banners, notices and imports | Changes have explicit scope, expiry, review and rollback; imported notices require approval |
| 4 Teacher and parent | Teacher agenda, parent notices/calendar, role landing | Teacher assignments and school calendar supplied; audiences receive appropriate information |
| 5 Mobile and Android | Mobile layouts, PWA/install choices, notification strategy and Android distribution | Mobile flows are usable independently of store publication |
| 6 Optional social features | Verified class/group chat, reports, scoped moderation and filters | Membership, retention, appeals and moderation rules agreed before launch |

Polls remain optional. Chat should not delay the schedule release. Cookie bans are easily cleared and may affect shared devices; use verified membership, account restrictions and controlled invitations as the primary controls. Automatic filters should support review and temporary restrictions, with a clear reporting/appeal route.

## Inputs needed before implementation

Confirm the cycle anchor and term reset/resume rule; regular dismissal; school calendar; missing rooms; teacher identities and assignments; permission defaults; public-notice approvers; and precedence for conflicting date arrangements. Chat retention and reporting decisions are required only before its later phase. These inputs do not prevent review of the desktop visual concepts.

## Review findings incorporated

The visual review replaced the tall countdown layout with the image’s horizontal current-context strip, added the purple rail and enlarged subject icons. The functional review moved permissions and audit history into the first publishing phase, made special bells date-scoped, distinguished final lesson endings from dismissal, and preserved merged-session records. Visual and functional planning remain separate in DESIGN.md and this plan.

## Technical references

Implementation should use the official [Supabase row level security guidance](https://supabase.com/docs/guides/database/postgres/row-level-security), [custom claims and role based access control guidance](https://supabase.com/docs/guides/api/custom-claims-and-role-based-access-control-rbac), and [Google Classroom API documentation](https://developers.google.com/workspace/classroom). These are implementation references; the concepts have no connected backend.
