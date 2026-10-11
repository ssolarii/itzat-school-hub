import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { calendarView, studentView, teacherView, agenda, notices, subject, lessonRow, dateLabel, escape } from '../src/views.js';

const seed = JSON.parse(readFileSync(new URL('../school-data.json', import.meta.url), 'utf8'));
const fixture = () => structuredClone(seed);
const at = (date, time) => new Date(`${date}T${time}:00-06:00`);
const pattern = html => html.split('<h3>Explore the 7-day cycle</h3>')[1].split('<h3>Upcoming events & holidays</h3>')[0];
const codes = html => [...html.matchAll(/<span class="subject-icon">.*?<\/span><span>(.*?)<\/span>/g)].map(match => match[1]);

test('cycle picker shows the selected repeating day regardless of holidays and date overrides', () => {
  const doc = fixture();
  doc.calendar['2026-10-15'] = { type: 'holiday', label: 'Holiday' };
  doc.overrides.push({ id: 'dated', date: '2026-10-13', group: '3CS', session: 1, subject: 'QR', room: 'N4', teacher: 'Test staff' });
  for (let day = 1; day <= 7; day++) {
    const html = calendarView({ document: doc, group: '3CS', calendarDate: '2026-10-13', cycleDay: day });
    assert.deepEqual(codes(pattern(html)), doc.groups['3CS'][day - 1].map(lesson => escape(lesson.subject)), `Day ${day}`);
  }
  const half = pattern(calendarView({ document: doc, group: '3CS', calendarDate: '2026-10-13', cycleDay: 7 }));
  assert.ok(half.includes('12:20 PM'));
  assert.ok(!half.includes('Substitute'));
});

test('cycle pattern works when the selected calendar date is on a weekend', () => {
  const doc = fixture(), html = calendarView({ document: doc, group: '1A', calendarDate: '2026-10-17', cycleDay: 3 });
  assert.deepEqual(codes(pattern(html)), doc.groups['1A'][2].map(lesson => escape(lesson.subject)));
  assert.ok(pattern(html).includes('Super Teams'));
});

test('weekend week view shows the upcoming school week', () => {
  const doc = fixture(), html = studentView({ document: doc, group: '3CS', view: 'week', now: at('2026-10-10', '12:00') });
  assert.ok(html.includes(`Week of ${dateLabel('2026-10-12')}`));
  assert.ok(!html.includes(dateLabel('2026-10-05')));
});

test('today adapts to dismissal, half-day bells, and non-campus arrangements', () => {
  const doc = fixture();
  const prep = studentView({ document: doc, group: '3CS', view: 'today', now: at('2026-10-13', '15:10') });
  assert.ok(prep.includes('Getting ready to leave'));
  assert.equal((prep.match(/class="lesson-row\s+finished"/g) || []).length, doc.groups['3CS'][5].length);
  const after = studentView({ document: doc, group: '3CS', view: 'today', now: at('2026-10-14', '12:21') });
  assert.ok(after.includes('School’s out.'));
  assert.ok(after.includes('Replay today · Day 7'));
  doc.calendar['2026-10-15'] = { type: 'async', label: 'Independent work', description: 'Work at home; no live classes.' };
  const async = studentView({ document: doc, group: '3CS', view: 'today', now: at('2026-10-15', '10:00') });
  assert.ok(async.includes('Work at home; no live classes.'));
  assert.ok(!async.includes('id="timer-value"'));
});

test('teacher empty state distinguishes unpublished assignments, closed days, and no lessons today', () => {
  const doc = fixture();
  assert.ok(teacherView(doc, '2026-10-13', 'Staff').includes('Lessons haven’t been assigned yet'));
  doc.calendar['2026-10-15'] = { type: 'async', label: 'Independent work', description: 'No live classes.' };
  const closedPending = teacherView(doc, '2026-10-15', 'Staff');
  assert.ok(closedPending.includes('Independent work'));
  assert.ok(closedPending.includes('Teacher lesson assignments have not been published yet'));
  doc.teacherAssignments = [{ teacher: 'Staff', group: '3CS', day: 6, session: 1 }];
  assert.ok(teacherView(doc, '2026-10-15', 'Staff').includes('Independent work'));
  assert.ok(teacherView(doc, '2026-10-14', 'Staff').includes('No teaching lessons listed today'));
  assert.ok(!teacherView(doc, '2026-10-14', 'Staff').includes('haven’t been assigned yet'));
});

test('teacher joined lessons render once when both session assignments refer to the same lesson', () => {
  const doc = fixture();
  doc.teacherAssignments = [{ teacher: 'Staff', group: '1A', day: 3, session: 5 }, { teacher: 'Staff', group: '1A', day: 3, session: 6 }];
  doc.settings.anchorDay = 3;
  const html = teacherView(doc, '2026-10-13', 'Staff');
  assert.equal(codes(html).filter(code => code === 'Super Teams').length, 1);
});

test('public notices filter drafts, future notices, expired notices, and unrelated classes', () => {
  const doc = fixture();
  doc.announcements = [
    { id: 'public', title: 'Public notice', body: 'Read this', audience: 'school', approved: true, publishedAt: '2020-01-01T00:00:00Z' },
    { id: 'class', title: 'Class notice', body: 'Read this', audience: '3CS', approved: true, publishedAt: '2020-01-01T00:00:00Z' },
    { id: 'other', title: 'Other class notice', body: 'Read this', audience: '1A', approved: true, publishedAt: '2020-01-01T00:00:00Z' },
    { id: 'draft', title: 'Private draft', body: 'Read this', audience: 'school', approved: false, publishedAt: '2020-01-01T00:00:00Z' },
    { id: 'expired', title: 'Expired notice', body: 'Read this', audience: 'school', approved: true, publishedAt: '2020-01-01T00:00:00Z', expiresAt: '2020-01-02T00:00:00Z' },
    { id: 'future', title: 'Future notice', body: 'Read this', audience: 'school', approved: true, publishedAt: '2099-01-01T00:00:00Z' }
  ];
  const html = notices(doc, '3CS');
  assert.ok(html.includes('Public notice'));
  assert.ok(html.includes('Class notice'));
  for (const title of ['Other class notice', 'Private draft', 'Expired notice', 'Future notice']) assert.ok(!html.includes(title));
});

test('subject names, room, teacher, notes, notices and calendar text are escaped', () => {
  const doc = fixture();
  doc.subjects.QR.name = '<script>name()</script>';
  assert.ok(subject('QR', doc).includes('&lt;script&gt;'));
  const row = lessonRow({ start: '08:00', end: '08:55', subject: 'QR', room: '<img src=x>', teacher: '<script>teacher()</script>', note: '<script>note()</script>' }, doc);
  assert.ok(!row.includes('<script>'));
  assert.ok(!row.includes('<img'));
  doc.announcements = [{ id: 'unsafe', title: '<script>title()</script>', body: '<img src=x onerror=alert(1)>', audience: 'school', approved: true, publishedAt: '2020-01-01T00:00:00Z' }];
  assert.ok(!notices(doc).includes('<img'));
  doc.calendar['2026-10-15'] = { type: 'event', label: '<script>event()</script>', description: '<img src=x>' };
  assert.ok(!agenda('2026-10-15', '3CS', doc).includes('<script>'));
});
