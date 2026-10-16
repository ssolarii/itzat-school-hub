import { addDays } from './schedule.js';

export const CACHE_SCHEMA_VERSION = 1;
const clone = value => JSON.parse(JSON.stringify(value));
const object = value => !!value && typeof value === 'object' && !Array.isArray(value);
const assert = (condition, message) => { if (!condition) throw new Error(`Invalid published snapshot: ${message}`); };
const validDate = value => { try { return addDays(value, 0) === value; } catch { return false; } };
const time = value => typeof value === 'string' && /^(?:[01]\d|2[0-3]):[0-5]\d$/.test(value);

/** Validate the public schedule document before storing or displaying a revision. */
export function validateDocument(document) {
  assert(object(document), 'document must be an object');
  assert(object(document.settings), 'settings are required');
  const settings = document.settings;
  assert(settings.anchorDate == null || validDate(settings.anchorDate), 'anchor date is invalid');
  assert(Number.isInteger(settings.anchorDay) && settings.anchorDay >= 1 && settings.anchorDay <= 7, 'anchor day must be 1–7');
  try { new Intl.DateTimeFormat('en', { timeZone: settings.timezone || 'America/Belize' }); } catch { throw new Error('Invalid published snapshot: timezone is invalid'); }
  assert(time(settings.regularDismissal), 'regular dismissal is invalid');
  assert(object(document.groups) && Object.keys(document.groups).length > 0, 'at least one group is required');
  for (const [group, days] of Object.entries(document.groups)) {
    assert(group.length > 0 && Array.isArray(days) && days.length === 7, `${group} needs seven cycle days`);
    days.forEach((lessons, index) => {
      assert(Array.isArray(lessons), `${group} day ${index + 1} must be an array`);
      let slots = 0;
      for (const lesson of lessons) {
        assert(object(lesson) && typeof lesson.subject === 'string' && lesson.subject.trim(), 'lesson needs a subject');
        assert(lesson.room == null || typeof lesson.room === 'string', 'lesson room must be text or null');
        assert(lesson.span == null || Number.isInteger(lesson.span) && lesson.span >= 1 && lesson.span <= 6, 'lesson span is invalid');
        slots += lesson.span || 1;
      }
      assert(slots <= (index === 6 ? 4 : 6), `${group} day ${index + 1} exceeds student sessions`);
    });
  }
  assert(document.archivedGroups === undefined || Array.isArray(document.archivedGroups), 'archived groups must be an array');
  const archivedGroups = document.archivedGroups || [];
  assert(Array.isArray(archivedGroups), 'archived groups must be an array');
  assert(archivedGroups.every(group => typeof group === 'string' && Object.hasOwn(document.groups, group)), 'archived groups must be registered group codes');
  assert(new Set(archivedGroups).size === archivedGroups.length, 'archived group codes must be unique');
  assert(archivedGroups.length < Object.keys(document.groups).length, 'at least one class group must remain active');
  assert(object(document.bellProfiles), 'bell profiles are required');
  assert(document.subjects == null || object(document.subjects), 'subject definitions must be an object');
  for (const key of ['regular', 'quick', 'half']) {
    const profile = document.bellProfiles[key];
    assert(object(profile) && Array.isArray(profile.slots) && profile.slots.length === (key === 'half' ? 4 : 6), `${key} bell profile has the wrong slot count`);
    let previousEnd = '';
    for (const slot of profile.slots) {
      assert(object(slot) && time(slot.start) && time(slot.end) && slot.start < slot.end, `${key} has an invalid lesson interval`);
      assert(slot.start >= previousEnd, `${key} lessons overlap`);
      previousEnd = slot.end;
    }
    assert(time(profile.dismissal) && profile.dismissal >= previousEnd, `${key} dismissal precedes lessons ending`);
  }
  assert(object(document.calendar || {}), 'calendar must be an object');
  for (const [date, entry] of Object.entries(document.calendar || {})) {
    assert(validDate(date) && object(entry), 'calendar entry is invalid');
    assert(['regular', 'holiday', 'async', 'event'].includes(entry.type), 'calendar type is invalid');
    assert(entry.bellProfile == null || ['regular', 'quick', 'half'].includes(entry.bellProfile), 'calendar bell profile is invalid');
  }
  for (const key of ['overrides', 'announcements', 'banners', 'teacherAssignments']) assert(document[key] == null || Array.isArray(document[key]), `${key} must be an array`);
  for (const override of document.overrides || []) {
    assert(object(override) && validDate(override.date) && Object.hasOwn(document.groups, override.group), 'substitute date or group is invalid');
    assert(Number.isInteger(override.session) && override.session >= 1 && override.session <= 6, 'substitute session is invalid');
    assert(!Object.hasOwn(override, 'subject') || typeof override.subject === 'string' && override.subject.trim(), 'substitute subject is invalid');
    assert(override.room == null || typeof override.room === 'string', 'substitute room is invalid');
  }
  // Only public document fields enter the offline cache, never adapter/session data.
  return clone(Object.fromEntries(['settings', 'groups', 'archivedGroups', 'subjects', 'bellProfiles', 'calendar', 'overrides', 'announcements', 'banners', 'teacherAssignments'].filter(key => Object.hasOwn(document, key)).map(key => [key, document[key]])));
}

