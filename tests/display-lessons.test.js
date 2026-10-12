import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {groupDisplayLessons} from '../src/display-lessons.js';
import {getLessons,getDayStatus} from '../src/schedule.js';
import {agenda,studentView} from '../src/views.js';

const doc=JSON.parse(readFileSync(new URL('../school-data.json',import.meta.url),'utf8'));
const slots=doc.bellProfiles.regular.slots;
const lesson=(session,extra={})=>({session,span:1,subject:'QR',room:'D2',teacher:null,note:'',start:slots[session-1].start,end:slots[session-1].end,...extra});

test('matching separately entered lessons group without mutating engine lessons',()=>{
  const input=[lesson(2),lesson(3)],before=structuredClone(input),rows=groupDisplayLessons(input,slots);
  assert.equal(rows.length,1);assert.equal(rows[0].span,2);
  assert.deepEqual(rows[0].segments,[{session:2,start:'09:00',end:'09:55'},{session:3,start:'10:05',end:'11:00'}]);
  assert.deepEqual(input,before);
});
test('substitutions, rooms, teachers and lesson notes keep distinct rows',()=>{
  for(const changed of [{room:'N4'},{teacher:'Another teacher'},{note:'Bring notes'},{substitution:true}]){
    assert.equal(groupDisplayLessons([lesson(1),lesson(2,changed)],slots).length,2);
  }
  assert.equal(groupDisplayLessons([lesson(1,{substitution:true}),lesson(2)],slots).length,2);
  assert.equal(groupDisplayLessons([lesson(1),lesson(3)],slots).length,2);
});
test('neither separate records nor existing spans group across lunch',()=>{
  assert.equal(groupDisplayLessons([lesson(4),lesson(5)],slots).length,2);
  const rows=groupDisplayLessons([lesson(4,{span:2,end:slots[4].end})],slots);
  assert.deepEqual(rows.map(row=>[row.session,row.span,row.start,row.end]),[[4,1,'11:05','12:00'],[5,1,'13:00','13:55']]);
});
test('double-period agenda shows its break while actual transition countdown stays unchanged',()=>{
  const fixture=structuredClone(doc);fixture.settings.anchorDay=1;
  fixture.groups['3CS'][0]=[lesson(1,{subject:'LA'}),lesson(2),lesson(3),lesson(4,{subject:'LA'}),lesson(5,{subject:'PE'}),lesson(6,{subject:'M'})];
  const before=getLessons('2026-10-13','3CS',fixture);
  const status=getDayStatus('2026-10-13','3CS',fixture,new Date('2026-10-13T09:58:00-06:00'));
  assert.equal(status.status,'transition');assert.equal(status.remainingSeconds,7*60);
  const html=agenda('2026-10-13','3CS',fixture,status);
  assert.ok(html.includes('2 periods'));assert.ok(html.includes('Break 9:55 AM – 10:05 AM'));
  assert.deepEqual(getLessons('2026-10-13','3CS',fixture),before);
});
test('student timetable has optional rooms, compact side updates and earlier lessons disclosure',()=>{
  const html=studentView({document:doc,group:'3CS',view:'today',now:new Date('2026-10-13T11:10:00-06:00')});
  assert.ok(html.includes('class="schedule-primary"'));assert.ok(html.includes('class="schedule-secondary"'));
  assert.ok(html.includes('class="earlier-lessons" open'));
  assert.ok(html.includes('data-show-rooms >Show rooms'));
  assert.ok(html.includes('class="subject-name"'));assert.ok(html.includes('class="subject-short"'));
});
test('substitute room remains identifiable even when routine rooms are hidden',()=>{
  const fixture=structuredClone(doc);fixture.overrides.push({date:'2026-10-13',group:'3CS',session:1,subject:'LA',room:'N4',teacher:'Substitute teacher'});
  const html=agenda('2026-10-13','3CS',fixture);
  assert.ok(html.includes('class="substitute-location"'));assert.ok(html.includes('New room: N4'));
  assert.ok(html.includes('class="lesson-teacher">Substitute teacher'));
});
