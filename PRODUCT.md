# Itz’at school schedule

Students should identify their current class, room, remaining time and next class at a glance, then find the next school day or any cycle day with minimal interaction. The existing class hub supplies functional context; the user-selected generated image supplies the desktop visual direction.

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

Release the schedule and administrative publishing foundation first. Add notices, substitutions and scoped roles next, then assignment-driven teacher and parent views. Polls and chat are optional later work. Audience selection on the landing page changes presentation, not permissions.

See school-build-plan.md for the build sequence and open operational inputs. DESIGN.md records visual decisions separately.
