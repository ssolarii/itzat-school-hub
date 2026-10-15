import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {digitizedTeacherLessons} from '../src/teacher-schedule.js';
import {teacherView} from '../src/views.js';
const doc=JSON.parse(fs.readFileSync(new URL('../school-data.json',import.meta.url),'utf8'));
const upload={status:'digitized',digitized_schedule:{version:1,entries:[{day:7,session:5,span:2,subject:'PLC',room:'MS',groups:[]},{day:6,session:1,subject:'BS',room:'N2',groups:['3EM']} ]}};
test('private teacher schedule keeps PLC after student half-day dismissal',()=>{
 const rows=digitizedTeacherLessons(upload,'2026-10-14',doc);
 assert.equal(rows.length,1);assert.equal(rows[0].subject,'PLC');assert.equal(rows[0].start,'13:00');assert.equal(rows[0].end,'15:00');
 assert.ok(teacherView(doc,'2026-10-14','teacher',upload).includes('Staff planning'));
});
test('digitized room and class come from the teacher source independently of student records',()=>{
 const rows=digitizedTeacherLessons(upload,'2026-10-13',doc);
 assert.equal(rows[0].room,'N2');assert.deepEqual(rows[0].groups,['3EM']);
 assert.deepEqual(digitizedTeacherLessons(upload,'2026-10-17',doc),[]);
 assert.equal(digitizedTeacherLessons({...upload,status:'pending'},'2026-10-13',doc),null);
});
