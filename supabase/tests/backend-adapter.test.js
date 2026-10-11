import test from 'node:test';
import assert from 'node:assert/strict';
import { createBackend } from '../../src/backend.js';

const url = 'https://test-project.supabase.co';
test('browser adapter rejects Supabase secret keys', () => {
  assert.throws(() => createBackend({ url, key: 'sb_secret_never_in_browser' }), /secret Supabase key/);
});
test('browser adapter rejects privileged service-role JWTs', () => {
  const payload = Buffer.from(JSON.stringify({ role: 'service_role' })).toString('base64url');
  assert.throws(() => createBackend({ url, key: `header.${payload}.signature` }), /Only the Supabase anon key/);
});
test('browser adapter rejects malformed keys and missing keys', () => {
  assert.throws(() => createBackend({ url, key: 'plain-password' }), /publishable or anon key/);
  assert.throws(() => createBackend({ url, key: 'a.!invalid!.z' }), /not a valid/);
  assert.throws(() => createBackend({ url }), /key is missing/);
});
test('browser adapter requires HTTPS except local development', () => {
  assert.throws(() => createBackend({ url: 'http://test-project.supabase.co', key: 'sb_publishable_test' }), /must use HTTPS/);
});
