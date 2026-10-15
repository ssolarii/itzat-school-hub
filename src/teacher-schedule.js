import {resolveDate} from './schedule.js';

export function digitizedTeacherLessons(upload,date,document){
  const resolved=resolveDate(date,document),schedule=upload?.status==='digitized'&&upload.digitized_schedule;
  if(!schedule||schedule.version!==1||!Array.isArray(schedule.entries))return null;
  if(!resolved.isCampusDay)return [];
  return schedule.entries.filter(entry=>entry.day===resolved.cycleDay).flatMap(entry=>{
    const span=entry.span||1,staff=entry.subject==='PLC',slots=staff?document.bellProfiles.regular.slots:resolved.profile?.slots;
    if(!Number.isInteger(entry.session)||entry.session<1||!slots?.[entry.session+span-2])return [];
    const segments=slots.slice(entry.session-1,entry.session+span-1);
    return [{...entry,span,start:segments[0].start,end:segments.at(-1).end,segments,groups:Array.isArray(entry.groups)?entry.groups:[],note:entry.note||''}];
  }).sort((a,b)=>a.session-b.session);
}
