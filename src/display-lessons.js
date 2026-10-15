/** Presentation grouping leaves the schedule engine and its countdowns untouched. */
export function groupDisplayLessons(lessons, slots = []) {
  const rows = [];
  for (const lesson of lessons) {
    const segments = Array.from({length: lesson.span || 1}, (_, index) => ({
      session: lesson.session + index,
      start: slots[lesson.session + index - 1]?.start || lesson.start,
      end: slots[lesson.session + index - 1]?.end || lesson.end
    }));
    // Even an existing multi-session record must not visually swallow lunch.
    const split = segments.findIndex(segment => segment.session === 5);
    const chunks = split > 0 ? [segments.slice(0, split), segments.slice(split)] : [segments];
    for (const chunk of chunks) {
      const row = {...lesson, session: chunk[0].session, span: chunk.length,
        start: chunk[0].start, end: chunk.at(-1).end, segments: chunk};
      const previous = rows.at(-1);
      const adjacent = previous && previous.session + previous.span === row.session;
      const crossesLunch = previous && previous.session + previous.span - 1 === 4;
      const matching = previous && ['subject', 'room', 'teacher', 'note','teacherUnavailable'].every(key => (previous[key] ?? '') === (row[key] ?? ''));
      if (adjacent && !crossesLunch && matching && !previous.substitution && !row.substitution) {
        previous.span += row.span;
        previous.end = row.end;
        previous.segments.push(...chunk);
      } else rows.push(row);
    }
  }
  return rows;
}
