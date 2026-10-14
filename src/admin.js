import { resolveDate } from './schedule.js';

const esc = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
const clone = value => JSON.parse(JSON.stringify(value));
const id = prefix => `${prefix}-${globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(36).slice(2)}`}`;
const icon = name => `<i data-lucide="${esc(name)}" aria-hidden="true"></i>`;
const tabs = [
  ['schedule', 'Timetables', 'schedules.manage'], ['substitute', 'Substitutions', 'substitutions.manage'],
  ['calendar', 'Calendar', 'calendar.manage'], ['notices', 'Announcements', 'notices.submit'],
  ['banner', 'Banner', 'banners.manage'], ['subjects', 'Subjects', 'subjects.manage'],
  ['classes', 'Classes', 'classes.manage'], ['settings', 'Bell times & cycle', 'calendar.manage'],
  ['permissions', 'Permissions', 'members.manage'], ['integrations', 'ISA sync', 'members.manage']
];
const delegated = ['schedules.manage', 'classes.manage', 'subjects.manage', 'calendar.manage', 'substitutions.manage', 'notices.submit', 'notices.publish', 'banners.manage', 'chat.moderate', 'chat.emojis', 'chat.kick'];
const leading = member => !!member?.active && ['developer', 'principal'].includes(member.role);
const permits = (member, capability) => !!member?.active && (capability === 'members.manage' ? member.role === 'developer' : leading(member) || member.capabilities?.includes(capability));
const inScope = (member, group) => leading(member) || member?.groups?.includes('*') || member?.groups?.includes(group);
const globally = (member, capability) => permits(member, capability) && (leading(member) || member.groups?.includes('*'));
const option = (value, label, selected) => `<option value="${esc(value)}"${String(value) === String(selected) ? ' selected' : ''}>${esc(label)}</option>`;
const groupNames = doc => Object.keys(doc.groups || {}).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
const subjectOptions = (doc, selected) => Object.entries(doc.subjects || {}).map(([code, subject]) => option(code, `${code} — ${subject.name}`, selected)).join('');
const groupOptions = (doc, selected, member) => groupNames(doc).filter(group => !member || inScope(member, group)).map(group => option(group, group, selected)).join('');
const hidden = (name, value) => `<input type="hidden" name="${esc(name)}" value="${esc(value)}">`;
const timeLabel = value => {
  const [hour, minute] = String(value || '').split(':').map(Number);
  return Number.isFinite(hour) && Number.isFinite(minute) ? `${hour % 12 || 12}:${String(minute).padStart(2, '0')} ${hour < 12 ? 'AM' : 'PM'}` : 'not configured';
};
const field = (label, name, control, help = '') => `<div class="field"><label for="admin-${esc(name)}">${esc(label)}</label>${control}${help ? `<small>${esc(help)}</small>` : ''}</div>`;
const input = (name, value = '', type = 'text', extra = '') => `<input id="admin-${esc(name)}" name="${esc(name)}" type="${esc(type)}" value="${esc(value)}" ${extra}>`;
const select = (name, options, extra = '') => `<select id="admin-${esc(name)}" name="${esc(name)}" ${extra}>${options}</select>`;
const textarea = (name, value = '', extra = '') => `<textarea id="admin-${esc(name)}" name="${esc(name)}" ${extra}>${esc(value)}</textarea>`;
const submit = (text = 'Review changes') => `<div class="toolbar"><button type="submit" class="button primary">${icon('check')}${esc(text)}</button></div>`;
const form = (kind, content, enabled, metadata = '') => `<form class="editor-form" data-admin-kind="${esc(kind)}"${kind.startsWith('remove-') || ['class-archive', 'class-restore'].includes(kind) ? ' style="padding:0;background:transparent;margin-top:12px"' : ''}>${metadata}<fieldset style="border:0;padding:0;margin:0"${enabled ? '' : ' disabled'}>${content}</fieldset></form>`;
const empty = text => `<div class="empty"><p>${esc(text)}</p></div>`;

function timetable(doc, group, day, enabled) {
  let session = 1;
  const rows = (doc.groups?.[group]?.[day - 1] || []).map((lesson, index) => {
    const span = lesson.span || 1, from = session;
    session += span;
    return `<tr><td>${span === 1 ? `Session ${from}` : `Sessions ${from}–${session - 1}`}${hidden(`span-${index}`, span)}</td><td>${field('Subject', `subject-${index}`, select(`subject-${index}`, subjectOptions(doc, lesson.subject)))}</td><td>${field('Room', `room-${index}`, input(`room-${index}`, lesson.room ?? '', 'text', 'maxlength="40"'), 'Blank means room not listed.')}</td></tr>`;
  }).join('');
  return form('schedule', `<h3>${esc(group)} · Day ${day}</h3><p class="subtle">Edits change this repeating timetable. Use a substitution for a change on one date. Joined sessions remain joined.</p><div class="table-wrap" style="margin-top:20px"><table class="data-table"><thead><tr><th>Session</th><th>Subject</th><th>Room</th></tr></thead><tbody>${rows}</tbody></table></div>${day === 7 ? `<p class="subtle" style="margin-top:14px">Four student sessions, dismissal at ${esc(timeLabel(doc.bellProfiles.half.dismissal))}. Staff PLC is not a student lesson.</p>` : ''}${submit()}`, enabled,
    hidden('group', group) + hidden('day', day) + hidden('rowCount', doc.groups?.[group]?.[day - 1]?.length || 0));
}

function substitute(doc, group, today, enabled) {
  const overrides = (doc.overrides || []).filter(item => item.group === group).sort((a, b) => b.date.localeCompare(a.date));
  const contents = `<h3>A replacement for one lesson</h3><p class="subtle">The original timetable stays intact. The replacement applies only to the chosen class, date, and session.</p><div class="form-grid" style="margin-top:23px">
    ${field('School date', 'date', input('date', today, 'date', 'required'))}
    ${field('Session', 'session', select('session', Array.from({ length: 6 }, (_, i) => option(i + 1, `Session ${i + 1}`, 1)).join('')))}
    ${field('Replacement subject', 'subject', select('subject', subjectOptions(doc, 'SIL')))}
    ${field('New room', 'room', input('room', '', 'text', 'maxlength="40"'), 'Leave blank only when the room is not known.')}
    ${field('Substitute teacher', 'teacher', input('teacher', '', 'text', 'required maxlength="160"'))}
    ${field('Student note', 'note', input('note', '', 'text', 'maxlength="500"'), 'For example, bring your independent work.')}
    </div><div class="review-panel"><p>${icon('repeat-2')} Students will see a substitute flair, the new room, and teacher. Publishing another replacement for the same session replaces the previous one.</p></div>${submit()}`;
  return form('substitute', contents, enabled, hidden('group', group)) + `<section class="section"><h3>${esc(group)} replacements</h3>${overrides.length ? `<div class="table-wrap"><table class="data-table"><thead><tr><th>Date / session</th><th>Replacement</th><th>Action</th></tr></thead><tbody>${overrides.map(item => `<tr><td>${esc(item.date)} · ${esc(item.session)}</td><td><strong>${esc(item.subject)}</strong><div class="subtle">${esc(item.room || 'Room not listed')} · ${esc(item.teacher || 'Teacher not listed')}</div></td><td>${form('remove-substitute', '<button class="button secondary" type="submit">Review removal</button>', enabled, hidden('id', item.id))}</td></tr>`).join('')}</tbody></table></div>` : empty('No date-specific substitutions for this class.')}</section>`;
}

function calendar(doc, today, enabled) {
  const entries = Object.entries(doc.calendar || {}).sort(([a], [b]) => a.localeCompare(b));
  return form('calendar', `<h3>School arrangements</h3><p class="subtle">Holidays pause the cycle. Asynchronous days and events advance it. Bell times are a separate choice.</p><div class="form-grid" style="margin-top:23px">
    ${field('Date', 'date', input('date', today, 'date', 'required'))}
    ${field('Attendance arrangement', 'type', select('type', option('regular', 'Campus classes', 'regular') + option('holiday', 'Holiday / school closed') + option('async', 'Asynchronous work') + option('event', 'Parade / school event')))}
    ${field('Display label', 'label', input('label', '', 'text', 'maxlength="160"'), 'For example, Independence Day or Asynchronous learning.')}
    ${field('Bell times', 'bellProfile', select('bellProfile', option('', 'Automatic — half-day on Day 7', '') + option('regular', `Regular day · ${timeLabel(doc.bellProfiles.regular.dismissal)} dismissal`) + option('quick', `Quick Exit · ${timeLabel(doc.bellProfiles.quick.dismissal)} dismissal`) + option('half', `Half-day · ${timeLabel(doc.bellProfiles.half.dismissal)} dismissal`)))}
    ${field('Instructions for families', 'description', textarea('description', '', 'maxlength="2000"'))}
    </div>${submit()}`, enabled) + `<section class="section"><h3>Published calendar</h3>${entries.length ? `<div class="table-wrap"><table class="data-table"><thead><tr><th>Date</th><th>Arrangement</th><th>Cycle</th><th>Action</th></tr></thead><tbody>${entries.map(([date, entry]) => `<tr><td>${esc(date)}</td><td><strong>${esc(entry.label || entry.type)}</strong><div class="subtle">${esc(entry.description || '')}</div></td><td>${entry.type === 'holiday' ? 'Paused' : 'Advances'}</td><td>${form('remove-calendar', '<button class="button secondary" type="submit">Review removal</button>', enabled, hidden('date', date))}</td></tr>`).join('')}</tbody></table></div>` : empty('No school closures or special arrangements have been published yet.')}</section>`;
}

function notices(doc, member, group, enabled) {
  const canPublish = permits(member, 'notices.publish');
  const options = (inScope(member, 'school') ? option('school', 'Schoolwide', group) : '') + groupOptions(doc, group, member);
  const list = (doc.announcements || []).filter(item => inScope(member, item.audience));
  return form(canPublish ? 'notice-publish' : 'notice-draft', `<h3>${canPublish ? 'Publish an announcement' : 'Send an announcement for approval'}</h3><p class="subtle">Approved notices are public. Keep student information and private classroom work out of announcements.</p><div class="form-grid" style="margin-top:23px">
    ${field('Audience', 'audience', select('audience', options, 'required'))}
    ${field('Subject label (optional)', 'subject', select('subject', option('', 'No subject label', '') + subjectOptions(doc)))}
    ${field('Title', 'title', input('title', '', 'text', 'required maxlength="160"'))}
    ${field('Expires on (optional)', 'expires', input('expires', '', 'date'))}
    ${field('Announcement', 'body', textarea('body', '', 'required maxlength="10000"'))}
    </div>${submit(canPublish ? 'Review announcement' : 'Review draft')}`, enabled) + `<section class="section"><h3>Published notices</h3>${list.length ? `<div class="notice-list">${list.map(item => `<article class="notice-item"><span class="notice-icon">${icon('megaphone')}</span><div><p class="meta">${esc(item.audience === 'school' ? 'Schoolwide' : item.audience)}${item.subject ? ` · ${esc(item.subject)}` : ''}</p><h3>${esc(item.title)}</h3><p style="white-space:pre-wrap">${esc(item.body)}</p>${canPublish ? form('remove-notice', '<button class="button secondary" type="submit">Review removal</button>', true, hidden('id', item.id)) : ''}</div></article>`).join('')}</div>` : empty('No approved notices have been published yet.')}</section>`;
}

function banner(doc, enabled) {
  const active = (doc.banners || [])[0];
  return form('banner', `<h3>One clear schoolwide banner</h3><p class="subtle">Use the banner for an immediate school arrangement. Longer updates belong in announcements.</p><div class="form-grid" style="margin-top:23px">
    ${field('Message', 'text', textarea('text', active?.text || '', 'required maxlength="500"'))}
    ${field('Emphasis', 'tone', select('tone', option('info', 'Information', active?.tone || 'info') + option('warning', 'Schedule change', active?.tone) + option('urgent', 'Urgent notice', active?.tone)))}
    ${field('Starts on (optional)', 'starts', input('starts', active?.startsAt?.slice(0, 10) || '', 'date'))}
    ${field('Ends on (optional)', 'expires', input('expires', active?.expiresAt?.slice(0, 10) || '', 'date'))}
    </div>${submit()}`, enabled, hidden('id', active?.id || '')) + (active ? form('remove-banner', '<button type="submit" class="button secondary">Review banner removal</button>', enabled) : '');
}

function subjects(doc, enabled) {
  return form('subject', `<h3>Add a subject</h3><div class="form-grid">
    ${field('Short code', 'code', input('code', '', 'text', 'required maxlength="20"'), 'Use the code students already recognise.')}
    ${field('Full name', 'name', input('name', '', 'text', 'required maxlength="160"'))}
    ${field('Icon', 'icon', select('icon', ['book-open', 'calculator', 'flask-conical', 'palette', 'monitor-play', 'languages', 'dumbbell', 'hammer', 'sprout', 'briefcase-business', 'landmark', 'heart-handshake', 'wallet', 'users'].map(name => option(name, name.replaceAll('-', ' '), 'book-open')).join('')))}
    </div>${submit()}`, enabled) + `<section class="section"><h3>Subject names</h3><div class="table-wrap"><table class="data-table"><thead><tr><th>Code</th><th>Full name</th></tr></thead><tbody>${Object.entries(doc.subjects || {}).map(([code, subject]) => `<tr><td><strong>${esc(code)}</strong></td><td>${esc(subject.name)}</td></tr>`).join('')}</tbody></table></div></section>`;
}

function classes(doc, enabled, member) {
  const canCreate = enabled && globally(member, 'classes.manage') && permits(member, 'schedules.manage');
  return form('class-create', `<h3>Create a class</h3><p class="subtle">Copy an existing class as a starting point, then review all seven days before publishing the new timetable.</p><div class="form-grid" style="margin-top:23px">
    ${field('Class code', 'code', input('code', '', 'text', 'required pattern="[1-4][A-Z]{1,12}" maxlength="13"'), 'For example, 1C or 3HST. Years 1–4 and future subclass codes are supported.')}
    ${field('Timetable to copy', 'template', select('template', groupOptions(doc, '1A'), 'required'))}
    </div>${submit()}${canCreate ? '' : '<p class="subtle">Creating a class requires schoolwide class and timetable permissions.</p>'}`, canCreate) + `<section class="section"><h3>Classes</h3><div class="table-wrap"><table class="data-table"><thead><tr><th>Class</th><th>Status</th><th>Action</th></tr></thead><tbody>${groupNames(doc).map(group => {
      const archived = doc.archivedGroups?.includes(group);
      return `<tr><td><strong>${esc(group)}</strong></td><td>${archived ? 'Archived' : 'Active'}</td><td>${form(archived ? 'class-restore' : 'class-archive', `<button type="submit" class="button secondary">Review ${archived ? 'restore' : 'archive'}</button>`, enabled && inScope(member, group), hidden('group', group))}</td></tr>`;
    }).join('')}</tbody></table></div><p class="subtle" style="margin-top:12px">Archiving hides a class from student choices and preserves its timetable and previous publications.</p></section>`;
}

function settings(doc, enabled) {
  const profiles = Object.entries(doc.bellProfiles || {}).map(([key, profile]) => `<section class="section"><h3>${esc({ regular: 'Regular day', quick: 'Quick Exit', half: 'Half-day' }[key] || key)}</h3><div class="form-grid">${profile.slots.map((slot, i) => field(`Session ${i + 1} start`, `${key}-start-${i}`, input(`${key}-start-${i}`, slot.start, 'time', 'required')) + field(`Session ${i + 1} end`, `${key}-end-${i}`, input(`${key}-end-${i}`, slot.end, 'time', 'required'))).join('')}${field('Dismissal', `${key}-dismissal`, input(`${key}-dismissal`, profile.dismissal, 'time', 'required'))}</div></section>`).join('');
  return form('settings', `<h3>Cycle anchor</h3><p class="subtle">The confirmed anchor is Tuesday, 13 October 2026, Day 6. Changing this recalculates dates across the school.</p><div class="form-grid" style="margin-top:23px">${field('Known school date', 'anchorDate', input('anchorDate', doc.settings?.anchorDate || '', 'date', 'required'))}${field('Cycle day on this date', 'anchorDay', select('anchorDay', Array.from({ length: 7 }, (_, i) => option(i + 1, `Day ${i + 1}`, doc.settings?.anchorDay)).join('')))}</div>${profiles}${submit()}`, enabled);
}

const permissionLabels = {'schedules.manage':'Edit timetables','classes.manage':'Create and archive classes','subjects.manage':'Manage subjects','calendar.manage':'Edit holidays, bell times and cycle','substitutions.manage':'Set substitutes','notices.submit':'Submit announcements','notices.publish':'Publish announcements','banners.manage':'Set the school banner','chat.moderate':'Moderate schoolwide messages','chat.emojis':'Upload schoolwide emojis for review','chat.kick':'Remove members from schoolwide chat'};
function permissions(doc, enabled, account = null) {
  const current=account||{role:'codeveloper',groups:['*'],capabilities:[],active:true};
  return form('member', `<h3>Account permissions</h3><p class="subtle">Find an existing account by email or UID. Only Developers can change access. Award badges do not grant permissions.</p><div class="form-grid" style="margin-top:23px">
    ${field('Email or account UID', 'userId', input('userId', account?.user_id||'', 'text', 'required maxlength="320" autocomplete="off"'), account?.email||'The person must already have an account.')}
    <div class="field"><button class="button secondary" type="button" data-member-lookup>Find account</button></div>
    ${field('Role', 'role', select('role', ['codeveloper','developer','principal','teacher'].map(role=>option(role,({codeveloper:'Admin - selected permissions',developer:'Developer - full access',principal:'Principal / Vice Principal',teacher:'Teacher'})[role],current.role)).join('')))}
    ${field('Class scope', 'groups', input('groups', (current.groups||[]).join(', ')), 'Use * for schoolwide access, or comma-separated class codes. Teachers need specific classes.')}
    ${field('Access', 'active', select('active', option('true','Grant / keep access',String(current.active))+option('false','Revoke staff and moderator access',String(current.active))))}
    </div><section class="section"><h3>Choose permissions</h3><p class="subtle">Admins receive only the checked permissions. Developer and Principal roles have full school publishing rights. Teachers receive the checked permissions within their assigned classes.</p><div class="permission-list" style="margin-top:16px">${delegated.map(cap=>`<label><span>${esc(permissionLabels[cap])}</span><input type="checkbox" name="capabilities" value="${esc(cap)}" ${current.capabilities?.includes(cap)?'checked':''}></label>`).join('')}</div></section>${submit('Review access change')}`, enabled);
}

export function renderAdmin({ document: doc, membership, tab = 'schedule', group = '3CS', day = 1, today, permissionAccount = null }) {
  if (!membership?.active) return empty('Sign in with an approved staff account to access school administration.');
  const scopedGroups = groupNames(doc).filter(code => inScope(membership, code));
  if (!scopedGroups.includes(group)) group = scopedGroups[0] || groupNames(doc)[0];
  day = Math.max(1, Math.min(7, Number(day) || 1));
  const tabAllowed = ([key, , capability]) => key === 'permissions' ? membership.role === 'developer' : key === 'notices' ? permits(membership, 'notices.submit') || permits(membership, 'notices.publish') : ['calendar', 'banner', 'subjects', 'settings'].includes(key) ? globally(membership, capability) : permits(membership, capability) && scopedGroups.length > 0;
  if (!tabs.some(item => item[0] === tab)) tab = 'schedule';
  if (!tabAllowed(tabs.find(item => item[0] === tab))) tab = tabs.find(tabAllowed)?.[0] || 'schedule';
  const enabled = tabAllowed(tabs.find(item => item[0] === tab));
  const chooseGroup = ['schedule', 'substitute'].includes(tab);
  const renderers = { schedule: () => timetable(doc, group, day, enabled), substitute: () => substitute(doc, group, today, enabled), calendar: () => calendar(doc, today, enabled), notices: () => notices(doc, membership, group, enabled), banner: () => banner(doc, enabled), subjects: () => subjects(doc, enabled), classes: () => classes(doc, enabled, membership), settings: () => settings(doc, enabled), permissions: () => permissions(doc, enabled, permissionAccount), integrations: () => `<section class="section"><h3>Connect ISA Updates</h3><p>Automatically publish ISA Updates from the selected Classroom course. This connection cannot edit schedules or staff permissions.</p><form id="isa-sync-config" class="editor-form"><div class="field"><label for="isa-course-id">Classroom course ID</label><input id="isa-course-id" name="course" value="780277588874" required pattern="[0-9]{1,32}" autocomplete="off"><small>Use the numeric course ID, not the classroom join code.</small></div><div class="field"><label for="isa-sync-token">Private sync token</label><input id="isa-sync-token" name="token" type="password" required minlength="32" maxlength="256" autocomplete="new-password"><small>Use the same long random token in Apps Script’s ISA_SYNC_TOKEN property. Keep it out of messages and screenshots.</small></div><label class="settings-room-choice"><input type="checkbox" name="autoPublish" checked>Automatically publish posts to the public ISA Updates feed</label><p class="subtle">New and edited Classroom announcements will be readable publicly. Attachments keep their original Google access rules.</p><button class="button primary">Save ISA Updates connection</button></form></section>` };
  return `<div class="page-heading"><div><h2>School administration</h2><p>Review each change before it reaches students and families.</p></div><span class="badge">${esc({ developer: 'Developer', principal: 'Principal / Vice Principal', teacher: 'Teacher', codeveloper: 'Admin / Codeveloper' }[membership.role] || membership.role)}</span></div>
    <nav class="editor-tabs" aria-label="Administration areas">${tabs.map(item => `<button type="button" data-action="admin-tab" data-admin-tab="${item[0]}" data-tab="${item[0]}" class="${item[0] === tab ? 'active' : ''}"${tabAllowed(item) ? '' : ' disabled'}>${item[1]}</button>`).join('')}</nav>
    ${chooseGroup ? `<div class="toolbar"><div class="class-picker"><label for="admin-group-picker">Class</label><select id="admin-group-picker" data-action="admin-group" data-admin-group>${groupOptions(doc, group, membership)}</select></div>${tab === 'schedule' ? `<div class="class-picker"><label for="admin-day-picker">Cycle day</label><select id="admin-day-picker" data-action="admin-day" data-admin-day>${Array.from({ length: 7 }, (_, i) => option(i + 1, `Day ${i + 1}`, day)).join('')}</select></div>` : ''}</div>` : ''}
    ${enabled ? '' : '<div class="warning">Your account has no permission to edit this area. Contact the school developer to request access.</div>'}${renderers[tab]()}`;
}

function dataFor(form) { return form instanceof FormData ? form : new FormData(form); }
function required(data, name) {
  const value = String(data.get(name) || '').trim();
  if (!value) throw new Error(`Enter ${name.replaceAll('-', ' ')}.`);
  return value;
}
function validDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) !== value) throw new Error('Choose a valid calendar date.');
  return value;
}
function clock(value) {
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(value)) throw new Error('Use a valid bell time.');
  return value;
}
const atStart = date => `${validDate(date)}T00:00:00-06:00`;
const atEnd = date => `${validDate(date)}T23:59:59-06:00`;

/** Returns a proposal only. Authentication, review, and publication belong to the controller. */
export function handleAdminSubmit(formElement, original) {
  const data = dataFor(formElement);
  const action = formElement?.dataset?.adminKind || data.get('adminKind');
  const doc = clone(original);
  const value = name => String(data.get(name) || '').trim();
  const group = value('group');
  let summary = '';
  switch (action) {
    case 'schedule': {
      const day = Number(value('day')), count = Number(value('rowCount'));
      const existing = doc.groups?.[group]?.[day - 1];
      if (!existing || existing.length !== count) throw new Error('This timetable changed. Reload before editing.');
      doc.groups[group][day - 1] = existing.map((lesson, i) => {
        const subject = required(data, `subject-${i}`);
        if (!Object.hasOwn(doc.subjects, subject)) throw new Error('Choose a registered subject.');
        return { subject, room: value(`room-${i}`) || null, ...(lesson.span ? { span: lesson.span } : {}) };
      });
      summary = `Update ${group} Day ${day}. This changes its repeating timetable.`;
      break;
    }
    case 'substitute': {
      const date = validDate(required(data, 'date')), session = Number(value('session'));
      const resolved = resolveDate(date, doc);
      if (!doc.groups[group] || !resolved.isCampusDay || !resolved.cycleDay) throw new Error('Choose a campus school date and an existing class.');
      const max = Math.min(resolved.profile.slots.length, resolved.cycleDay === 7 ? 4 : 6);
      if (!Number.isInteger(session) || session < 1 || session > max) throw new Error(`This date has only ${max} student sessions.`);
      const subject = required(data, 'subject');
      if (!doc.subjects[subject]) throw new Error('Choose a registered subject.');
      const replacement = { id: id('sub'), date, group, session, subject, room: value('room') || null, teacher: required(data, 'teacher'), note: value('note') };
      doc.overrides = (doc.overrides || []).filter(item => !(item.date === date && item.group === group && Number(item.session) === session));
      doc.overrides.push(replacement);
      summary = `Replace ${group}, ${date}, Session ${session} with ${subject}. Room: ${replacement.room || 'not listed'}. Teacher: ${replacement.teacher}.`;
      break;
    }
    case 'remove-substitute':
      doc.overrides = (doc.overrides || []).filter(item => item.id !== value('id')); summary = 'Remove this dated replacement and restore the original lesson.'; break;
    case 'calendar': {
      const date = validDate(required(data, 'date')), type = value('type'), profile = value('bellProfile');
      if (!['regular', 'holiday', 'async', 'event'].includes(type)) throw new Error('Choose a school arrangement.');
      if (profile && !['regular', 'quick', 'half'].includes(profile)) throw new Error('Choose valid bell times.');
      if (date === doc.settings.anchorDate && type === 'holiday') throw new Error('The cycle anchor must remain a rolling school date. Change the anchor first.');
      doc.calendar[date] = { type, label: value('label'), description: value('description'), ...(profile ? { bellProfile: profile } : {}) };
      summary = `Set ${date} to ${type}. ${type === 'holiday' ? 'The cycle pauses and later school dates may shift.' : 'The cycle advances.'}${profile ? ` Bell times: ${profile}.` : ' Day 7 uses half-day bells automatically.'}`;
      break;
    }
    case 'remove-calendar': delete doc.calendar[value('date')]; summary = `Remove the special arrangement on ${value('date')}. Weekday classes and automatic bells will apply; later cycle dates may change.`; break;
    case 'notice-publish':
    case 'notice-draft': {
      const audience = required(data, 'audience');
      if (audience !== 'school' && !doc.groups[audience]) throw new Error('Choose an existing announcement audience.');
      const payload = { title: required(data, 'title'), body: required(data, 'body'), audience,
        ...(value('subject') ? { subject: value('subject') } : {}), ...(value('expires') ? { expiresAt: atEnd(value('expires')) } : {}) };
      if (payload.subject && !doc.subjects[payload.subject]) throw new Error('Choose a registered subject label.');
      if (payload.expiresAt && new Date(payload.expiresAt) <= new Date()) throw new Error('Announcement expiry must be in the future.');
      if (action === 'notice-draft') return { document: original, kind: 'notice', payload, summary: `Send “${payload.title}” for ${audience} to school reviewers. It stays private until approved.` };
      doc.announcements.push({ id: id('notice'), ...payload, approved: true, publishedAt: new Date().toISOString() });
      summary = `Publish “${payload.title}” for ${audience === 'school' ? 'the whole school' : audience}. Approved announcements are public.`;
      break;
    }
    case 'remove-notice': doc.announcements = doc.announcements.filter(item => item.id !== value('id')); summary = 'Remove this announcement from the public feed.'; break;
    case 'banner': {
      const tone = value('tone');
      if (!['info', 'warning', 'urgent'].includes(tone)) throw new Error('Choose a banner emphasis.');
      const banner = { id: value('id') || id('banner'), text: required(data, 'text'), tone,
        ...(value('starts') ? { startsAt: atStart(value('starts')) } : {}), ...(value('expires') ? { expiresAt: atEnd(value('expires')) } : {}) };
      if (banner.startsAt && banner.expiresAt && new Date(banner.expiresAt) <= new Date(banner.startsAt)) throw new Error('The banner must end after it starts.');
      doc.banners = [banner]; summary = `Show the schoolwide banner: “${banner.text}”.`; break;
    }
    case 'remove-banner': doc.banners = []; summary = 'Remove the schoolwide banner.'; break;
    case 'subject': {
      const code = required(data, 'code'), name = required(data, 'name'), chosenIcon = value('icon');
      if (code.length > 20 || !/^[A-Za-z0-9& -]+$/.test(code)) throw new Error('Use a short subject code with letters, numbers, spaces, or &.');
      if (doc.subjects[code]) throw new Error('This subject code already exists.');
      if (!/^[a-z0-9-]{1,60}$/.test(chosenIcon)) throw new Error('Choose a valid subject icon.');
      doc.subjects[code] = { name, icon: chosenIcon }; summary = `Add ${code}: ${name}.`; break;
    }
    case 'class-create': {
      const code = required(data, 'code').toUpperCase(), template = required(data, 'template');
      if (!/^[1-4][A-Z]{1,12}$/.test(code)) throw new Error('Class codes use a year from 1–4 followed by letters.');
      if (doc.groups[code]) throw new Error('That class already exists.');
      if (!doc.groups[template]) throw new Error('Choose an existing timetable to copy.');
      doc.groups[code] = clone(doc.groups[template]); summary = `Create ${code} using ${template}'s seven-day timetable. Review its subjects and rooms before students use it.`; break;
    }
    case 'class-archive':
    case 'class-restore': {
      if (!doc.groups[group]) throw new Error('Choose an existing class.');
      const archived = new Set(doc.archivedGroups || []);
      if (action === 'class-archive') archived.add(group); else archived.delete(group);
      if (archived.size === Object.keys(doc.groups).length) throw new Error('At least one class must remain active.');
      doc.archivedGroups = [...archived]; summary = `${action === 'class-archive' ? 'Archive' : 'Restore'} ${group}. Its timetable and publication history stay preserved.`; break;
    }
    case 'settings': {
      const anchorDate = validDate(required(data, 'anchorDate')), anchorDay = Number(value('anchorDay'));
      const weekday = new Date(`${anchorDate}T12:00:00Z`).getUTCDay();
      if (weekday === 0 || weekday === 6 || doc.calendar[anchorDate]?.type === 'holiday') throw new Error('Choose a rolling weekday for the anchor.');
      if (!Number.isInteger(anchorDay) || anchorDay < 1 || anchorDay > 7) throw new Error('Choose a cycle day from 1–7.');
      for (const [key, profile] of Object.entries(doc.bellProfiles)) {
        let previous = '00:00';
        const slots = profile.slots.map((_, i) => {
          const start = clock(required(data, `${key}-start-${i}`)), end = clock(required(data, `${key}-end-${i}`));
          if (start < previous || end <= start) throw new Error(`${key} bells must be in order without overlapping.`);
          previous = end; return { start, end };
        });
        const dismissal = clock(required(data, `${key}-dismissal`));
        if (dismissal < previous) throw new Error('Dismissal cannot be before the last lesson ends.');
        doc.bellProfiles[key] = { slots, dismissal };
      }
      doc.settings = { ...doc.settings, anchorDate, anchorDay, regularDismissal: doc.bellProfiles.regular.dismissal };
      summary = `Update the cycle anchor to ${anchorDate}, Day ${anchorDay}, and the school bell times. Existing dates and countdowns will recalculate.`; break;
    }
    case 'member': {
      const userId = required(data, 'userId'), role = value('role'), capabilities = data.getAll('capabilities').map(String), groups = value('groups').split(',').map(item => item.trim()).filter(Boolean);
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(userId) && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(userId)) throw new Error('Enter an existing account email or UID.');
      if (!['developer', 'principal', 'teacher', 'codeveloper'].includes(role)) throw new Error('Choose a valid staff role.');
      if (capabilities.some(cap => !delegated.includes(cap))) throw new Error('Choose supported capabilities.');
      if (groups.some(code => code !== '*' && !doc.groups[code])) throw new Error('Use existing class codes for scopes.');
      if (role === 'teacher' && groups.includes('*')) throw new Error('Teachers require specific class scopes.');
      const payload = { userId, role, capabilities, groups: [...new Set(groups)], active: value('active') !== 'false' };
      return { document: original, kind: 'member', payload, summary: `Set account ${userId} to ${role}, ${payload.active ? 'active' : 'paused'}. Scope: ${groups.join(', ') || 'none'}.` };
    }
    default: throw new Error('Unknown administration action.');
  }
  return { document: doc, summary, kind: 'document' };
}
