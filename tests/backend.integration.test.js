import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { validateSnapshot } from '../src/repository.js';

// Opt-in only: local unit tests must also work without internet connectivity.
const enabled = process.env.ISA_INTEGRATION === '1';
function config() { return JSON.parse(readFileSync(new URL('../school-config.json', import.meta.url), 'utf8')); }
async function request(path) {
  const cfg = config();
  return fetch(new URL(path, cfg.url), { headers: { apikey: cfg.publishableKey }, signal: AbortSignal.timeout(10000) });
}

test('live anonymous client can load a validated public timetable revision', { skip: !enabled }, async () => {
  const response = await request('/rest/v1/school_versions?select=revision,document,published_at&order=revision.desc&limit=1');
  assert.equal(response.status, 200);
  const rows = await response.json(); assert.equal(rows.length, 1);
  const published = validateSnapshot({ ...rows[0], publishedAt: rows[0].published_at });
  assert.ok(published.revision >= 1);
  assert.ok(Object.keys(published.document.groups).length >= 11);
});
test('live anonymous client cannot read private staff accounts or notice drafts', { skip: !enabled }, async () => {
  for (const table of ['school_members', 'school_notice_drafts']) {
    const response = await request(`/rest/v1/${table}?select=*&limit=1`);
    assert.ok([401, 403].includes(response.status), `${table} must deny anonymous private reads`);
  }
});
test('live anonymous client cannot select publisher account IDs', { skip: !enabled }, async () => {
  const response = await request('/rest/v1/school_versions?select=published_by&limit=1');
  assert.ok([401, 403].includes(response.status));
});
