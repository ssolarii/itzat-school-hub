# Schoolwide space (migration 006)

Migrations 004–008 are applied after user approval. The database enables private Storage, authorized message reads and Realtime, Developer-only admission, temporary one-use invites, recipient consent, optional Discovery and icon-based profile identity. No real account received a new staff role during activation.

## Data models and authorization

Profile columns hold status text, standard or approved custom emoji, up to four cosmetic interests, one personal tag, name color, private theme and schoolwide consent. Existing image paths remain private and signed. Status and name color respect existing profile access. Theme is returned only to its owner.

Joining schoolwide Chat shares the full profile with other joined members. The join dialog states this and allows Not now. Roles Creative, Science, Sports and Night owl are cosmetic. Trusted Developer/Teacher roles derive from active school memberships; only a Developer may appoint a school-space Moderator. Moderator capabilities are explicit manage_messages, upload_emojis and kick_members. Removal from schoolwide Chat does not remove staff access, class membership or private conversations. Staff cannot be kicked by Moderators.

Default channels are General, Assignments and Announcements. The Developer may create and edit channels, set a server name and description, and archive/restore channels without deleting history. Announcements require manage_messages. New school channels and media require verified accounts, explicit join consent and no school-space exclusion. Original student emoji requests continue to require Developer review; school-space emoji uploads require their scoped upload permission. New submissions return a pending_review flag; the existing database lifecycle uses pending/approved/rejected.

## API and state

createSchoolSpaceApi exposes getState, saveProfile, savePreferences, heartbeat, listMembers, assignModerator, kickMember, restoreMember, removeMessage and submitEmoji. saveProfile saves base identity and preferences in one transaction. Preference updates are patches; changing a theme cannot silently enroll someone or revoke existing join consent.

Realtime INSERT subscriptions are room-filtered and authorized with RLS. Events are hints: the client reloads message history through its authorized RPC. Periodic polling handles reconnects and removal placeholders. Deleted or removed message text is unavailable to direct readers. Presence uses heartbeats while the Chat page is visible, expires after 90 seconds, and is limited to six heartbeats per minute.

## UI and persistence

Profile editing uses a native modal dialog, Identity/Status and Appearance tabs, a safe Markdown preview and original GIF object URLs. No flattening, canvas conversion or raw HTML is used. Object URLs are revoked on replacement, close and account changes. Tab changes preserve file inputs; background updates preserve the draft. Uploads retain the existing 5 MB file limit. Local GIF favorites stay local; account themes, statuses and tags live in Supabase. Messages and member directories are never persisted in browser storage or the offline cache.

## Verification and activation

128 tests pass, including read-only production public timetable checks. PGlite migrations 001–006 and rollback privacy, rate-limit, permission and atomic-save fixtures pass, with mocked Storage schema checks. Native profile layout and live local form previews were reviewed in the browser using synthetic content. Production authenticated uploads, Realtime delivery and cross-device theme persistence require migration activation and live verification; they have not been claimed as tested.

## Production admission and consent (008)

Only active staff or admitted accounts can use private community services. Admission requests expose verified email identities to the Developer alone. Invitations expire after seven days and are stored only as hashes; raw codes are returned once. The Developer can later change `join_policy` to verified-account entry.

Accepted friends are added immediately to a new conversation. Other invited members cannot read or write until they accept. A declined DM is rejected; leaving a group removes access even for its creator. Channels use a stable posting policy independent of their editable name. Archives retain history and can be restored. Profile status supports Unicode emoji, approved uploaded emoji or a curated icon, one at a time. Badge feature selection validates an active award; revoking an award clears its featured status.
