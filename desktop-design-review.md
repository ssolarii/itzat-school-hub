# Desktop concept review

Scope: revised HTML concepts and final planning documents. The student composition and administrative flows received subagent source review and a bounded desktop browser inspection. Mobile acceptance, production authorization and backend behavior are outside this concept review.

## What works

- The purple navigation rail and horizontal current-context strip now follow the selected image while retaining real timetable data.
- Subject icons, codes and rooms form a consistent row structure; essential information stays visible without opening a menu.
- Viewing Day X separates a cycle lookup from live Today context.
- The admin substitute preview makes the changed room, subject and teacher visible before publication.
- The yellow teacher view accurately shows unassigned lessons, and the gray parent view does not invent an uploaded school calendar.

## Findings and disposition

| Priority | Finding | Disposition |
|---|---|---|
| P1 | Old tall current panel did not match the selected image | Replaced with a horizontal strip and purple rail |
| P1 | Global special bells affected subsequent dates | Scoped demo bells to Friday; future/cycle views use their defaults |
| P1 | Permissions and audit history followed publishing in the older sequence | Moved into the publishing foundation |
| P2 | Host icon styles rendered requested subject icons at 16 px | Explicit subject sizing restored to 28 px and current subject to 34 px |
| P2 | Replay Friday omitted the dated bell profile | Corrected to retain Friday bells |
| P3 | Tomorrow and cycle data still follow Today vertically | Retained to support the user's scroll-to-see requirement; labeled as secondary context |

The static Impeccable scan reported no findings on the two revised HTML sources. This is not a complete accessibility or production release certification. Browser inspection demonstrated the desktop composition, dated Quick Exit/Day 7 displays, substitution review and scoped permission preview. Current concepts remain local demonstrations.

## Handoff

DESIGN.md is the provisional desktop design system. school-build-plan.md contains the implementation sequence and unresolved operational inputs. Schedule data remains in schoolwide-schedules.json. Teacher assignments, the school calendar, anchor date, regular dismissal and permission defaults need resolution during implementation planning.
