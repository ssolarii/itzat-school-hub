import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { loginView, renderTeacherRequests } from '../src/staff-views.js';

const doc = JSON.parse(readFileSync(new URL('../school-data.json', import.meta.url), 'utf8'));
const args = { backendReady: true, document: doc };
const session = { user: { id: 'account', email: 'teacher@example.edu', user_metadata: { full_name: 'School Teacher' } } };

test('staff login is password based with correct autofill semantics', () => {
  const html = loginView({ ...args, mode: 'login', email: 'teacher@example.edu' });
  assert.ok(html.includes('id="password-login"'));
  assert.ok(html.includes('type="password" name="password" autocomplete="current-password"'));
  assert.ok(html.includes('data-staff-mode="signup"'));
  assert.ok(!html.includes('id="verify-form"'));
  assert.ok(!html.includes('sign-in code'));
});

test('signup uses a new password and promises approval rather than automatic teacher rights', () => {
  const html = loginView({ ...args, mode: 'signup' });
  assert.ok(html.includes('id="staff-signup"'));
  assert.ok(html.includes('minlength="8" autocomplete="new-password" required'));
  assert.ok(html.includes('name="displayName"'));
  assert.ok(html.includes('must approve your request'));
  assert.ok(html.includes('data-staff-mode="login"'));
});

test('request and pending views require an authenticated session', () => {
  assert.ok(loginView({ ...args, mode: 'request' }).includes('id="password-login"'));
  assert.ok(loginView({ ...args, mode: 'pending' }).includes('id="password-login"'));
  const html = loginView({ ...args, mode: 'request', session });
  assert.ok(html.includes('id="teacher-request"'));
  assert.ok(html.includes('name="displayName"'));
  assert.ok(html.includes('name="teaching" value="[&quot;QR&quot;,&quot;3CS&quot;]"'));
  assert.ok(html.includes('name="note"'));
  assert.ok(!html.includes('name="password"'));
  const pending = loginView({ ...args, mode: 'pending', session });
  assert.ok(pending.includes('awaiting review'));
  assert.ok(pending.includes('data-refresh'));
  assert.ok(!pending.includes('id="teacher-request"'));
});

test('approved, rejected, and disconnected account states are honest', () => {
  assert.ok(loginView({ ...args, session, membership: { active: true, role: 'teacher' } }).includes('approved school permissions are active'));
  const rejected = loginView({ ...args, session, mode: 'pending', request: { status: 'rejected', review_note: 'Check your class scope.' } });
  assert.ok(rejected.includes('did not approve'));
  assert.ok(rejected.includes('Check your class scope.'));
  assert.ok(rejected.includes('data-staff-mode="request"'));
  const offline = loginView({ ...args, backendReady: false });
  assert.ok(offline.includes('sign-in is unavailable'));
  assert.ok(!offline.includes('<form'));
});

test('teacher request review exposes named decisions and approved class scopes only for pending records', () => {
  const requests = [{ id: 'request-1', user_id: 'teacher-id', display_name: 'Teacher', groups: ['3CS'], requested_teaching:[{subject:'LA',group:'3CS'}], note: 'I teach LA.', status: 'pending' }];
  const html = renderTeacherRequests(requests, doc);
  assert.ok(html.includes('data-staff-review="request-1"'));
  assert.ok(html.includes('name="requestId" value="request-1"'));
  assert.ok(html.includes('name="teaching" value="[&quot;LA&quot;,&quot;3CS&quot;]" checked'));
  assert.ok(html.includes('name="decision" value="approve"'));
  assert.ok(html.includes('name="decision" value="reject"'));
  assert.ok(!html.includes('name="reviewNote"'));
  assert.ok(!renderTeacherRequests([{ ...requests[0], status: 'approved' }], doc).includes('data-staff-review'));
});

test('private requests and form values escape all supplied strings and omit archived class choices', () => {
  const fixture = structuredClone(doc); fixture.archivedGroups = ['1A'];
  const html = loginView({ ...args, document: fixture, mode: 'request', session, request: { display_name: '<script>alert(1)</script>', groups: ['3CS'], note: '<img src=x>' } });
  assert.ok(!html.includes('<script>'));
  assert.ok(!html.includes('<img'));
  assert.ok(html.includes('&lt;script&gt;'));
  assert.ok(!html.includes('name="groups" value="1A"'));
  const reviewed = renderTeacherRequests([{ id: 'x" onclick="bad()', display_name: '<img src=x>', note: '<script>bad()</script>', groups: [], status: 'pending' }], fixture);
  assert.ok(!reviewed.includes('<script>'));
  assert.ok(!reviewed.includes('<img'));
  assert.ok(!reviewed.includes('data-staff-review="x" onclick="bad()"'));
  assert.ok(renderTeacherRequests([], doc).includes('No teacher requests awaiting review'));
});

test("approved request with inactive access reports paused rather than awaiting review",()=>{ const html=loginView({...args,session,mode:"pending",request:{status:"approved"}}); assert.ok(html.includes("staff access is paused")); assert.ok(!html.includes("awaiting review")); });
