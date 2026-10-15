import {noticeContent} from './notice-attachments.js';
import {teacherTimetableIntake,digitizedTeacherSchedulePreview} from './teacher-timetable.js';
import {digitizedTeacherLessons} from './teacher-schedule.js';
import {dateKey,addDays,resolveDate,getLessons,getDayStatus,nextSchoolDate,getWeek} from './schedule.js';
import {groupDisplayLessons} from './display-lessons.js';

export const escape = value => String(value ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const icon = name => `<i data-lucide="${escape(name)}" aria-hidden="true"></i>`;
export const time = value => { if(!value)return ''; const [h,m]=value.split(':').map(Number); return `${h%12||12}:${String(m).padStart(2,'0')} ${h<12?'AM':'PM'}`; };
export const dateLabel = date => new Intl.DateTimeFormat('en-BZ',{weekday:'long',month:'long',day:'numeric',timeZone:'UTC'}).format(new Date(date+'T12:00:00Z'));
export const empty = (title,body,name='calendar-days') => `<div class="empty">${icon(name)}<h3>${escape(title)}</h3><p>${escape(body)}</p></div>`;
export function subject(code,doc){const s=doc.subjects[code],name=s?.name||code;return `<button type="button" class="subject-code" data-tooltip="${escape(name)}" aria-label="${escape(name)}"><span class="subject-icon">${icon(s?.icon||'book-open')}</span><span class="subject-short">${escape(code)}</span><span class="subject-name" aria-hidden="true">${escape(name)}</span></button>`;}
export function lessonRow(l,doc,{current=false,finished=false}={}){
  const breaks=(l.segments||[]).slice(1).flatMap((segment,i)=>segment.start!==l.segments[i].end?[`Break ${time(l.segments[i].end)} – ${time(segment.start)}`]:[]);
  const changedRoom=l.substitution&&l.room!==l.original?.room;
  return `<div class="lesson-row ${current?'current':''} ${finished?'finished':''}" data-session="${l.session}"><time>${time(l.start)}<span class="time-end">${time(l.end)}</span></time><div class="lesson-main">${subject(l.subject,doc)}<div class="room"><span class="lesson-room">${l.room?escape(l.room):'Room not listed'}</span>${l.teacher?`<span class="lesson-teacher">${escape(l.teacher)}</span>`:''}</div>${l.teacherUnavailable?`<p class="teacher-unavailable">${icon('user-round-x')}Teacher unavailable</p>`:''}${l.span>1?`<span class="period-count">${l.span} periods</span>`:''}${breaks.length?`<span class="lesson-break">${breaks.map(escape).join(' · ')}</span>`:''}${l.note?`<p class="subtle">${escape(l.note)}</p>`:''}${changedRoom?`<p class="substitute-location">${icon('map-pin')}New room: ${l.room?escape(l.room):'Room not listed'}</p>`:''}</div>${l.substitution?`<span class="flair">${icon('repeat-2')}Substitute</span>`:current?'<span class="flair">Now</span>':''}</div>`;
}
export function agenda(date,group,doc,status=null){
  const r=resolveDate(date,doc),lessons=groupDisplayLessons(getLessons(date,group,doc),r.profile?.slots);
  if(!r.isCampusDay)return empty(r.label||({async:'Asynchronous day',event:'School event',holiday:'School holiday',weekend:'Weekend'}[r.type]),r.description||(r.isRollingDay?`Day ${r.cycleDay} counts in the cycle. No on-campus classes.`:'The rolling cycle pauses today.'));
  if(!lessons.length)return empty('Schedule not available','Select another class or ask the school to publish its timetable.');
  const finished=l=>!!status&&(['after','dismissal-prep'].includes(status.status)||(!status.current&&status.next&&l.session+l.span<=status.next.session)||status.current&&l.session+l.span<=status.current.session);
  const rows=lessons.map((l,i)=>{const previous=lessons[i-1],gap=previous&&previous.end!==l.start&&previous.session+previous.span-1===4;
    return {finished:finished(l),html:`${gap?`<div class="break-row">${icon('utensils')}Lunch · ${time(previous.end)} – ${time(l.start)}</div>`:''}${lessonRow(l,doc,{current:!!status?.current&&status.current.session>=l.session&&status.current.session<l.session+l.span,finished:finished(l)})}`};
  });
  const earlier=rows.filter(row=>row.finished),remaining=rows.filter(row=>!row.finished);
  return `<div class="agenda">${earlier.length?`<details class="earlier-lessons" open><summary>Earlier today · ${earlier.length} ${earlier.length===1?'lesson':'lessons'}</summary>${earlier.map(row=>row.html).join('')}</details>`:''}${remaining.map(row=>row.html).join('')}<div class="dismissal">${icon('log-out')}Dismissal ${time(r.profile.dismissal)}${r.bellProfile==='half'?' · Half day':r.bellProfile==='quick'?' · Quick exit':''}</div></div>`;
}
export function notices(doc,group=null){const now=Date.now(), rows=doc.announcements.filter(n=>n.approved&&Date.parse(n.publishedAt)<=now&&(!n.expiresAt||Date.parse(n.expiresAt)>now)&&(!group||n.audience==='school'||n.audience===group)).sort((a,b)=>Date.parse(b.publishedAt)-Date.parse(a.publishedAt));return rows.length?`<div class="notice-list" role="region" aria-label="Announcements" tabindex="0">${rows.map(n=>`<article class="notice-item"><div class="notice-icon">${icon('megaphone')}</div><div><div class="meta">${escape(n.audience==='school'?'Schoolwide':n.audience)} · ${escape(new Date(n.publishedAt).toLocaleDateString('en-BZ'))}</div><h3>${escape(n.title)}</h3>${noticeContent(n)}${n.subject?`<span class="badge">${escape(n.subject)}</span>`:''}</div></article>`).join('')}</div>`:empty('No announcements to show','School staff will publish approved announcements here.','megaphone');}
function live(status,doc){const current=status.current,next=status.next;let title=({before:'Before school',transition:'Time to move',lunch:'Lunch break','dismissal-prep':'Getting ready to leave'}[status.status])||'Now';return `<section class="live-strip" aria-label="Current school status"><div class="live-subject"><div class="meta">${escape(title)}</div>${current?`${subject(current.subject,doc)}<div class="room lesson-room">${current.room?escape(current.room):'Room not listed'}</div>`:`<h3>${status.status==='before'?'Start at '+time(next?.start):status.status==='dismissal-prep'?'Dismissal '+time(status.dismissal):title}</h3>`}</div><div class="live-timer"><strong id="timer-value">${Math.ceil(status.remainingSeconds/60)}</strong><span id="timer-unit">min ${current?'left':'to '+(status.status==='dismissal-prep'?'dismissal':'next class')}</span><small id="timer-detail">${current?'Ends '+time(current.end):next?'Next starts '+time(next.start):''}</small></div><div class="live-next"><div class="meta">${next?'Up next · '+time(next.start):'After this'}</div>${next?`${subject(next.subject,doc)}<div class="room lesson-room">${next.room?escape(next.room):'Room not listed'}</div>`:`<h3>${status.status==='dismissal-prep'?'School’s out soon':'Dismissal'}</h3><p>${time(status.dismissal)}</p>`}</div></section>`;}
export function weekView(date,group,doc){return `<div class="week-grid">${getWeek(date,doc).slice(0,5).map(r=>`<section class="week-day"><p>${escape(dateLabel(r.date))}</p><h3>${r.cycleDay?'Day '+r.cycleDay:'No classes'}</h3>${agenda(r.date,group,doc)}</section>`).join('')}</div>`;}
export function studentView({document:doc,group,view,showRooms=false,now=new Date()}){
  const today=dateKey(now),s=getDayStatus(today,group,doc,now),isClosed=['weekend','holiday','after'].includes(s.status),next=nextSchoolDate(today,doc);
  const displayed=view==='next'||(['today','week'].includes(view)&&isClosed)?next:today,r=resolveDate(displayed,doc);
  const title=view==='week'?'Your school week':view==='next'?'Next school day':view==='today'&&s.status==='weekend'?'It’s the weekend.':view==='today'&&s.status==='holiday'?(s.label||'School holiday'):view==='today'&&s.status==='after'?'School’s out.':'Today’s classes';
  return `<div class="student-schedule"><div class="schedule-toolbar"><nav class="view-tabs" aria-label="Schedule view">${[['today','Today'],['next','Next school day'],['week','Week']].map(([v,label])=>`<button data-view="${v}" class="${view===v?'active':''}" aria-pressed="${view===v}">${label}</button>`).join('')}</nav><label class="rooms-toggle" for="rooms-toggle"><input type="checkbox" id="rooms-toggle" data-show-rooms ${showRooms?'checked':''}>Show rooms</label></div><div class="schedule-layout"><div class="schedule-primary"><div class="page-heading"><div><h2>${escape(title)}</h2><p>${view==='week'?`Week of ${dateLabel(getWeek(displayed,doc)[0].date)}`:`${dateLabel(displayed)}${isClosed&&view==='today'?' · Back '+(r.type==='regular'?'on campus':'to schoolwork'):''}`}</p></div>${view!=='week'?`<span class="day-tag">${r.cycleDay?'Day '+r.cycleDay:'Cycle paused'}</span>`:''}</div>${view==='week'?weekView(displayed,group,doc):`${view==='today'&&['before','lesson','transition','lunch','dismissal-prep'].includes(s.status)&&s.isCampusDay?live(s,doc):''}<div class="section-heading"><h3>${displayed===today?'Today’s schedule':'Next school day'} · ${escape(group)}</h3><span class="subtle">${!r.isCampusDay?({async:'Asynchronous',event:'School event',holiday:'Holiday',weekend:'Weekend'}[r.type]||'No campus classes'):r.bellProfile==='half'?'Half day':r.bellProfile==='quick'?'Quick exit':'Regular day'}</span></div>${agenda(displayed,group,doc,displayed===today?s:null)}${view==='today'&&s.status==='after'?`<details class="today-replay"><summary>Replay today · Day ${s.cycleDay}</summary>${agenda(today,group,doc,s)}</details>`:''}`}</div><section class="schedule-secondary"><div class="section-heading"><h3>ISA Updates</h3><button class="button" data-route="updates">All updates ${icon('arrow-right')}</button></div>${notices(doc,group)}</section></div></div>`;
}
export function calendarView({document:doc,group,calendarDate,cycleDay,teacher=false}) {
  const r = resolveDate(calendarDate,doc);
  if(teacher)return `<div class="page-heading"><div><h2>School calendar</h2><p>School dates and changes to the school day.</p></div></div><div class="field"><label for="calendar-date">Choose a date</label><input id="calendar-date" type="date" value="${escape(calendarDate)}" data-calendar-date></div><section class="section"><h3>${dateLabel(calendarDate)}</h3><p>${escape(r.label||r.type)}${r.cycleDay?' · Day '+r.cycleDay:''}</p></section>${eventList(doc,calendarDate)}`;
  let patternDate = calendarDate;
  while ([0,6].includes(new Date(patternDate+'T12:00:00Z').getUTCDay())) patternDate=addDays(patternDate,1);
  const selectedDay = Math.max(1,Math.min(7,Number(cycleDay)||1));
  const patternDocument = {...doc,settings:{...doc.settings,anchorDate:patternDate,anchorDay:selectedDay},overrides:[],calendar:{}};
  return `<div class="page-heading"><div><h2>School calendar</h2><p>Dates, cycle days, and changes to the school day.</p></div></div><div class="toolbar"><div class="field"><label for="calendar-date">Choose a date</label><input id="calendar-date" type="date" value="${escape(calendarDate)}" data-calendar-date></div><div class="day-tag">${r.cycleDay?'Day '+r.cycleDay:'Cycle paused'}</div></div><h3>${dateLabel(calendarDate)}</h3>${agenda(calendarDate,group,doc)}<section class="section"><h3>Explore the 7-day cycle</h3><div class="cycle-picker"><label for="cycle-day">Viewing</label><select id="cycle-day" data-cycle-day>${Array.from({length:7},(_,i)=>`<option value="${i+1}" ${selectedDay===i+1?'selected':''}>Day ${i+1}</option>`).join('')}</select></div><p class="subtle">Regular cycle timetable. Date-specific substitutions are shown in the date view above.</p>${agenda(patternDate,group,patternDocument,null)}</section><section class="section"><h3>Upcoming events & holidays</h3>${eventList(doc,calendarDate)}</section>`;
}
export function eventList(doc,today){const dates=Object.keys(doc.calendar).filter(d=>d>=today).sort();return dates.length?`<div class="notice-list" role="region" aria-label="Announcements" tabindex="0">${dates.map(d=>{let e=doc.calendar[d];return `<article><div class="notice-icon">${icon(e.type==='holiday'?'sun':'calendar-days')}</div><div><div class="meta">${dateLabel(d)}</div><h3>${escape(e.label||e.type)}</h3><p>${escape(e.description)}</p><span class="badge">${e.type==='holiday'?'Cycle paused':e.type==='async'?'Asynchronous · cycle advances':e.type==='event'?'School event · cycle advances':e.bellProfile==='quick'?'Quick exit':e.bellProfile==='half'?'Half day':'Regular day'}</span></div></article>`}).join('')}</div>`:empty('No upcoming dates published','School holidays and events will appear here once added.');}
export function parentView(doc,group,today,interests=['events','dismissal','holidays']) {
  const selected=new Set(interests);
  // Holidays/closures stay visible for safety; elective events follow browser preferences.
  const calendar=Object.fromEntries(Object.entries(doc.calendar).filter(([date,e])=>(e.type==='holiday'&&(selected.has('holidays')||date<addDays(today,7)))||e.type==='async'||(e.type==='event'&&selected.has('events'))||(selected.has('dismissal')&&['quick','half'].includes(e.bellProfile))));
  if(selected.has('dismissal'))for(let i=0;i<21;i++){
    const date=addDays(today,i),r=resolveDate(date,doc);
    if(r.isCampusDay&&['quick','half'].includes(r.bellProfile)&&!calendar[date])calendar[date]={type:'regular',bellProfile:r.bellProfile,label:r.bellProfile==='half'?'Half day':'Quick exit',description:`Day ${r.cycleDay} · Dismissal ${time(r.profile.dismissal)}.`};
  }
  return `<div class="page-heading"><div><h2>School updates</h2><p>School notices and upcoming dates for ${escape(group)}.</p></div></div><h3>ISA Updates</h3>${notices(doc,group)}<section class="section"><div class="section-heading"><h3>Your upcoming dates</h3><button class="button" data-route="settings">Edit interests</button></div><p class="subtle" style="margin-bottom:16px">Early dismissal reminders cover the next three weeks. You’ll also see school closures in the next seven days.</p>${eventList({...doc,calendar},today)}</section><details><summary>View ${escape(group)}’s next school day</summary>${agenda(nextSchoolDate(today,doc),group,doc)}</details>`;
}
export function teacherView(doc,today,teacher,timetableUpload=null,approvalMessage='',availability='') {
  const r = resolveDate(today,doc), allAssignments = doc.teacherAssignments || [];
  const digitized=digitizedTeacherLessons(timetableUpload,today,doc);
  const assignments = allAssignments.filter(a=>a.teacher===teacher&&a.day===r.cycleDay).sort((a,b)=>a.session-b.session||a.group.localeCompare(b.group));
  let lessons;
  if (!r.isCampusDay) {
    lessons = agenda(today,'',doc);
    if (!allAssignments.length&&!digitized) lessons += `<p class="subtle" style="margin-top:15px">Teacher lesson assignments have not been published yet.</p>`;
  } else if (digitized) {
    const teacherDoc={...doc,subjects:{...doc.subjects,PLC:{name:'PLC / staff planning',icon:'users-round'}}};
    lessons=digitized.length?digitized.map(lesson=>`<section style="margin-bottom:20px"><h3>${escape(lesson.groups.length?lesson.groups.join(', '):lesson.subject==='PLC'?'Staff planning':'Combined groups')}</h3>${lessonRow(lesson,teacherDoc)}</section>`).join(''):empty('No teaching lessons listed today','No lessons are listed in your digitized timetable for this cycle day.','presentation');
  } else if (!allAssignments.length) {
    lessons = empty('Lessons haven’t been assigned yet','The teacher-to-lesson list is awaiting your school’s teacher assignments. Your timetable will appear here once it is published.','presentation');
  } else {
    const seen=new Set();
    const rows=assignments.map(a=>{
      const lesson=getLessons(today,a.group,doc).find(l=>a.session>=l.session&&a.session<l.session+l.span);
      const key=lesson?`${a.group}:${lesson.session}`:'';
      if (!lesson||seen.has(key)) return '';
      seen.add(key);
      return `<section style="margin-bottom:20px"><h3>${escape(a.group)}</h3>${lessonRow(lesson,doc)}</section>`;
    }).filter(Boolean);
    lessons=rows.length?rows.join(''):empty('No teaching lessons listed today','No lessons are assigned to your teaching profile for this cycle day. Ask school administration if something is missing.','presentation');
  }
  return `<div class="page-heading"><div><h2>Your teaching day</h2><p>In development</p><p>${dateLabel(today)}${r.cycleDay?' · Day '+r.cycleDay:''}</p></div></div>${approvalMessage?`<section class="section teacher-approval-message"><h3>Message from school leadership</h3><p style="white-space:pre-wrap">${escape(approvalMessage)}</p></section>`:''}${availability}${teacherTimetableIntake(timetableUpload)}${digitizedTeacherSchedulePreview(timetableUpload,doc)}${lessons}<section class="section"><h3>ISA Updates</h3>${notices(doc,'school')}</section>`;
}
