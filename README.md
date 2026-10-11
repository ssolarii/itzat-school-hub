# Itzâ€™at School Hub

Desktop-first school schedules, calendar, approved notices and staff administration.

## Development

Node 24 and pnpm 10: `pnpm install`, `pnpm dev`, `pnpm test`, `pnpm build`.
Production output is `dist/`. The build generates a versioned offline shell, including local fonts. Routes use URL fragments and assets are relative for GitHub Pages.

## Access

Visitors choose Student, Teacher or Parent before navigation. A one-year, path-scoped SameSite cookie remembers presentation; it grants no permissions. Teachers sign in with a Supabase email/password account, confirm email, then request teaching-class access. Developer and Principal/Vice Principal accounts review private requests. Approval grants only the Teacher role and scoped notice-submission capability. Database RLS and checked RPCs enforce authorization.

Public configuration in `school-config.json` contains only the publishable key. Never put a service-role key or database password in this project.

## Deployment

GitHub Pages uses `.github/workflows/pages.yml`. Enable GitHub Actions as the Pages source. Supabase Auth Site URL and redirects must match the actual deployed Pages URL and any explicitly approved local preview URL.

Apply migrations in order, then seed only on a fresh database. Migration 002 installs private teacher account requests; migration 003 adds leadership-only verified applicant emails. Teacher assignments use immutable account IDs in the teacher field. Bootstrap the first Developer only after verifying their Auth account identity using the reviewed template. SQL authorization tests roll back their fixtures.

## School rules

Anchor: Tuesday 13 October 2026 is Day 6. Weekends and holidays pause the seven-day cycle; asynchronous and event days advance it. Day 7 has four student sessions and 12:20 dismissal. Regular dismissal 15:15; Quick Exit 14:10. Missing rooms and teacher assignments remain unassigned. Official Belize 2026 holidays are included; future government calendars require an approved import.

## Pending integrations

Teacher assignments, Classroom synchronization, student chat, notifications and Play Store packaging are future work. Migrations 001–003 are applied to the separate school project. The first verified Developer account is active. Staff authorization is covered by rollback-only database fixtures; ordinary teacher assignments await the school’s data.
