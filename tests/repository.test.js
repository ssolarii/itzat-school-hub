import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRepository, validateDocument, validateSnapshot } from '../src/repository.js';

const groups = JSON.parse(readFileSync(new URL('../schoolwide-schedules.json', import.meta.url), 'utf8'));
function seed() {
  const regularSlots = ['08:00/08:55', '09:00/09:55', '10:05/11:00', '11:05/12:00', '13:00/13:55', '14:05/15:00'].map(pair => { const [start, end] = pair.split('/'); return { start, end }; });
  return { settings: { anchorDate: '2026-10-13', anchorDay: 6, timezone: 'America/Belize', regularDismissal: '15:15' }, groups, subjects: {}, calendar: {}, overrides: [], announcements: [], banners: [], teacherAssignments: [],
    bellProfiles: { regular: { slots: regularSlots, dismissal: '15:15' }, quick: { slots: ['08:00/08:50', '08:55/09:45', '09:55/10:45', '10:55/11:45', '12:25/13:10', '13:15/13:55'].map(pair => { const [start, end] = pair.split('/'); return { start, end }; }), dismissal: '14:10' }, half: { slots: regularSlots.slice(0, 4), dismissal: '12:20' } } };
}
function memoryStorage() {
  const values = new Map();
  return { getItem: key => values.get(key) || null, setItem: (key, value) => values.set(key, value), removeItem: key => values.delete(key) };
}
const snapshot = (revision = 1) => ({ document: seed(), revision, publishedAt: '2026-10-10T15:00:00Z' });

