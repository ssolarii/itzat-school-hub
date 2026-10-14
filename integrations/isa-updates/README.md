# ISA Updates sync

ISA Updates course: **780277588874** ([Classroom](https://classroom.google.com/u/1/c/NzgwMjc3NTg4ODc0)).

Automatically publishes announcements from this course into the public ISA Updates feed when the Developer enables automatic publishing. Approval-draft mode remains available. Imports attachment titles, HTTPS links and Google-provided thumbnails. It does not import comments or roster identities, copy Drive files, or change their sharing permissions. Each notice has a Link to Classroom button; unavailable image previews fall back to the attachment link.

## Setup

1. Migrations 012–014 are applied to the school project. Migration 014 adds automatic-publication mode; configuring a connection still requires a Developer account.
2. Create an Apps Script project under the Google account with access to ISA Updates. Copy `Code.gs` and `appsscript.json`. The manifest enables the advanced Classroom service; a standard Google Cloud project also needs the Classroom API enabled there.
3. Set `ISA_COURSE_ID` to `780277588874`. `findISAUpdatesCourse` can verify the course name under the Google account installing the script. Do not use a classroom join code.
4. Generate a long random token privately. A signed-in Developer enters the course ID and token in **School administration → ISA sync**, with automatic publishing checked. Keep the token out of Git, chat and screenshots. Supabase stores its SHA-256 hash.
5. Set Script Properties: `ISA_COURSE_ID`, `SUPABASE_URL` (`https://rssshitgdspbqjtqxvmr.supabase.co`), `SUPABASE_PUBLISHABLE_KEY` (the public browser key), and `ISA_SYNC_TOKEN` (the same token). Never use a service-role or secret Supabase key.
6. Run `previewISAUpdates` to check the post count without transferring announcement text. The initial lookback is 30 days.
7. Run `syncISAUpdates` once, then check **ISA Updates** on the public site. In draft mode, check the announcement approval queue.
8. Run `installISASyncTrigger` after verifying the import. It installs one ten-minute trigger. `stopISASyncTrigger` removes only this handler's triggers. A Developer can disable the import endpoint with `disable_isa_sync()`.

## Behavior

- Script lock prevents overlapping runs; transient HTTP failures retry with backoff.
- Pagination and a five-minute overlap catch edited announcements. The cursor advances only after every batch succeeds; a partial retry does not create duplicates.
- Unchanged or older revisions are ignored. An edited pending draft is updated. Automatic mode replaces the same notice ID on source edits. Draft mode requires fresh approval before replacing a published notice.
- After migration 017, run `refreshISAUpdatesAttachments` once to backfill the last 30 days. Source content hashes allow enrichment without duplicating posts. Thumbnail URL rotation alone does not create another public timetable revision.
- Source deletion does not automatically remove a public notice in this first version. Remove outdated notices through the school admin review flow.
- Posts over 10,000 characters stop the run for manual review instead of silently truncating content.
- Google triggers use the installing account's permissions. Losing Classroom access stops the sync without advancing the cursor.
- Activated under the school Google account on 13 October 2026. The first run imported 14 posts; a second run imported no duplicates. One `syncISAUpdates` trigger runs every ten minutes. Tokens remain outside the repository.

References: [Classroom announcements API](https://developers.google.com/workspace/classroom/reference/rest/v1/courses.announcements/list), [advanced Classroom service](https://developers.google.com/apps-script/advanced/classroom), [Script Properties](https://developers.google.com/apps-script/guides/properties), [installable triggers](https://developers.google.com/apps-script/guides/triggers/installable).
