import test from 'node:test';
import assert from 'node:assert/strict';
import { createBackend } from '../src/backend.js';
import { teacherTimetableIntake, teacherAssignmentEditor, teacherAssignmentProposal } from '../src/teacher-timetable.js';
import { loginView, renderTeacherRequests } from '../src/staff-views.js';
const backend = () => createBackend({url:'https://example.supabase.co',key:'sb_publishable_test'});
test('teacher image upload uses own private path and submits only after storage success',async()=>{
 const service=backend(),calls=[];
 service.client.auth.getSession=async()=>({data:{session:{user:{id:'teacher-id'}}}});
 service.client.storage.from=bucket=>({upload:async(path,file,options)=>{calls.push({bucket,path,options});return {data:{path}};}});
 service.client.rpc=async(name,args)=>{calls.push({name,args});return {data:{status:'pending'}};};
 const result=await service.uploadTeacherTimetable({type:'image/png',size:1024});
 assert.equal(result.status,'pending');assert.equal(calls[0].bucket,'teacher-timetables');
 assert.match(calls[0].path,/^teacher-id\/[^/]+\.png$/);assert.equal(calls[0].options.upsert,false);
 assert.deepEqual(calls[1],{name:'submit_teacher_timetable',args:{p_path:calls[0].path}});
});
test('teacher image upload rejects wrong types, empty images, oversize files and failed storage',async()=>{
 const service=backend();
 for(const file of [{type:'image/gif',size:1},{type:'image/png',size:0},{type:'image/png',size:10485761}])await assert.rejects(()=>service.uploadTeacherTimetable(file),/JPG, PNG or WebP/);
 service.client.auth.getSession=async()=>({data:{session:{user:{id:'teacher'}}}});
 service.client.storage.from=()=>({upload:async()=>({error:{message:'Upload denied'}})});
 service.client.rpc=()=>{throw Error('Should not submit failed upload');};
 await assert.rejects(()=>service.uploadTeacherTimetable({type:'image/png',size:1}),/Upload denied/);
});
test('approval message is private account copy and escapes supplied HTML',()=>{
 const html=loginView({backendReady:true,membership:{active:true},request:{approval_message:'Welcome <script>bad()</script>'}});
 assert.ok(html.includes('Message from school leadership'));assert.ok(html.includes('&lt;script&gt;'));assert.ok(!html.includes('<script>'));
 const review=renderTeacherRequests([{id:'request',status:'approved'}],{groups:{'3CS':[]}});
 assert.ok(review.includes('data-teacher-message'));assert.ok(review.includes('maxlength="2000"'));
});
test('teacher intake offers supported file formats and honest pending state',()=>{
 const html=teacherTimetableIntake({status:'pending',image_url:'https://example.test/timetable.png'});
 assert.ok(html.includes('id="teacher-timetable-upload"'));assert.ok(html.includes('image/jpeg,image/png,image/webp'));
 assert.ok(html.includes('waiting for digitization'));assert.ok(html.includes('View your uploaded timetable'));
});
test('digitization changes only one teacher and requires valid classes before publication',()=>{
 const doc={groups:{'3CS':[],'4CS':[]},teacherAssignments:[{teacher:'other',day:1,session:1,group:'4CS'}]};
 const values=new Map([['teacher','teacher'],['assignment-1-1','3CS'],['assignment-1-2','3CS']]);
 const result=teacherAssignmentProposal(doc,values);
 assert.equal(result.kind,'document');assert.equal(doc.teacherAssignments.length,1);assert.equal(result.document.teacherAssignments.length,3);
 assert.equal(result.document.teacherAssignments[0].teacher,'other');
 assert.ok(teacherAssignmentEditor(result.document,'teacher').includes('value="3CS" selected'));
 values.set('assignment-1-3','missing');assert.throws(()=>teacherAssignmentProposal(doc,values),/active class/);
});
