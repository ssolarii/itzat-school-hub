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

Helvetica Now Display: titles, subject codes, countdown, forms, reading and navigation. Use the supplied local WOFF2 files, included in the offline cache.

## Desktop measurements

Target widths: 1024, 1280 and 1440 px. Student rail 190 px, reducing to 158 px in the compact desktop composition; admin rail about 198 px. Main padding 22–30 px. Current strip about 147–170 px high. Daily rows at least 79 px. Subject codes 23 px; room labels 15 px; title 30–32 px; current code 35 px; countdown 37 px. Values are provisional and should follow the final rendered composition.

Use 8 px control corners, 12 px current-panel corners and a single soft outer shadow. Row dividers carry structure. Avoid repeated shadows, decorative gradients, invented dashboard metrics, unnecessary eyebrows and excess navigation.

## Interaction and state

Keep Today, Next school day and Week local to the schedule. The rail contains Schedule, Cycle calendar and ISA Updates. One cycle dropdown selects one repeating day; label it Viewing Day X so it cannot be mistaken for live context. Class identity is always textual; stable purple/orange variants support it.

Use Lucide icons with visible labels. Subject icons are 28 px, current-subject icons 34 px. Preserve keyboard focus and native controls. Full names are supplementary reveals; the code and room remain visible. Respect reduced motion; transitions follow user actions rather than automatic page entrances.

## V5.7 compact layout

The approved V5.7 composition supersedes the provisional measurements above. Use a 168 px desktop rail, 80 px header, 110 px live strip, and 56 px timetable rows. Place the timetable beside ISA Updates. Adjacent matching periods share one row, retaining their individual timing and intervening breaks. Hide ordinary room labels by default; always show a changed substitute room. Expand subject names when the timetable has sufficient width.

The landing page contains three horizontal role choices on desktop, without a progress bar or feature overview. Landing and workspace have separate physical URLs. At 760 px and below, use the optimized single-column schedule, 58 px rows, bottom navigation, and collapsed earlier lessons. Settings retains room visibility and view changes. Mobile web is included in V5.7; native app packaging remains future work.

## Chat community

Chat is a separate, full-height application connected to Schedule Assistant. Use a compact space rail, conversation or channel list, central message thread and optional member/profile panel. Keep the schedule’s primary navigation out of the chat shell. Server name and description sit above channel groups; channel descriptions appear with their title. A Developer can reach server settings from the server name, create channels from each category, and edit channel details in the right panel. Archiving is reversible and keeps history.

Profile customization follows the uploaded reference: a narrow left section rail, a live profile card in the center, and focused controls on the right. The panel covers identity, personal tag, photo/banner, colors, status and interests. Personal tags remain self-selected and cosmetic; Developer-awarded badges are visibly distinct. Status accepts any pasted emoji or approved custom emoji. User-selected accent gradients belong to profile personalization only. The existing Helvetica Now and purple/orange identity remain. At 760 px, the editor becomes one column and message moderation targets are at least 44 px high.

Chat navigation now has distinct Schoolwide, DMs, Classes, and Friends/Discovery entries. Use the official square school logo in the rail. All controls use their actual registered Lucide icon; profile symbols come from a curated Tabler SVG catalog. Profile interests and badge collections stay out of message bylines and member rows. One featured badge may sit beside a name. The native emoji picker is searchable and uses local data. Server settings retain the same compact panel style with icon/image customization and a stable posting-permission control.