export function validateSnapshot(snapshot) {
  assert(object(snapshot), 'snapshot must be an object');
  assert(Number.isSafeInteger(snapshot.revision) && snapshot.revision >= 0, 'revision must be a nonnegative integer');
  assert(snapshot.publishedAt == null || typeof snapshot.publishedAt === 'string' && Number.isFinite(Date.parse(snapshot.publishedAt)), 'published timestamp is invalid');
  return { document: validateDocument(snapshot.document), revision: snapshot.revision, publishedAt: snapshot.publishedAt || null };
}

function browserStorage() { try { return globalThis.localStorage || null; } catch { return null; } }
const message = error => error instanceof Error ? error.message : String(error);

/** Backend is injected. No auth tokens, sessions or credentials belong here. */
export function createRepository({ seed, backend = null, storage = browserStorage(), cacheKey = 'isa.published-schedule.v1' } = {}) {
  const seedSnapshot = validateSnapshot({ document: seed, revision: 0, publishedAt: null });
  let state = { ...seedSnapshot, source: 'seed', offline: false, error: null, cacheError: null };
  try {
    const encoded = storage?.getItem(cacheKey);
    if (encoded) {
      const cached = JSON.parse(encoded);
      if (cached.schemaVersion !== CACHE_SCHEMA_VERSION) throw new Error('Unsupported offline snapshot format');
      state = { ...validateSnapshot(cached.snapshot), source: 'cache', offline: false, error: null, cacheError: null };
    }
  } catch (error) { state.cacheError = message(error); }

  function cache(snapshot) {
    try {
      storage?.setItem(cacheKey, JSON.stringify({ schemaVersion: CACHE_SCHEMA_VERSION, snapshot }));
      return null;
    } catch (error) { return message(error); }
  }
  function adopt(snapshot) {
    if (snapshot.revision < state.revision) throw new Error('Published revision is older than the saved revision');
    const cacheError = cache(snapshot);
    state = { ...snapshot, source: 'remote', offline: false, error: null, cacheError };
  }

  return {
    getState: () => clone(state),
    async load() {
      if (!backend) return clone(state);
      try {
        const published = await backend.loadPublished({ knownRevision: state.revision });
        if (published) adopt(validateSnapshot(published));
        else state = { ...state, source: state.revision > 0 ? 'remote' : state.source, offline: false, error: null };
      } catch (error) { state = { ...state, offline: true, error: message(error) }; }
      return clone(state);
    },
    async publish(document, { expectedRevision = state.revision } = {}) {
      if (!backend?.publish) throw new Error('Publishing requires a connected, authorized backend');
      if (expectedRevision !== state.revision) throw new Error('Revision conflict: reload before publishing');
      const validated = validateDocument(document);
      // Nothing changes locally before the database confirms the complete revision.
      const published = validateSnapshot(await backend.publish(validated, { expectedRevision }));
      if (published.revision <= expectedRevision) throw new Error('Publishing did not advance the revision');
      adopt(published);
      return clone(state);
    }
  };
}
