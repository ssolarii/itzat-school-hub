# Itz’at desktop design

Provisional design system for the planning concepts. The user-selected generated board is the visual reference; its invented subjects, rooms, dates and navigation are excluded. This is a desktop Operate surface: reading a timetable and editing a dated lesson take priority.

## Visual hierarchy

Student: purple navigation rail, white application header, pale lavender workspace, horizontal current lesson strip, then a broad agenda. Subject, room, time remaining and next lesson are directly visible. The strongest visual accent belongs to current context.

Admin: lavender navigation rail, white workspace, clearly named work areas, restrained underlined task tabs and roomy forms. Review substitutions in a warm preview before publication. Teacher: yellow rail and header. Parent: gray rail and quiet notice/calendar hierarchy. Landing: distinct role choices inside the same school identity.

## Tokens

| Token | Light theme | Dark theme | Use |
|---|---|---|---|
| Brand | #512393 | #3C2261 | Student rail and current context |
| Purple text | #512393 | #CBB1F5 | Links and selected context |
| Orange | #FFAB44 | #FFB761 | Remaining time and exceptions |
| Canvas | #F7F4FD | #1D1728 | Student workspace |
| Agenda | #FFFFFF | #251D31 | Timetable rows and reading surfaces |
| Ink | #23103F | #F7F1FF | Primary content |
| Secondary ink | #6A5B7D | #C7BAD6 | Rooms, dates and supporting text |
| Lavender | #EBE3FC | #362747 | Current row and selected controls |
| Warm preview | #FFF4DF | #352918 | Substitutions and exceptions |
| Divider | #E8E1F0 | #42344F | Row boundaries |

Space Grotesk: titles, subject codes and countdown. DM Sans: forms, reading and navigation. Google Fonts are used in the concepts; the implementation should cache or self-host font files for offline use.

## Desktop measurements

Target widths: 1024, 1280 and 1440 px. Student rail 190 px, reducing to 158 px in the compact desktop composition; admin rail about 198 px. Main padding 22–30 px. Current strip about 147–170 px high. Daily rows at least 79 px. Subject codes 23 px; room labels 15 px; title 30–32 px; current code 35 px; countdown 37 px. Values are provisional and should follow the final rendered composition.

Use 8 px control corners, 12 px current-panel corners and a single soft outer shadow. Row dividers carry structure. Avoid repeated shadows, decorative gradients, invented dashboard metrics, unnecessary eyebrows and excess navigation.

## Interaction and state

Keep Today, Next school day and Week local to the schedule. The rail contains Schedule, Cycle calendar and ISA Updates. One cycle dropdown selects one repeating day; label it Viewing Day X so it cannot be mistaken for live context. Class identity is always textual; stable purple/orange variants support it.

Use Lucide icons with visible labels. Subject icons are 28 px, current-subject icons 34 px. Preserve keyboard focus and native controls. Full names are supplementary reveals; the code and room remain visible. Respect reduced motion; transitions follow user actions rather than automatic page entrances.

Desktop design is the current deliverable. Existing narrow-screen fallback is provisional, and mobile is not part of this design acceptance.