test('validates all uploaded groups with confirmed anchor and schoolwide half-day dismissal', () => {
  const document = validateDocument(seed());
  assert.equal(Object.keys(document.groups).length, 11);
  assert.equal(document.settings.anchorDate, '2026-10-13');
  assert.equal(document.bellProfiles.half.dismissal, '12:20');
});
test('validation rejects invalid dates, cycle days and timezones', () => {
  let document = seed(); document.settings.anchorDate = '2026-02-30'; assert.throws(() => validateDocument(document), /anchor date/);
  document = seed(); document.settings.anchorDay = 8; assert.throws(() => validateDocument(document), /anchor day/);
  document = seed(); document.settings.timezone = 'Not/a-timezone'; assert.throws(() => validateDocument(document), /timezone/);
});
test('validation rejects overlapping bells and early dismissal', () => {
  let document = seed(); document.bellProfiles.regular.slots[1].start = '08:30'; assert.throws(() => validateDocument(document), /overlap/);
  document = seed(); document.bellProfiles.half.dismissal = '11:50'; assert.throws(() => validateDocument(document), /dismissal/);
});
test('validation rejects malformed schedules, calendar arrangements and substitutions', () => {
  let document = seed(); document.groups = { '3CS': [] }; assert.throws(() => validateDocument(document), /seven cycle/);
  document = seed(); document.calendar = { '2026-10-13': { type: 'unknown' } }; assert.throws(() => validateDocument(document), /calendar type/);
  document = seed(); document.overrides = [{ date: '2026-10-13', group: 'missing', session: 1 }]; assert.throws(() => validateDocument(document), /substitute date or group/);
  document = seed(); document.overrides = [{ date: '2026-10-13', group: '3CS', session: 7 }]; assert.throws(() => validateDocument(document), /substitute session/);
});
test('snapshot validates monotonic integer metadata and strips unrelated adapter fields', () => {
  assert.throws(() => validateSnapshot({ ...snapshot(), revision: -1 }), /revision/);
  assert.throws(() => validateSnapshot({ ...snapshot(), publishedAt: 'invalid' }), /timestamp/);
  const document = seed(); document.session = { token: 'never-cache-this' };
  const saved = validateSnapshot({ ...snapshot(), document, auth: 'never-cache-this' });
  assert.equal(saved.document.session, undefined); assert.equal(saved.auth, undefined);
});
test('seed remains usable without any backend or local storage', async () => {
  const repo = createRepository({ seed: seed(), storage: null });
  const state = await repo.load(); assert.equal(state.source, 'seed'); assert.equal(state.offline, false); assert.equal(state.revision, 0);
  await assert.rejects(repo.publish(seed()), /connected, authorized backend/);
});
test('successful remote load caches a verified snapshot, cache boots offline', async () => {
  const storage = memoryStorage();
  const repo = createRepository({ seed: seed(), storage, backend: { loadPublished: async () => snapshot(3) } });
  const state = await repo.load(); assert.equal(state.source, 'remote'); assert.equal(state.revision, 3);
  const offline = createRepository({ seed: seed(), storage, backend: { loadPublished: async () => { throw new Error('Network unavailable'); } } });
  const cached = await offline.load(); assert.equal(cached.source, 'cache'); assert.equal(cached.revision, 3); assert.equal(cached.offline, true); assert.equal(cached.error, 'Network unavailable');
});
test('corrupt or incompatible cache falls back to validated seed', () => {
  const storage = memoryStorage(); storage.setItem('isa.published-schedule.v1', '{not-json');
  let repo = createRepository({ seed: seed(), storage }); assert.equal(repo.getState().source, 'seed'); assert.ok(repo.getState().cacheError);
  storage.setItem('isa.published-schedule.v1', JSON.stringify({ schemaVersion: 99, snapshot: snapshot() }));
  repo = createRepository({ seed: seed(), storage }); assert.equal(repo.getState().source, 'seed'); assert.match(repo.getState().cacheError, /Unsupported/);
});
test('invalid remote payload never replaces the previous verified cache', async () => {
  const storage = memoryStorage(); let remote = snapshot(1);
  const repo = createRepository({ seed: seed(), storage, backend: { loadPublished: async () => remote } });
  await repo.load(); const previous = storage.getItem('isa.published-schedule.v1');
  remote = { document: {}, revision: 2 }; const state = await repo.load();
  assert.equal(state.revision, 1); assert.equal(state.offline, true); assert.equal(storage.getItem('isa.published-schedule.v1'), previous);
});
test('failed publishing leaves current state and saved cache unchanged', async () => {
  const storage = memoryStorage();
  const repo = createRepository({ seed: seed(), storage, backend: { loadPublished: async () => snapshot(1), publish: async () => { throw new Error('Permission denied'); } } });
  await repo.load(); const previous = repo.getState(), cached = storage.getItem('isa.published-schedule.v1');
  const draft = seed(); draft.settings.anchorDay = 4;
  await assert.rejects(repo.publish(draft), /Permission denied/);
  assert.deepEqual(repo.getState(), previous); assert.equal(storage.getItem('isa.published-schedule.v1'), cached);
});
test('successful publish forwards expected revision and adopts complete confirmed version', async () => {
  const storage = memoryStorage(); let received;
  const backend = { loadPublished: async () => snapshot(1), publish: async (document, options) => { received = options; return { ...snapshot(2), document }; } };
  const repo = createRepository({ seed: seed(), storage, backend }); await repo.load();
  const draft = seed(); draft.settings.anchorDay = 4;
  const state = await repo.publish(draft); assert.deepEqual(received, { expectedRevision: 1 });
  assert.equal(state.revision, 2); assert.equal(state.document.settings.anchorDay, 4);
  assert.equal(JSON.parse(storage.getItem('isa.published-schedule.v1')).snapshot.revision, 2);
});
test('local stale revision conflict does not contact the backend', async () => {
  let called = false;
  const repo = createRepository({ seed: seed(), storage: null, backend: { loadPublished: async () => snapshot(3), publish: async () => { called = true; return snapshot(4); } } });
  await repo.load(); await assert.rejects(repo.publish(seed(), { expectedRevision: 1 }), /Revision conflict/); assert.equal(called, false);
});
test('older remote revision and unchanged publish revision are rejected without cache writes', async () => {
  let remote = snapshot(3); const storage = memoryStorage();
  const repo = createRepository({ seed: seed(), storage, backend: { loadPublished: async () => remote, publish: async () => snapshot(3) } });
  await repo.load(); const cached = storage.getItem('isa.published-schedule.v1');
  remote = snapshot(2); await repo.load(); assert.equal(repo.getState().revision, 3); assert.equal(storage.getItem('isa.published-schedule.v1'), cached);
  await assert.rejects(repo.publish(seed()), /advance the revision/); assert.equal(storage.getItem('isa.published-schedule.v1'), cached);
});
test('storage quota failure preserves remote usability and reports offline limitation', async () => {
  const storage = { getItem: () => null, setItem: () => { throw new Error('Quota exceeded'); } };
  const repo = createRepository({ seed: seed(), storage, backend: { loadPublished: async () => snapshot(1) } });
  const state = await repo.load(); assert.equal(state.source, 'remote'); assert.equal(state.offline, false); assert.equal(state.cacheError, 'Quota exceeded');
});
test('returned snapshots are copies; edits cannot mutate repository state before publication', async () => {
  const repo = createRepository({ seed: seed(), storage: null }); const state = repo.getState();
  state.document.settings.anchorDay = 4;
  assert.equal(repo.getState().document.settings.anchorDay, 6);
});
test('archived group metadata survives publication and offline caching', async () => {
  const storage = memoryStorage();
  const backend = { publish: async document => ({ ...snapshot(1), document }) };
  const repo = createRepository({ seed: seed(), storage, backend });
  const draft = seed(); draft.archivedGroups = ['3CS'];
  const published = await repo.publish(draft);
  assert.deepEqual(published.document.archivedGroups, ['3CS']);
  assert.ok(published.document.groups['3CS'], 'archiving retains the historical timetable');
  const offline = createRepository({ seed: seed(), storage });
  assert.deepEqual(offline.getState().document.archivedGroups, ['3CS']);
});
test('archived groups reject unknown, duplicate, malformed and all-archived lists', () => {
  let document = seed(); document.archivedGroups = ['missing']; assert.throws(() => validateDocument(document), /registered group/);
  document = seed(); document.archivedGroups = ['3CS', '3CS']; assert.throws(() => validateDocument(document), /unique/);
  document = seed(); document.archivedGroups = '3CS'; assert.throws(() => validateDocument(document), /array/);
  document = seed(); document.archivedGroups = Object.keys(document.groups); assert.throws(() => validateDocument(document), /remain active/);
});
