import test from 'node:test';
import assert from 'node:assert/strict';
import {noticeContent} from '../src/notice-attachments.js';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
test('Classroom links have a named button and legacy text is removed',()=>{
 const html=noticeContent({body:'Hello\n\nOriginal Classroom post: https://classroom.google.com/c/123/p/456'});
 assert.ok(html.includes('Link to Classroom'));assert.ok(!html.includes('Original Classroom post:'));
});
test('attachments show lazy image previews and escape names and URLs',()=>{
 const html=noticeContent({body:'See https://example.test/help',classroomUrl:'https://classroom.google.com/c/123',attachments:[{title:'<img onerror=bad()>',url:'https://drive.google.com/file/d/123',imageUrl:'https://example.test/image.png',kind:'file'}]});
 assert.ok(html.includes('loading="lazy"'));assert.ok(html.includes('&lt;img onerror=bad()&gt;'));assert.ok(html.includes('Open file'));assert.ok(html.includes('href="https://example.test/help"'));
 assert.ok(!noticeContent({body:'Plain',attachments:[{url:'javascript:alert(1)'}],classroomUrl:'https://evil.test'}).includes('href='));
});
test('Apps Script extracts supported Classroom materials without copying private files',()=>{
 const ctx=vm.createContext({});vm.runInContext(readFileSync(new URL('../integrations/isa-updates/Code.gs',import.meta.url),'utf8'),ctx);
 const post=ctx.isaPost_({id:'1',text:'Post',updateTime:'2026-10-13T18:00:00Z',alternateLink:'https://classroom.google.com/c/123',materials:[{driveFile:{driveFile:{title:'Timetable',alternateLink:'https://drive.google.com/file/d/1',thumbnailUrl:'https://example.test/thumbnail.png'}}},{link:{title:'School',url:'https://www.itzat.edu.bz'}},{link:{url:'javascript:bad()'}}]});
 assert.equal(post.attachments.length,2);assert.equal(post.attachments[0].kind,'file');assert.equal(post.classroomUrl,'https://classroom.google.com/c/123');assert.equal(post.body,'Post');
});
