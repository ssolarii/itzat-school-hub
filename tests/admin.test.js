import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { renderAdmin, handleAdminSubmit } from '../src/admin.js';

const seed = JSON.parse(readFileSync(new URL('../school-data.json', import.meta.url), 'utf8'));
const fixture = () => structuredClone(seed);
const developer = { active: true, role: 'developer', capabilities: [], groups: [] };
const proposal = (doc, kind, values = {}) => {
  const data = new FormData();
  data.set('adminKind', kind);
  for (const [key, value] of Object.entries(values)) {
    if (Array.isArray(value)) value.forEach(item => data.append(key, item));
    else data.set(key, String(value));
  }
  return handleAdminSubmit(data, doc);
};

test('timetable proposals retain joined sessions and unknown rooms without mutating source', () => {
  const doc = fixture(), original = JSON.stringify(doc), lessons = doc.groups['1A'][2];
  const values = { group: '1A', day: 3, rowCount: lessons.length };
  lessons.forEach((lesson, i) => { values[`subject-${i}`] = lesson.subject; values[`room-${i}`] = lesson.room ?? ''; });
  const result = proposal(doc, 'schedule', values);
  assert.equal(result.document.groups['1A'][2].at(-1).span, 2);
  assert.equal(result.document.groups['1A'][2].at(-1).room, null);
  assert.equal(result.kind, 'document');
  assert.equal(JSON.stringify(doc), original);
  assert.throws(() => proposal(doc, 'schedule', { ...values, rowCount: 99 }), /changed/);
});

test('substitutions apply to one date and session and replace duplicates', () => {
  const doc = fixture(), values = { group: '3CS', date: '2026-10-13', session: 3, subject: 'LA', teacher: 'Test substitute', room: 'N4', note: 'Bring work' };
  const first = proposal(doc, 'substitute', values).document;
  const second = proposal(first, 'substitute', { ...values, subject: 'QR', teacher: 'Other substitute' }).document;
  const matching = second.overrides.filter(item => item.group === '3CS' && item.date === values.date && item.session === 3);
  assert.equal(matching.length, 1);
  assert.equal(matching[0].subject, 'QR');
  assert.equal(matching[0].teacher, 'Other substitute');
  assert.equal(proposal(second, 'remove-substitute', { id: matching[0].id }).document.overrides.length, 0);
});

test('substitution validation rejects unavailable sessions and non-campus dates', () => {
  const doc = fixture(), values = { group: '3CS', date: '2026-10-14', session: 5, subject: 'LA', teacher: 'Test staff' };
  assert.throws(() => proposal(doc, 'substitute', values), /only 4/);
  assert.throws(() => proposal(doc, 'substitute', { ...values, date: '2026-10-17', session: 1 }), /campus/);
  doc.calendar['2026-10-15'] = { type: 'async', label: 'Independent work' };
  assert.throws(() => proposal(doc, 'substitute', { ...values, date: '2026-10-15', session: 1 }), /campus/);
});

test('teacher drafts and published notices have separate action paths', () => {
  const doc = fixture(), values = { title: 'Bring your sketchbook', body: 'Bring it to FA.', audience: '3CS', subject: 'FA' };
  const draft = proposal(doc, 'notice-draft', values);
  assert.equal(draft.kind, 'notice');
  assert.deepEqual(draft.payload, values);
  assert.equal(draft.document, doc);
  const publication = proposal(doc, 'notice-publish', values);
  assert.equal(publication.document.announcements.at(-1).approved, true);
  assert.equal(publication.document.announcements.at(-1).subject, 'FA');
  assert.throws(() => proposal(doc, 'notice-publish', { ...values, audience: 'missing' }), /audience/);
});

test('calendar arrangements keep attendance and bell choices separate', () => {
  const doc = fixture();
  const result = proposal(doc, 'calendar', { date: '2026-10-15', type: 'async', label: 'Independent work', description: 'No live classes', bellProfile: '' });
  assert.deepEqual(result.document.calendar['2026-10-15'], { type: 'async', label: 'Independent work', description: 'No live classes' });
  assert.throws(() => proposal(doc, 'calendar', { date: '2026-10-13', type: 'holiday' }), /anchor/);
});

test('new classes copy complete schedules and archive preserves data', () => {
  const doc = fixture(), created = proposal(doc, 'class-create', { code: '1C', template: '1A' }).document;
  assert.deepEqual(created.groups['1C'], doc.groups['1A']);
  assert.notEqual(created.groups['1C'], doc.groups['1A']);
  assert.throws(() => proposal(doc, 'class-create', { code: '1A', template: '1A' }), /already/);
  const archived = proposal(doc, 'class-archive', { group: '3CS' }).document;
  assert.ok(archived.archivedGroups.includes('3CS'));
  assert.deepEqual(archived.groups['3CS'], doc.groups['3CS']);
  assert.ok(!proposal(archived, 'class-restore', { group: '3CS' }).document.archivedGroups.includes('3CS'));
});

