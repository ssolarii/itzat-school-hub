import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dateKey, addDays, cycleDayFor, resolveDate, getLessons, getDayStatus, getWeek, nextSchoolDate, nextCampusDate } from '../src/schedule.js';

const groups = JSON.parse(readFileSync(new URL('../schoolwide-schedules.json', import.meta.url), 'utf8'));
function fixture() {
  return { settings: { anchorDate: '2026-10-09', anchorDay: 7, timezone: 'America/Belize', regularDismissal: '15:15' }, groups,
    bellProfiles: {
      regular: { slots: [{ start: '08:00', end: '08:55' }, { start: '09:00', end: '09:55' }, { start: '10:05', end: '11:00' }, { start: '11:05', end: '12:00' }, { start: '13:00', end: '13:55' }, { start: '14:05', end: '15:00' }], dismissal: '15:15' },
      quick: { slots: [{ start: '08:00', end: '08:50' }, { start: '08:55', end: '09:45' }, { start: '09:55', end: '10:45' }, { start: '10:55', end: '11:45' }, { start: '12:25', end: '13:10' }, { start: '13:15', end: '13:55' }], dismissal: '14:10' },
      half: { slots: [{ start: '08:00', end: '08:55' }, { start: '09:00', end: '09:55' }, { start: '10:05', end: '11:00' }, { start: '11:05', end: '12:00' }], dismissal: '12:20' }
    }, calendar: {}, overrides: [], announcements: [], banners: [], subjects: {} };
}
const at = (date, time) => new Date(`${date}T${time}:00-06:00`);

