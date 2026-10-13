import test from 'node:test';
import assert from 'node:assert/strict';
import seed from '../school-data.json' with {type:'json'};
import {welcomeView,settingsView,communityAccountView,normalizeProfile,profileCookie,parseProfileCookie,DEFAULT_INTERESTS} from '../src/welcome.js';
import {parentView} from '../src/views.js';
import {loginView,renderTeacherRequests} from '../src/staff-views.js';

test('welcome has a plain admin link and no school navigation',()=>{
  const html=welcomeView({});
  assert.match(html,/<a class="admin-request-link" href="#request-admin" data-request-admin>Request an admin role<\/a>/);
  assert.ok(!html.includes('side-nav')); assert.equal((html.match(/data-welcome-role=/g)||[]).length,3);assert.ok(!html.includes('welcome-progress'));assert.ok(!html.includes('welcome-footer'));
});
test('roles are presented as three deliberate choices',()=>{
  const html=welcomeView({step:'role'});
  assert.equal((html.match(/data-welcome-role=/g)||[]).length,3);
  assert.match(html,/Change it any time in Settings/);
});
test('profile cookies round trip scoped preferences and reject corrupt/privileged roles',()=>{
  const p={role:'parent',name:' Alejandro ',interests:['events','invalid'],completed:true};
  const saved=profileCookie(p,{basePath:'/itzat-school-hub/',secure:true});
  assert.match(saved,/Path=\/itzat-school-hub\/; SameSite=Lax; Secure/);
  assert.deepEqual(parseProfileCookie(saved),{role:'parent',name:'Alejandro',interests:['events'],completed:true});
  for(const cookie of ['isa_welcome=%ZZ','isa_welcome=%7B','isa_welcome={"role":"developer"}','isa_welcome={}; isa_welcome={}'])assert.equal(parseProfileCookie(cookie),null);
  assert.throws(()=>profileCookie(p,{basePath:'/; Domain=x'}));
  assert.equal(normalizeProfile({role:'student',name:'',completed:true}).completed,false);
  assert.equal(normalizeProfile({role:'student',name:'x'.repeat(100)}).name.length,60);
});
test('parent personalization exposes meaningful interests without claiming notifications',()=>{
  const html=welcomeView({step:'personalize',role:'parent',name:'A',groups:['3CS'],interests:DEFAULT_INTERESTS});
  assert.match(html,/Which class are you following/); assert.equal((html.match(/name="interests"/g)||[]).length,3);
  assert.match(html,/do not enable email or phone notifications/);
});
test('account prompts distinguish approval, optional access and private community features',()=>{
  const teacher=welcomeView({step:'account',role:'teacher',name:'A'});
  assert.match(teacher,/invite-only/);assert.match(teacher,/Vice Principal/);assert.ok(!teacher.includes('Continue without'));
  const student=welcomeView({step:'account',role:'student',name:'A'});
  assert.match(student,/recommend creating a student account/);assert.match(student,/Sign in to use Chat and class polls/);assert.match(student,/Continue without an account/);
  const parent=welcomeView({step:'account',role:'parent',name:'A'});
  assert.match(parent,/Create an account \(optional\)/);assert.match(parent,/Open my parent overview/);
});
test('all names and account values are escaped',()=>{
  const malicious='<script>alert(1)</script>"';
  for(const html of [welcomeView({step:'personalize',role:'student',name:malicious}),welcomeView({step:'account',role:'student',name:malicious}),settingsView({profile:{role:'student',name:malicious},groups:['3CS'],group:'3CS'}),communityAccountView({email:malicious})]){
    assert.ok(!html.includes('<script>'));assert.ok(html.includes('&lt;script&gt;'));
  }
});
test('offline account actions are disabled and student guest access remains available',()=>{
  const html=welcomeView({step:'account',role:'student',name:'A',online:false});
  assert.match(html,/data-welcome-finish="signup" disabled/);assert.match(html,/data-welcome-finish="schedule"/);
});
test('admin requests are clearly separated from teacher approval without granting access',()=>{
  const html=renderTeacherRequests([{id:'a',display_name:'A',status:'pending',groups:['3CS'],note:'[Admin role request] Codeveloper'}],seed);
  assert.match(html,/Permissions tab/);assert.ok(!html.includes('value="approve"'));assert.match(html,/value="reject"/);
  const form=loginView({backendReady:true,mode:'request',session:{user:{id:'a'}},document:seed,requestIntent:'admin'});
  assert.match(form,/Request an admin role/);
  assert.match(form,/name="note" maxlength="1979" required/);
  const pending=loginView({backendReady:true,mode:'pending',session:{user:{id:'a'}},document:seed,request:{status:'pending',note:'[Admin role request] Codeveloper'}});
  assert.match(pending,/Your admin role request is awaiting review/);
  assert.match(pending,/Developer must assign admin permissions/);
});
test('parent choices filter elective events while near closures and published notices remain visible',()=>{
  const doc=structuredClone(seed);doc.calendar={'2026-10-12':{type:'holiday',label:'Near closure'},'2026-12-01':{type:'holiday',label:'Far holiday'},'2026-10-15':{type:'event',label:'Club exhibition'}};
  const limited=parentView(doc,'3CS','2026-10-10',[]);
  assert.match(limited,/Near closure/);assert.ok(!limited.includes('Far holiday'));assert.ok(!limited.includes('Club exhibition'));
  const full=parentView(doc,'3CS','2026-10-10',DEFAULT_INTERESTS);
  assert.match(full,/Far holiday/);assert.match(full,/Club exhibition/);assert.match(full,/Half day/);
});
