# Schoolwide space (migration 006)

Current decision: keep this revision local. Apply only after future approval, following migrations 004 and 005. No real account receives a new staff or Moderator role from this migration.

## Data models and authorization

Profile columns hold status text, standard or approved custom emoji, cosmetic tags, name color, private theme and schoolwide consent. Existing image paths remain private and signed. Status and name color respect existing profile access. Theme is returned only to its owner.

Joining schoolwide Chat shares the full profile with other joined members. The join dialog states this and allows Not now. Roles Creative, Science, Sports and Night owl are cosmetic. Trusted Developer/Teacher roles derive from active school memberships; only a Developer may appoint a school-space Moderator. Moderator capabilities are explicit manage_messages, upload_emojis and kick_members. Removal from schoolwide Chat does not remove staff access, class membership or private conversations. Staff cannot be kicked by Moderators.

Channels are General, Assignments and Announcements. Announcements require manage_messages. New school channels and media require verified accounts, explicit join consent and no school-space exclusion. Original student emoji requests continue to require Developer review; school-space emoji uploads require their scoped upload permission. New submissions return a pending_review flag; the existing database lifecycle uses pending/approved/rejected.

## API and state

createSchoolSpaceApi exposes getState, saveProfile, savePreferences, heartbeat, listMembers, assignModerator, kickMember, restoreMember, removeMessage and submitEmoji. saveProfile saves base identity and preferences in one transaction. Preference updates are patches; changing a theme cannot silently enroll someone or revoke existing join consent.

Realtime INSERT subscriptions are room-filtered and authorized with RLS. Events are hints: the client reloads message history through its authorized RPC. Periodic polling handles reconnects and removal placeholders. Deleted or removed message text is unavailable to direct readers. Presence uses heartbeats while the Chat page is visible, expires after 90 seconds, and is limited to six heartbeats per minute.

## UI and persistence

Profile editing uses a native modal dialog, Identity/Status and Appearance tabs, a safe Markdown preview and original GIF object URLs. No flattening, canvas conversion or raw HTML is used. Object URLs are revoked on replacement, close and account changes. Tab changes preserve file inputs; background updates preserve the draft. Uploads retain the existing 5 MB file limit. Local GIF favorites stay local; account themes, statuses and tags live in Supabase. Messages and member directories are never persisted in browser storage or the offline cache.

## Verification and activation

128 tests pass, including read-only production public timetable checks. PGlite migrations 001–006 and rollback privacy, rate-limit, permission and atomic-save fixtures pass, with mocked Storage schema checks. Native profile layout and live local form previews were reviewed in the browser using synthetic content. Production authenticated uploads, Realtime delivery and cross-device theme persistence require migration activation and live verification; they have not been claimed as tested.
