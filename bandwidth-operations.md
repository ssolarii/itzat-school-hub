# Bandwidth controls

## Incident: 16 October 2026

Supabase's school-project dashboard showed 5.632 GB uncached egress and
0.466 GB cached egress. The organization allowance was 5 GB uncached.
The current billing period displayed 15 October–15 November 2026.
Totals refresh periodically; these are an incident snapshot, not live metrics.

The 15 October chart showed Storage at 4.823 GB (95.5%), PostgREST at
222.703 MB (4.3%), Realtime at 10.016 MB (0.2%) and Auth at 1.214 MB.
Storage traffic is the priority. Request counts alone do not measure bytes.

## Active controls

- `school-config.json` has `chatPaused: true`. Chat renders a maintenance
  screen without creating a Supabase client or loading messages/media.
- Chat message, notification and presence polling are disabled during pause.
- Migration 022 also blocks room reads/writes and authorized Realtime reads
  through the shared chat gate. A restrictive Storage policy stops new
  community-media uploads and signed URLs. Existing signed URLs can remain
  usable until they expire; already downloaded media cannot be recalled.
- No chat data or files are deleted. School schedules, ISA Updates, Q+A and
  private teacher timetable uploads are retained.
- Cached schedules request only revisions newer than their saved revision.
  Unchanged visits receive an empty result rather than the complete document.
- Theme sync reads the user's own profile instead of the server/member state.
- Public teacher availability refreshes every five minutes in visible school
  schedule/calendar views, over today through the next 45 days.
- New chat uploads use a five-minute browser cache lifetime instead of zero.
  This does not retrofit headers on existing files or make the bucket public.
- When eventually re-enabled, fallback chat polling is every 30 seconds,
  notification polling is every 60 seconds, and neither runs in hidden tabs.

## Before reopening chat

1. Resize static avatars and banners before uploading, and set separate small
   upload limits for avatars, banners, emojis and chat attachments. Keep GIFs
   animated but cap their size; use explicit play/download for large media.
2. Stop rendering full-resolution banners outside profile views. Lazy-load
   attachments and avoid autoplaying animated media throughout member lists.
3. Reuse signed URLs only in memory within their existing authorization
   lifetime. Do not publish private buckets or cache private responses in the
   shared service worker. Plan a supported update of old objects' cache headers.
4. Replace repeated whole-room history downloads with cursor-based reads,
   bounded history, and incremental Realtime updates. Load friend lists and
   directories on demand, with pagination.
5. Inspect daily Storage, PostgREST and Realtime bytes in Supabase Usage.
   Use 70% as a warning threshold and 85% to pause media-heavy features before
   the quota is exhausted. No scheduled monitoring has been enabled.

The existing period cannot return below 100% through optimization: usage
already transferred remains counted. Avoid promising a quota guarantee.
Reference: https://supabase.com/docs/guides/platform/manage-your-usage/egress

## Reopening (Developer, only when requested)

Review usage first. Set `school_private.chat_runtime.paused` to false for its
singleton row in the SQL editor, then set frontend `chatPaused` to false and
deploy. The Storage policy and original audience restrictions will apply
automatically. Re-enabling access requires the normal action-time security
approval; do not toggle it as part of routine deployment.
