# Chat redesign research

Scope: desktop student chat in Itz'at Schedule Assistant, using current product documentation and the user's Discord screenshot. These findings concern layout and interaction patterns, not a claim about how often school users encounter them.

| Evidence | What it suggests for this app |
|---|---|
| [Discord Friends List 101](https://support.discord.com/hc/en-us/articles/217674288-Friends-List-101) separates accepted friends, pending requests and blocked users, and permits adding friends from a conversation profile. | A Friends area with requests, cross-class discovery and profile actions. Friendship requires the recipient's consent. |
| [Slack sidebar](https://slack.com/help/articles/212596808-Adjust-your-sidebar-preferences) groups channels and DMs in navigation sections. | Keep the class channel under School and personal conversations under Friends. Search the list without moving the message pane. |
| [Signal notification options](https://support.signal.org/hc/en-us/articles/360043273491-In-App-Notification-Options) allows controlling notification content. | Default to generic desktop alerts, with no message body or private conversation name. |
| The supplied screenshot has a narrow workspace rail, conversation list, large thread and bottom-left account controls. | Give Chat a full-height shell, separate from timetable banners/header/footer. Open profiles and utilities only when requested. |

## Decisions

Keep Helvetica Now and the school purple identity. Allocate 56 px to the space rail, about 248 px to conversations, and the remaining width to messages. Anchor the composer to the bottom of the message column and the user's profile to the bottom of the conversation column. No extra horizontal headings, timetable alerts, duplicated tabs, or permanent profile inspector.

School is an organizational space containing the user's permitted class channels; this does not create an unrestricted schoolwide discussion room. A shared general channel can be added after deciding its audience and moderation rules.

## Technical boundaries

[MDN notifications](https://developer.mozilla.org/en-US/docs/Web/API/Notifications_API) require HTTPS and a user gesture to request permission. Add an explicit opt-in control. Alerts work while the website is open, including when its tab is in the background. Closed-tab delivery needs a separate Push backend.

[WebRTC peer connections](https://webrtc.org/getting-started/peer-connections) require signaling and commonly TURN relays. Voice calling remains a proposal until hosting, call acceptance, blocking and moderation are specified. Do not add an inert call button.

Rate limits stay in PostgreSQL, so a client cannot bypass them. Bound messages, conversation creation, uploads, friend requests and notification reads independently. Existing private class and DM rules remain in force.

The production revision uses [Tabler SVG icons](https://docs.tabler.io/icons/static-files/svg) for profile symbols and [emoji-picker-element](https://github.com/nolanlawson/emoji-picker-element) for the searchable native emoji picker. Emoji data is served locally and picker code is loaded when needed. Messaging uses [Supabase Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes) behind the same room authorization policies as API reads.
