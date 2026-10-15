# Teacher subjects and check-outs

## Teaching scope

A link is one approved `(teacher account, subject code, class)` pair. For example,
`QR → 1A` does not include QR in 1B, other subjects in 1A, or every Year 1 class.
Teachers can request several subjects, choosing a separate class list for each.
Developer and Principal/Vice Principal accounts review the exact pairs on approval.
Approved links remain within the teacher's existing class permissions. Editing links
does not grant a new staff role or expand class permissions.

Existing teachers appear under **Admin → Teachers → Teacher subject links**.
Links can be edited or cleared there. The initial backfill uses only verified
digitized lessons in an active teacher's already-approved class scope. Duties such
as Advisory, Assembly, Seminar and PLC are not teaching subjects.

## Check-outs

An active Teacher account with confirmed links can check out for today or a future
date within a year. Select all six sessions for a whole day, or individual sessions.
The school date uses America/Belize. Saving the same date replaces its sessions.
The change is immediate. The teacher or school leadership can cancel it.

The full check-out record is private to the teacher and leadership. A bounded public
endpoint returns only affected date, subject, class, cycle day and session. It does
not return teacher names, account IDs, source timetables, or absence reasons.

Impact is matched in this order:

1. A verified private digitized timetable restricts impact to exact lessons.
2. Otherwise, the teacher's published session assignments restrict the matching.
3. With neither timetable, confirmed subject/class pairs match the student lessons
   in the selected sessions. For teachers who split the same subject within one
   class, digitize their timetables before relying on this fallback.

Holidays, weekends, and asynchronous/event days still follow the normal schedule
engine; an absence never advances or pauses the rolling cycle. Adjacent periods
with different availability do not merge. A named substitute keeps the replacement
lesson in place and suppresses the original teacher's unavailable label.

Students see **Teacher unavailable**, with existing times and rooms unchanged.
Open student schedules refresh availability once a minute or on manual Refresh.
No absence is inferred from a missing teaching assignment or pending upload.

## Activation

Apply `supabase/migrations/202610140021_teacher_subjects_and_checkouts.sql` before
deploying the frontend. The migration preserves legacy request/review APIs; the
new UI sends explicit subject/class pairs. Only leadership can confirm links.
All data changes run through server-authorized functions and create audit entries.
