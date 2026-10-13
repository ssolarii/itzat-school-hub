# Itz’at Schedule Assistant and Community

Schedule Assistant pairs an at-a-glance school timetable with a separate community space for students to talk, share interests and work together. The chat space is configurable by the Developer and connects back to schedules, notices and account identity.

The first implementation targets desktop browsers. Mobile interaction design, PWA installation and Android delivery are later phases. Planning concepts contain authentic uploaded timetables and illustrative calendar dates and notices; they do not publish data.

## Confirmed product rules

- Seven rolling days; weekends and holidays pause the cycle. Asynchronous work days and parades advance it.
- Day 7 has four student lessons. Schoolwide dismissal is 12:20 PM. PLC is staff planning.
- Quick Exit uses six shortened sessions and dismissal at 2:10 PM.
- Short subject codes; full names appear on hover or keyboard focus, with a later touch equivalent. Room underneath. A means Assembly; FL&E means Financial Literacy & Education.
- All 11 uploaded class timetables are included. Missing rooms remain unassigned. No 1C timetable was uploaded.
- Approved schoolwide notices are public. Student schedule reading needs no sign-in.
- Teacher lessons remain unassigned until the teacher list and assignment mapping are supplied.
- Supabase will manage published schedules and administrative access; Classroom imports will use Apps Script and an approval step.

## Scope

The schedule remains the school operations surface. Chat is a separate connection platform with profiles, friends, conversations and Developer-managed schoolwide channels. Teacher and parent views, moderation, access requests and data publishing continue to use server-authorized roles. Audience selection changes presentation, not permissions.

## Community rules

- Members may choose up to four interests and one personal tag. Neither grants permissions.
- Award badges are issued by the Developer and displayed on member profiles and chat identity.
- Status supports any pasted Unicode emoji or an approved custom server emoji.
- The Developer may rename the server, edit its description, create and edit channels, and archive or restore channels. Archiving retains messages.
- Community database changes remain local until the user approves applying them to Supabase.

See school-build-plan.md for the build sequence and open operational inputs. DESIGN.md records visual decisions separately.

## Production chat decisions · 12 October 2026

Chat access begins with a one-use invite or Developer approval. The Developer alone manages this temporary policy. Verified active staff are eligible through their existing school membership. Students choose their own class. Friends can create DMs and groups immediately; non-friends must accept a message invitation, and all private room members may leave. Discovery requires explicit opt-in and matches shared interests without exposing email, activity or location. Profile interests and personal tags are visible on profile tap. Icon badges are shown on profiles, with one optional featured icon beside a name.