test('school timezone controls dates at midnight and supports override', () => {
  assert.equal(dateKey(new Date('2026-10-10T03:00:00Z')), '2026-10-09');
  assert.equal(dateKey(new Date('2026-10-10T03:00:00Z'), 'UTC'), '2026-10-10');
});
test('date arithmetic includes leap days and validates inputs', () => {
  assert.equal(addDays('2028-02-28', 1), '2028-02-29');
  assert.equal(addDays('2026-12-31', 1), '2027-01-01');
  assert.equal(addDays('2026-01-01', -1), '2025-12-31');
  assert.throws(() => addDays('2026-02-30', 1), RangeError);
  assert.throws(() => addDays('2026-01-01', 0.5), RangeError);
});
test('Friday day seven wraps to Monday day one', () => {
  const doc = fixture();
  assert.equal(cycleDayFor('2026-10-09', doc), 7);
  assert.equal(cycleDayFor('2026-10-10', doc), null);
  assert.equal(cycleDayFor('2026-10-12', doc), 1);
});
test('cycle counts correctly backward, including across a weekend', () => {
  const doc = fixture();
  assert.equal(cycleDayFor('2026-10-08', doc), 6);
  assert.equal(cycleDayFor('2026-10-02', doc), 2);
  assert.equal(cycleDayFor('2026-10-01', doc), 1);
  assert.equal(cycleDayFor('2026-09-30', doc), 7);
});
test('holidays pause cycle in both directions', () => {
  const doc = fixture();
  doc.calendar['2026-10-12'] = { type: 'holiday', label: 'Holiday' };
  doc.calendar['2026-10-07'] = { type: 'holiday' };
  assert.equal(cycleDayFor('2026-10-12', doc), null);
  assert.equal(cycleDayFor('2026-10-13', doc), 1);
  assert.equal(cycleDayFor('2026-10-06', doc), 5);
});
test('async and event days advance the cycle without campus lessons', () => {
  const doc = fixture();
  doc.calendar['2026-10-12'] = { type: 'async', label: 'Independent work' };
  doc.calendar['2026-10-13'] = { type: 'event', label: 'Parade' };
  assert.equal(cycleDayFor('2026-10-12', doc), 1);
  assert.equal(cycleDayFor('2026-10-13', doc), 2);
  assert.equal(cycleDayFor('2026-10-14', doc), 3);
  assert.deepEqual(getLessons('2026-10-12', '3CS', doc), []);
  assert.equal(getDayStatus('2026-10-13', '3CS', doc, at('2026-10-13', '10:00')).status, 'event');
  assert.equal(nextSchoolDate('2026-10-09', doc), '2026-10-12');
  assert.equal(nextSchoolDate('2026-10-09', doc, { includeAsync: false }), '2026-10-13');
  assert.equal(nextCampusDate('2026-10-09', doc), '2026-10-14');
});
test('missing or closed anchor never invents a cycle day', () => {
  const doc = fixture(); doc.settings.anchorDate = null;
  assert.equal(cycleDayFor('2026-10-09', doc), null);
  assert.equal(getDayStatus('2026-10-09', '3CS', doc, at('2026-10-09', '10:00')).status, 'unconfigured');
  doc.settings.anchorDate = '2026-10-10';
  assert.equal(cycleDayFor('2026-10-12', doc), null);
});
test('all eleven schedules have four student sessions on day seven, no PLC', () => {
  const doc = fixture();
  assert.equal(Object.keys(groups).length, 11);
  for (const group of Object.keys(groups)) {
    const lessons = getLessons('2026-10-09', group, doc);
    assert.equal(lessons.length, 4, group);
    assert.ok(lessons.every(l => l.subject !== 'PLC'), group);
    assert.equal(lessons.at(-1).end, '12:00', group);
  }
  assert.equal(resolveDate('2026-10-09', doc).profile.dismissal, '12:20');
});
test('uploaded missing rooms remain null and teachers remain unassigned', () => {
  const doc = fixture(); doc.settings.anchorDay = 5;
  const pe = getLessons('2026-10-09', '3CS', doc).find(l => l.subject === 'PE');
  assert.equal(pe.room, null); assert.equal(pe.teacher, null);
});
test('merged Super Teams spans sessions five and six with the correct bell end', () => {
  const doc = fixture(); doc.settings.anchorDay = 3;
  const lessons = getLessons('2026-10-09', '1A', doc);
  assert.equal(lessons.length, 5);
  assert.deepEqual({ subject: lessons[4].subject, session: lessons[4].session, span: lessons[4].span, start: lessons[4].start, end: lessons[4].end },
    { subject: 'Super Teams', session: 5, span: 2, start: '13:00', end: '15:00' });
});
test('date scoped substitute splits a merged block and preserves the other session', () => {
  const doc = fixture(); doc.settings.anchorDay = 3;
  doc.overrides.push({ id: 'replacement', date: '2026-10-09', group: '1A', session: 6, subject: 'QR', room: 'N2', teacher: 'Example teacher', note: 'Cover' });
  const lessons = getLessons('2026-10-09', '1A', doc);
  assert.equal(lessons.length, 6); assert.equal(lessons[4].subject, 'Super Teams');
  assert.equal(lessons[4].end, '13:55'); assert.equal(lessons[5].start, '14:05');
  assert.equal(lessons[5].subject, 'QR'); assert.equal(lessons[5].substitution, true);
  assert.equal(lessons[5].original.subject, 'Super Teams'); assert.equal(lessons[5].teacher, 'Example teacher');
  assert.ok(getLessons('2026-10-20', '1A', doc).every(l => !l.substitution));
});
test('room only substitution can explicitly clear a room and does not affect another group', () => {
  const doc = fixture(); doc.settings.anchorDay = 1;
  doc.overrides.push({ date: '2026-10-09', group: '3CS', session: 1, room: null, teacher: 'Cover teacher' });
  const lesson = getLessons('2026-10-09', '3CS', doc)[0];
  assert.equal(lesson.subject, 'QR'); assert.equal(lesson.room, null); assert.equal(lesson.original.room, 'D2');
  assert.equal(getLessons('2026-10-09', '4CS', doc)[0].substitution, false);
});
test('bell override belongs only to its date and does not shift the cycle', () => {
  const doc = fixture(); doc.settings.anchorDay = 4;
  doc.calendar['2026-10-09'] = { type: 'regular', bellProfile: 'quick' };
  assert.equal(getLessons('2026-10-09', '3CS', doc)[2].end, '10:45');
  assert.equal(resolveDate('2026-10-12', doc).bellProfile, 'regular');
  assert.equal(cycleDayFor('2026-10-12', doc), 5);
  assert.equal(resolveDate('2026-10-09', doc).profile.dismissal, '14:10');
});
test('half day override limits a regular cycle day to four lessons', () => {
  const doc = fixture(); doc.settings.anchorDay = 3;
  doc.calendar['2026-10-09'] = { type: 'regular', bellProfile: 'half' };
  assert.equal(getLessons('2026-10-09', '1A', doc).length, 4);
});
test('statuses cover before school, current lesson and exact bell boundaries', () => {
  const doc = fixture(); doc.settings.anchorDay = 1;
  let state = getDayStatus('2026-10-09', '3CS', doc, at('2026-10-09', '07:40'));
  assert.equal(state.status, 'before'); assert.equal(state.remainingSeconds, 1200);
  state = getDayStatus('2026-10-09', '3CS', doc, at('2026-10-09', '08:00'));
  assert.equal(state.status, 'lesson'); assert.equal(state.elapsedSeconds, 0); assert.equal(state.remainingSeconds, 3300);
  state = getDayStatus('2026-10-09', '3CS', doc, at('2026-10-09', '08:55'));
  assert.equal(state.status, 'transition'); assert.equal(state.remainingSeconds, 300);
  state = getDayStatus('2026-10-09', '3CS', doc, at('2026-10-09', '10:38'));
  assert.equal(state.current.subject, 'LA'); assert.equal(state.remainingSeconds, 1320); assert.equal(state.elapsedSeconds, 1980);
});
test('regular and quick lunch countdowns use the selected profile', () => {
  const doc = fixture(); doc.settings.anchorDay = 1;
  assert.equal(getDayStatus('2026-10-09', '3CS', doc, at('2026-10-09', '12:45')).remainingSeconds, 900);
  assert.equal(getDayStatus('2026-10-09', '3CS', doc, at('2026-10-09', '12:45')).status, 'lunch');
  doc.calendar['2026-10-09'] = { type: 'regular', bellProfile: 'quick' };
  assert.equal(getDayStatus('2026-10-09', '3CS', doc, at('2026-10-09', '12:10')).remainingSeconds, 900);
  assert.equal(getDayStatus('2026-10-09', '3CS', doc, at('2026-10-09', '12:10')).status, 'lunch');
});
test('dismissal preparation and after school never report negative countdowns', () => {
  const doc = fixture();
  let state = getDayStatus('2026-10-09', '3CS', doc, at('2026-10-09', '12:05'));
  assert.equal(state.status, 'dismissal-prep'); assert.equal(state.remainingSeconds, 900);
  state = getDayStatus('2026-10-09', '3CS', doc, at('2026-10-09', '12:20'));
  assert.equal(state.status, 'after'); assert.equal(state.remainingSeconds, 0);
  assert.equal(getDayStatus('2026-10-09', '3CS', doc, at('2026-10-09', '23:59')).remainingSeconds, 0);
});
test('future date is before school and past date is after even when device time matches a lesson', () => {
  const doc = fixture(); doc.settings.anchorDay = 1;
  const now = at('2026-10-12', '10:38');
  assert.equal(getDayStatus('2026-10-09', '3CS', doc, now).status, 'after');
  assert.equal(getDayStatus('2026-10-13', '3CS', doc, now).status, 'before');
});
test('week view starts Monday and retains closed dates', () => {
  const doc = fixture(); doc.calendar['2026-10-12'] = { type: 'holiday', label: 'Holiday' };
  const week = getWeek('2026-10-18', doc);
  assert.equal(week.length, 7); assert.equal(week[0].date, '2026-10-12');
  assert.equal(week[0].type, 'holiday'); assert.equal(week[6].date, '2026-10-18'); assert.equal(week[6].type, 'weekend');
});
test('weekend cannot become rolling merely because a calendar event is listed', () => {
  const doc = fixture(); doc.calendar['2026-10-10'] = { type: 'event', label: 'Saturday event' };
  assert.equal(resolveDate('2026-10-10', doc).type, 'weekend');
  assert.equal(resolveDate('2026-10-10', doc).label, 'Saturday event');
  assert.equal(cycleDayFor('2026-10-12', doc), 1);
});
