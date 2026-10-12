# Itz'at Schedule Assistant V5.7

Desktop-first school schedules, calendar, approved notices and staff administration.

## Development

Node 24 and pnpm 10: `pnpm install`, `pnpm dev`, `pnpm test`, `pnpm build`.
Production output is `dist/`. The build generates versioned offline shells for `index.html` (landing) and `schedule.html` (workspace), including local fonts. Workspace sections use URL fragments and assets are relative for GitHub Pages.

## Access

First visits use three role choices → Name and preferences → Account options. `isa_welcome` stores a greeting name, role, completion flag and parent interests in a scoped cookie; `isa_audience` remembers the selected view. Both are presentation preferences, never authorization claims. Returning visitors get a personal greeting. Settings is the role-switching entry point. Student/parent accounts use normal Supabase email/password authentication; approved class notices stay public and student questions are still planned. Parent preferences filter elective dates while keeping closures in the next seven days visible; early-dismissal reminders cover the next three weeks.

The landing page’s plain “Request an admin role” link starts a verified-account request. Its private note is marked as an admin request, never approved through the Teacher approval action. A Developer reviews the account and assigns permissions separately. No onboarding step grants staff rights.

Visitors choose Student, Teacher or Parent before navigation. A one-year, path-scoped SameSite cookie remembers presentation; it grants no permissions. Teachers sign in with a Supabase email/password account, confirm email, then request teaching-class access. Developer and Principal/Vice Principal accounts review private requests. Approval grants only the Teacher role and scoped notice-submission capability. Database RLS and checked RPCs enforce authorization.

Public configuration in `school-config.json` contains only the publishable key. Never put a service-role key or database password in this project.

## Deployment

GitHub Pages uses `.github/workflows/pages.yml`. Enable GitHub Actions as the Pages source. Supabase Auth Site URL and redirects must match the actual deployed Pages URL and any explicitly approved local preview URL.

Apply migrations in order, then seed only on a fresh database. Migration 002 installs private teacher account requests; migration 003 adds leadership-only verified applicant emails. Teacher assignments use immutable account IDs in the teacher field. Bootstrap the first Developer only after verifying their Auth account identity using the reviewed template. SQL authorization tests roll back their fixtures.

## School rules

Anchor: Tuesday 13 October 2026 is Day 6. Weekends and holidays pause the seven-day cycle; asynchronous and event days advance it. Day 7 has four student sessions and 12:20 dismissal. Regular dismissal 15:15; Quick Exit 14:10. Missing rooms and teacher assignments remain unassigned. Official Belize 2026 holidays are included; future government calendars require an approved import.

## Community

Chat, Q+A and account profiles use migrations `202610110004_community.sql` and `202610120005_friends.sql`; apply both before publishing the community frontend. See `supabase/community.md` for permissions and review flows. Chat messages, profiles and member lists stay out of the offline cache and browser storage. Saved GIFs, notification opt-in and the selected room ID are local preferences; message bodies and member lists are never stored locally.

Students select their class themselves. A verified account gets the corresponding class chat when its community profile is first saved. Private DM/group conversations require leadership review. Class polls are private to the class; approved site suggestions and Developer Updates are public. Votes and likes require verified accounts and are separate records. Custom emojis require Developer review.

Profiles accept JPG, PNG, WebP and GIF photos/banners up to 5 MB. Names are self-reported; this release does not verify school identity. Private media uses short-lived signed URLs. Uploaded GIFs up to 1 MB can be saved on this browser. Direct Tenor/Giphy GIF links are also supported.

Reports reveal the reported message to the Developer, not a private conversation's full archive. All ordinary private reads use current server-side class or conversation membership, never the schedule picker or greeting cookie.

## Pending integrations

Teacher assignments, Classroom synchronization, notifications and Play Store packaging are future work. Migrations 001–003 are applied to the separate school project. The first verified Developer account is active. Staff authorization is covered by rollback-only database fixtures; ordinary teacher assignments await the school’s data.

Chat opens at `chat.html#chat` in a separate full-height shell. School class channels and Friends/DMs have their own navigation. The profile dock stays at the bottom left. Desktop alerts are opt-in, generic, and available only while the site is open. Closed-tab push and voice/video calling are not implemented. See `chat-research.md` for source-backed layout decisions.

## Schoolwide space and profiles

Migration `202610120006_school_space.sql` follows community 004 and friends 005. It adds explicit schoolwide profile-sharing consent, General/Assignments/Announcements channels, actual heartbeat presence, scoped chat moderators, status emojis, cosmetic tags, readable name colors and account-saved Light/Dark/System themes. Staff roles remain derived from school memberships; self-assigned tags never authorize moderation. Profile edits and preferences save atomically. See `supabase/school-space.md`. Local examples in `.qa` use synthetic accounts/messages and are excluded from production builds.

## First-use guides and release state

Short browser-local guides appear once on first launch and on the first visit to Schedule, Calendar, ISA Updates, Chat, Q+A and Profile. Next, Back, Skip and Escape are supported. Replay guides from Settings. The guide completion keys contain no account data.

Community migrations 004–006 remain unapplied by user choice. This release keeps `communityEnabled: false` in `school-config.json`, showing a clear coming-soon screen for Chat, Q+A and Profiles and preventing their API writes. Set it to true only after approved database setup and live verification. Personal tags are Creative, Music, Gaming, Books, Sports, Night owl, Early bird and Pet lover, with up to four choices.
