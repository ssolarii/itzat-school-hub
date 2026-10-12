# Chat and Q+A

## Product decisions

- Students select their own class on their account profile. The server stores membership; changing the schedule picker or browser cookie does not change private access.
- Each class has an automatic class conversation. Direct messages and group conversations start as requests and require staff review.
- Profiles support a real name, adjacent display name, photo, banner, biography, accent and optional gradient. Uploaded images may be GIFs.
- Custom emoji submissions require Developer review. Saved GIF choices remain in this browser's local storage.
- Class polls are account-only and class-private. Site suggestions require Developer approval before public display. Public readers may see approved suggestions and Developer Updates; voting, likes and submissions require a verified account.
- Yes/no votes and likes are distinct. Developer decisions and the affected Student, Teacher or Parent view are explicit fields.
- Developer Updates is a separate feed from ISA Updates. Nothing submitted here enters the public school timetable document.

## Composition

Keep the existing purple navigation rail, Helvetica Now, lavender workspace and orange exception states. Chat uses a compact conversation list and one primary message thread with its composer anchored below. Profile options belong behind Edit profile, with a preview next to the form on desktop. Q+A uses Class, Sitewide and Developer Updates tabs, readable list rows, and a selected detail panel. Pending review controls appear only for permitted staff.

No decorative statistics, invented messages, fabricated polls, or feature cards. Empty states name the next action. Guests see a sign-in gate for private conversations and class polls, while approved public suggestions remain available.

## Required states

Loading, no profile, no messages, pending conversation, rejected request, private access denied, offline read-only, failed upload, posting failure, submitting, successful submit, signed out and changed account. Keep drafts during incoming message refresh. Clear all private data when the account changes; never persist messages or member lists in local storage or the service worker.

## Access and media

Use PostgreSQL RLS plus verified-account RPCs. Reading a conversation requires active participation or the account's current class. Profile media uses a private Supabase bucket with bounded signed URLs. Image types and sizes are constrained; no HTML/SVG uploads. Real names are self-reported unless school staff later supply an identity source. Review does not grant staff roles.

## Dedicated Chat revision

Chat has a physical `chat.html` entry with a 56px space rail, 248px conversation list, and flexible message pane. Schedule banners, timetable header and footer stay outside this section. The account dock remains bottom left. Profile, members, media and settings appear in an on-demand panel. Friends use All/Pending/Add views and recipient consent across classes; DMs/groups retain leadership review. Alerts default off, use generic text and follow account changes. School groups authorized class channels; a public school general channel and calls remain proposals. Desktop evidence in `.qa/chat-desktop.png` uses synthetic layout examples, not real conversations.

## Schoolwide and profile revision

Schoolwide Chat adds categorized channels and a right-hand presence list grouped Developer, Teacher, Moderator, Student and Member. Only server authority sets those groups. Profile editing is a centered native dialog with identity/status and appearance tabs, a live safe Markdown/GIF preview, and account theme controls. First join requires an explicit profile-sharing explanation and permits Not now. Name colors preserve selected hues while adjusting for reading contrast; staff colors follow authority hierarchy. API and persistence remain separated from rendering.
