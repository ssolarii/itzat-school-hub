const DAY = 86_400_000;
const mod = (n, d) => ((n % d) + d) % d;

function dateNumber(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new RangeError('Expected an ISO calendar date');
  const stamp = Date.parse(`${value}T00:00:00Z`);
  if (!Number.isFinite(stamp) || new Date(stamp).toISOString().slice(0, 10) !== value) throw new RangeError('Invalid calendar date');
  return stamp / DAY;
}

/** Calendar dates and clock readings are always interpreted in the school timezone. */
export function dateKey(now = new Date(), timezone = 'America/Belize') {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: timezone, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(new Date(now));
  const values = Object.fromEntries(parts.map(p => [p.type, p.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

export function addDays(date, count) {
  if (!Number.isInteger(count)) throw new RangeError('Day increment must be an integer');
  return new Date((dateNumber(date) + count) * DAY).toISOString().slice(0, 10);
}

function calendarType(date, document) {
  const weekday = mod(dateNumber(date) + 4, 7);
  if (weekday === 0 || weekday === 6) return 'weekend';
  return document.calendar?.[date]?.type || 'regular';
}

const rolling = type => ['regular', 'async', 'event'].includes(type);

/** Anchor is a known rolling school date; closed dates never consume cycle days. */
export function cycleDayFor(date, document) {
  dateNumber(date);
  const { anchorDate, anchorDay = 1 } = document.settings || {};
  if (!anchorDate || !rolling(calendarType(date, document))) return null;
  if (!Number.isInteger(anchorDay) || anchorDay < 1 || anchorDay > 7) return null;
  if (!rolling(calendarType(anchorDate, document))) return null;
  const target = dateNumber(date), anchor = dateNumber(anchorDate);
  let distance = 0;
  if (target >= anchor) {
    for (let day = addDays(anchorDate, 1); dateNumber(day) <= target; day = addDays(day, 1)) if (rolling(calendarType(day, document))) distance++;
  } else {
    for (let day = date; dateNumber(day) < anchor; day = addDays(day, 1)) if (rolling(calendarType(day, document))) distance--;
  }
  return mod(anchorDay - 1 + distance, 7) + 1;
}

export function resolveDate(date, document) {
  const type = calendarType(date, document);
  const entry = document.calendar?.[date] || {};
  const cycleDay = cycleDayFor(date, document);
  const requestedProfile = entry.bellProfile || (cycleDay === 7 ? 'half' : 'regular');
  const bellProfile = document.bellProfiles?.[requestedProfile] ? requestedProfile : 'regular';
  return { date, type, label: entry.label || '', description: entry.description || '', cycleDay, bellProfile,
    profile: document.bellProfiles?.[bellProfile] || null, isRollingDay: rolling(type), isCampusDay: type === 'regular' };
}

/** Next rolling date includes async/event days unless explicitly excluded. */
export function nextSchoolDate(date, document, { includeAsync = true, includeEvents = true } = {}) {
  for (let i = 1; i <= 3660; i++) {
    const candidate = addDays(date, i), type = calendarType(candidate, document);
    if (type === 'regular' || (type === 'async' && includeAsync) || (type === 'event' && includeEvents)) return candidate;
  }
  return null;
}

export function nextCampusDate(date, document) {
  return nextSchoolDate(date, document, { includeAsync: false, includeEvents: false });
}

/** Returns student lessons only. PLC remains a staff planning activity. */
export function getLessons(date, group, document) {
  const resolved = resolveDate(date, document);
  if (!resolved.isCampusDay || !resolved.cycleDay || !resolved.profile) return [];
  const base = document.groups?.[group]?.[resolved.cycleDay - 1] || [];
  const slots = resolved.profile.slots || [];
  const limit = Math.min(slots.length, resolved.cycleDay === 7 ? 4 : slots.length);
  const expanded = [];
  let session = 1;
  base.forEach((lesson, baseIndex) => {
    const span = Math.max(1, Math.trunc(lesson.span || 1));
    for (let offset = 0; offset < span && session + offset <= limit; offset++) {
      const slot = session + offset;
      if (lesson.subject === 'PLC') continue;
      const override = (document.overrides || []).filter(o => o.date === date && o.group === group && Number(o.session) === slot).at(-1);
      const original = { subject: lesson.subject, room: lesson.room ?? null, teacher: lesson.teacher ?? null };
      const teacherUnavailable=!(override?.teacher&&override.teacher!==lesson.teacher)&&(document.teacherCheckouts||[]).some(checkout=>checkout.date===date&&checkout.class_group===group&&checkout.subject===lesson.subject&&(!checkout.cycle_day||checkout.cycle_day===resolved.cycleDay)&&checkout.session===slot);
      expanded.push({ ...lesson, ...override, session: slot, span: 1, room: override && Object.hasOwn(override, 'room') ? override.room : lesson.room ?? null,
        ...(teacherUnavailable?{teacherUnavailable:true}:{}),
        teacher: override?.teacher ?? lesson.teacher ?? null, note: override?.note || lesson.note || '', substitution: !!override,
        original: override ? original : null, start: slots[slot - 1].start, end: slots[slot - 1].end, _base: baseIndex, _override: override });
    }
    session += span;
  });
  const merged = [];
  for (const lesson of expanded) {
    const previous = merged.at(-1);
    if (previous && !lesson._override && !previous._override && previous.teacherUnavailable===lesson.teacherUnavailable && previous._base === lesson._base && previous.session + previous.span === lesson.session) {
      previous.span++; previous.end = lesson.end;
    } else merged.push({ ...lesson });
  }
  return merged.map(({ _base, _override, ...lesson }) => lesson);
}

function seconds(value) {
  const match = /^(\d{2}):(\d{2})(?::(\d{2}))?$/.exec(value || '');
  if (!match || +match[1] > 23 || +match[2] > 59 || +(match[3] || 0) > 59) throw new RangeError('Expected a valid 24-hour bell time');
  return +match[1] * 3600 + +match[2] * 60 + +(match[3] || 0);
}

function clockSeconds(now, timezone) {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: timezone, hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' }).formatToParts(new Date(now));
  const values = Object.fromEntries(parts.map(p => [p.type, p.value]));
  return +values.hour * 3600 + +values.minute * 60 + +values.second;
}

export function getDayStatus(date, group, document, now = new Date()) {
  const resolved = resolveDate(date, document);
  const lessons = getLessons(date, group, document);
  const dismissal = resolved.profile?.dismissal || document.settings?.regularDismissal || null;
  const result = { ...resolved, lessons, status: resolved.type, current: null, next: null, elapsedSeconds: 0, remainingSeconds: 0, durationSeconds: 0, dismissal };
  if (!resolved.isCampusDay) return result;
  if (!resolved.cycleDay || !resolved.profile || !lessons.length) return { ...result, status: 'unconfigured' };
  const timezone = document.settings?.timezone || 'America/Belize';
  const today = dateKey(now, timezone);
  const currentClock = date < today ? 86400 : date > today ? 0 : clockSeconds(now, timezone);
  const current = lessons.find(lesson => currentClock >= seconds(lesson.start) && currentClock < seconds(lesson.end));
  if (current) {
    const elapsedSeconds = currentClock - seconds(current.start), remainingSeconds = seconds(current.end) - currentClock;
    return { ...result, status: 'lesson', current, next: lessons.find(l => l.session > current.session + current.span - 1) || null,
      elapsedSeconds, remainingSeconds, durationSeconds: elapsedSeconds + remainingSeconds };
  }
  const next = lessons.find(lesson => seconds(lesson.start) > currentClock) || null;
  if (next) {
    const before = currentClock < seconds(lessons[0].start);
    const previous = lessons.filter(l => seconds(l.end) <= currentClock).at(-1);
    // Lunch follows session four; its timing comes from the selected date's profile.
    const lunch = !before && previous && previous.session + previous.span - 1 === 4;
    const start = before ? 0 : seconds(previous.end);
    return { ...result, status: before ? 'before' : lunch ? 'lunch' : 'transition', next,
      elapsedSeconds: before ? 0 : currentClock - start, remainingSeconds: seconds(next.start) - currentClock,
      durationSeconds: before ? 0 : seconds(next.start) - start };
  }
  const dismissAt = dismissal ? seconds(dismissal) : seconds(lessons.at(-1).end);
  if (currentClock < dismissAt) return { ...result, status: 'dismissal-prep', remainingSeconds: dismissAt - currentClock,
    elapsedSeconds: currentClock - seconds(lessons.at(-1).end), durationSeconds: dismissAt - seconds(lessons.at(-1).end) };
  return { ...result, status: 'after' };
}

/** A calendar week includes closed dates so holiday information remains visible. */
export function getWeek(date, document) {
  const weekday = mod(dateNumber(date) + 3, 7);
  const monday = addDays(date, -weekday);
  return Array.from({ length: 7 }, (_, index) => resolveDate(addDays(monday, index), document));
}