test('subject creation and banner dates are validated', () => {
  const doc = fixture();
  assert.equal(proposal(doc, 'subject', { code: 'New', name: 'New subject', icon: 'book-open' }).document.subjects.New.name, 'New subject');
  assert.throws(() => proposal(doc, 'subject', { code: 'QR', name: 'Existing', icon: 'calculator' }), /already/);
  const result = proposal(doc, 'banner', { text: 'Quick Exit today', tone: 'warning', starts: '2026-10-13', expires: '2026-10-14' });
  assert.equal(result.document.banners[0].startsAt, '2026-10-13T00:00:00-06:00');
  assert.throws(() => proposal(doc, 'banner', { text: 'Notice', tone: 'info', starts: '2026-10-14', expires: '2026-10-13' }), /end after/);
});

test('bell settings round-trip and reject overlapping periods', () => {
  const doc = fixture(), values = { anchorDate: doc.settings.anchorDate, anchorDay: doc.settings.anchorDay };
  for (const [key, profile] of Object.entries(doc.bellProfiles)) {
    values[`${key}-dismissal`] = profile.dismissal;
    profile.slots.forEach((slot, i) => { values[`${key}-start-${i}`] = slot.start; values[`${key}-end-${i}`] = slot.end; });
  }
  assert.deepEqual(proposal(doc, 'settings', values).document.bellProfiles, doc.bellProfiles);
  assert.throws(() => proposal(doc, 'settings', { ...values, 'regular-end-0': '07:59' }), /order/);
  assert.throws(() => proposal(doc, 'settings', { ...values, anchorDate: '2026-10-17' }), /weekday/);
});

test('role rendering honors teacher scopes and delegated class permissions', () => {
  const doc = fixture();
  for (const tab of ['schedule', 'substitute', 'calendar', 'notices', 'banner', 'subjects', 'classes', 'settings', 'permissions']) {
    assert.ok(renderAdmin({ document: doc, membership: developer, tab, group: '3CS', day: 7, today: '2026-10-13' }).includes('School administration'));
  }
  const teacher = { active: true, role: 'teacher', capabilities: ['notices.submit'], groups: ['3CS'] };
  const teacherPage = renderAdmin({ document: doc, membership: teacher, tab: 'schedule', today: '2026-10-13' });
  assert.ok(teacherPage.includes('data-admin-kind="notice-draft"'));
  assert.ok(!teacherPage.includes('data-admin-kind="member"'));
  assert.ok(!teacherPage.includes('<option value="1A"'));
  const delegated = { active: true, role: 'codeveloper', capabilities: ['classes.manage'], groups: ['3CS'] };
  const delegatedPage = renderAdmin({ document: doc, membership: delegated, tab: 'classes', today: '2026-10-13' });
  assert.match(delegatedPage, /data-admin-kind="class-create"[\s\S]*?<fieldset[^>]* disabled/);
  assert.match(delegatedPage, /data-admin-kind="class-archive"[^>]*><input type="hidden" name="group" value="3CS"><fieldset[^>]*>/);
});

test('grant proposals reject unsupported teacher capabilities and malformed accounts', () => {
  const doc = fixture(), values = { userId: '123e4567-e89b-12d3-a456-426614174000', role: 'teacher', groups: '3CS', capabilities: ['notices.submit'], active: true };
  assert.equal(proposal(doc, 'member', values).kind, 'member');
  assert.throws(() => proposal(doc, 'member', { ...values, groups: '*' }), /specific classes/);
  assert.throws(() => proposal(doc, 'member', { ...values, capabilities: ['notices.publish'] }), /specific classes/);
  assert.throws(() => proposal(doc, 'member', { ...values, userId: 'not-a-uuid' }), /UUID/);
});

test('admin public data is escaped in controls and announcement text', () => {
  const doc = fixture();
  doc.subjects.QR.name = '<script>alert(1)</script>';
  doc.announcements.push({ id: 'xss', title: '<img src=x onerror=alert(1)>', body: '<script>bad()</script>', audience: 'school', approved: true, publishedAt: '2020-01-01T00:00:00Z' });
  const html = renderAdmin({ document: doc, membership: developer, tab: 'notices', group: '3CS', today: '2026-10-13' });
  assert.ok(!html.includes('<script>'));
  assert.ok(!html.includes('<img'));
  assert.ok(html.includes('&lt;script&gt;'));
});
