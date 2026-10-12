# Community backend

Apply `migrations/202610110004_community.sql` as one transaction after migrations 001–003. It creates the community tables, private storage bucket, rate limits and narrowly scoped RPCs. It does not assign any staff roles or publish student suggestions.

## Access rules

- A verified Supabase account is required for profiles, chat, private class polls, votes and likes. A browser role or class cookie has no authority.
- Students choose one active class in their server profile. Class chat membership follows that profile immediately. Changing class removes access to the previous class chat and its history. This is self-selection, not school verification of enrollment.
- Approved teachers see their assigned classes; Principal and Developer accounts can access class channels. No staff role gives automatic access to direct messages or group messages.
- Direct messages and group conversations require Principal or Developer approval. Reviewers see the title and participants. Only participants can read messages after approval.
- Signed-in users may discover display names and account IDs when requesting a conversation. Real names, bios, class details and profile images are limited to classmates, approved conversation participants and leadership. Names are supplied by users, not verified by the school.
- Class polls are published immediately to that class. Site suggestions require Developer approval. Approved site suggestions and Developer announcements are public, with student author identities omitted for visitors. Voting and liking are separate operations, with one vote and one like per account.
- Only Developer accounts approve custom emojis, approve site suggestions, set implementation decisions and publish Developer announcements. This stream is separate from ISA Updates.
- Developer moderation shows reported message snippets. It does not expose unreported DM archives. Removing a message preserves a visible moderation placeholder. Developers may pause another account's posting for up to 30 days. Every review and moderation action is written to the existing private audit log.

## Media

`community-media` is a private 5 MB-per-file bucket accepting JPEG, PNG, WebP and GIF. Uploads are limited to 10 per hour and 100 files per account. Media URLs expire after five minutes; do not persist them in browser storage or the offline cache. The API returns durable paths and signs them on demand. Referenced files cannot be silently overwritten or deleted by browser clients. A later retention job should remove unused uploads through an authorized server workflow.

GIF favorites live in local storage. A GIF sent to chat must either be an uploaded private file or a direct HTTPS `.gif` from `media.tenor.com`, `media.giphy.com` or `i.giphy.com`. Third-party GIF hosts still receive the viewer's IP address; use `referrerpolicy="no-referrer"` and avoid automatic previews before the user chooses a GIF. SVG, HTML and arbitrary media links are not accepted by chat.

## API shape

`createCommunityApi(existingSupabaseClient)` provides bounded RPC operations. Results use database `snake_case` fields; mutation arguments use the JavaScript `camelCase` fields in `src/community-api.js`. Both public and signed-in site feeds return `yes_count`, `no_count`, `like_count`, `my_vote` and `my_like`. A vote of `null` withdraws a vote. Liking takes an explicit boolean and cannot increment a counter repeatedly.

Messages return the most recent 100 rows ordered oldest to newest, and `messages(roomId, beforeId)` retrieves the preceding page. Room data includes its review status and participant account IDs. Empty data is returned as an empty array, not example messages.

## Delivery

The community UI should show a clear sign-in gate, email-verification gate, pending review status and offline status. Never persist private messages, profiles or signed media in local storage or the service worker. Automatic chat refresh may poll the RPC; Realtime is not enabled by this migration. A later Realtime rollout should preserve the same room authorization and review rules.

## Friends and activity (migration 005)

Apply `202610120005_friends.sql` after 004. Recipient-approved friendship grants mutual profile/media access across classes. Declined requests have a 24-hour cooldown, including removal/block/unblock attempts; requests are limited to 10 per hour. Removing friends revokes friendship access. Blocking prevents new private conversation requests/approval and DM sends; existing shared class/group history remains available. Unblocking does not restore friendship. Private DM/group review is still required.

Activity polling returns authorized room IDs, author IDs, timestamps and a cursor, never message text or media. Initial polling skips old messages. Later pages return at most 100 events and cannot exceed 30 activity reads per minute. The frontend polls every 12 seconds when Chat is open or alerts are enabled. Native desktop alerts are per-account opt-in and generic; closed-tab push and calls are not implemented.

Local checks passed: 119 frontend/unit/read-only integration tests, PGlite migrations 001–005 and rollback access/rate-limit fixtures, mocked Storage policies. Real authenticated production storage and community behavior remain unverified until migration approval/application.
