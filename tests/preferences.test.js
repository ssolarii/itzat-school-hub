import test from 'node:test';
import assert from 'node:assert/strict';
import { AUDIENCE_COOKIE, parseAudienceCookie, audienceCookie, clearAudienceCookie } from '../src/preferences.js';

test('each valid audience parses from its saved cookie', () => {
  for (const role of ['student', 'teacher', 'parent']) assert.equal(parseAudienceCookie(`${AUDIENCE_COOKIE}=${role}`), role);
});
test('parser ignores other cookies and cookie ordering', () => {
  assert.equal(parseAudienceCookie(`unrelated=1; ${AUDIENCE_COOKIE}=parent; session=abc`), 'parent');
  assert.equal(parseAudienceCookie(`${AUDIENCE_COOKIE}=teacher; other=student`), 'teacher');
});
test('missing, malformed, ambiguous and privileged audience values require selection again', () => {
  for (const cookie of ['', null, undefined, {}, `${AUDIENCE_COOKIE}`, `${AUDIENCE_COOKIE}=`, `${AUDIENCE_COOKIE}=admin`, `${AUDIENCE_COOKIE}=developer`, `${AUDIENCE_COOKIE}=Student`, `${AUDIENCE_COOKIE}=%ZZ`, `${AUDIENCE_COOKIE}=student; ${AUDIENCE_COOKIE}=parent`]) assert.equal(parseAudienceCookie(cookie), null);
});
test('encoded legitimate values parse once; cookie injection and double encoding are rejected', () => {
  assert.equal(parseAudienceCookie(`${AUDIENCE_COOKIE}=%73tudent`), 'student');
  for (const value of ['student%3B%20admin%3Dtrue', 'student%253Badmin%253Dtrue', 'parent%0A', 'teacher%3Dadmin', '%3Cscript%3E']) assert.equal(parseAudienceCookie(`${AUDIENCE_COOKIE}=${value}`), null);
});
test('writer saves a one-year root preference with SameSite=Lax', () => {
  assert.equal(audienceCookie('student'), `${AUDIENCE_COOKIE}=student; Max-Age=31536000; Path=/; SameSite=Lax`);
  assert.equal(audienceCookie('teacher', { secure: true }), `${AUDIENCE_COOKIE}=teacher; Max-Age=31536000; Path=/; SameSite=Lax; Secure`);
});
test('GitHub Pages cookie is scoped to its deployment directory', () => {
  assert.match(audienceCookie('parent', { basePath: '/school-hub/' }), /Path=\/school-hub\/;/);
  assert.match(audienceCookie('parent', { basePath: '/school-hub' }), /Path=\/school-hub\/;/);
  assert.match(audienceCookie('parent', { basePath: '/nested/school/' }), /Path=\/nested\/school\/;/);
});
test('writer rejects unsupported audiences and path/header injection', () => {
  for (const audience of ['admin', '', null, 'student; admin=true', '<script>', 'STUDENT']) assert.throws(() => audienceCookie(audience), TypeError);
  for (const path of ['./', 'school', '/school;Secure', '/school\nDomain=example.com', '/school?admin=true', '/school#fragment', '/school\\other']) assert.throws(() => audienceCookie('student', { basePath: path }), TypeError);
  assert.throws(() => audienceCookie('student', { secure: 'true' }), TypeError);
});
test('clear uses the same path and security attributes as saving', () => {
  const value = clearAudienceCookie({ basePath: '/school/', secure: true });
  assert.match(value, /Max-Age=0/); assert.match(value, /Expires=Thu, 01 Jan 1970 00:00:00 GMT/);
  assert.match(value, /Path=\/school\/; SameSite=Lax; Secure$/);
  assert.equal(parseAudienceCookie(`${AUDIENCE_COOKIE}=`), null);
});
