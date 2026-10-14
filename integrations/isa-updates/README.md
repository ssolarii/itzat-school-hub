# ISA Updates sync — setup draft

Imports published Classroom announcements into the private school announcement approval queue. It does not automatically publish, import comments or roster identities, or copy Drive files. Attachments stay behind the original Classroom post link and its existing Google permissions.

## Setup

1. Apply migration `202610130013_isa_updates_sync.sql` after approval.
2. Create an Apps Script project under the Google account with access to ISA Updates. Copy `Code.gs` and `appsscript.json`. The manifest enables the advanced Classroom service; a standard Google Cloud project also needs the Classroom API enabled there.
3. Run `findISAUpdatesCourse` to obtain the numeric course ID. Do not use the classroom join code.
4. Generate a long random token privately. A signed-in Developer enters the course ID and token in **School administration → ISA sync**. Keep the token out of Git, chat and screenshots. Supabase stores its SHA-256 hash.
5. Set Script Properties: `ISA_COURSE_ID`, `SUPABASE_URL` (`https://rssshitgdspbqjtqxvmr.supabase.co`), `SUPABASE_PUBLISHABLE_KEY` (the public browser key), and `ISA_SYNC_TOKEN` (the same token). Never use a service-role or secret Supabase key.
6. Run `previewISAUpdates` to check the post count without transferring announcement text. The initial lookback is 30 days.
7. Run `syncISAUpdates` once, then check **School administration → Announcements → Notice review queue**. Approve only posts suitable for public reading.
8. Run `installISASyncTrigger` after verifying the import. It installs one five-minute trigger. `stopISASyncTrigger` removes only this handler's triggers. A Developer can disable the import endpoint with `disable_isa_sync()`.

## Behavior

- Script lock prevents overlapping runs; transient HTTP failures retry with backoff.
- Pagination and a five-minute overlap catch edited announcements. The cursor advances only after every batch succeeds; a partial retry does not create duplicates.
- Unchanged or older revisions are ignored. An edited pending draft is updated. Edits to published notices require fresh approval and replace the existing notice ID on approval.
- Source deletion does not automatically remove a public notice in this first version. Remove outdated notices through the school admin review flow.
- Posts over 10,000 characters stop the run for manual review instead of silently truncating content.
- Google triggers use the installing account's permissions. Losing Classroom access stops the sync without advancing the cursor.
- Not activated yet: migration approval, the actual course ID, Google authorization and token configuration are still required.

References: [Classroom announcements API](https://developers.google.com/workspace/classroom/reference/rest/v1/courses.announcements/list), [advanced Classroom service](https://developers.google.com/apps-script/advanced/classroom), [Script Properties](https://developers.google.com/apps-script/guides/properties), [installable triggers](https://developers.google.com/apps-script/guides/triggers/installable).
