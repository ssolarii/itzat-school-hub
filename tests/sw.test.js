import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../public/sw.js', import.meta.url), 'utf8');
const manifest = ['index.html','schedule.html','chat.html', 'assets/app-123.js', 'assets/app-456.css', 'assets/font-789.woff2'];
function worker() {
  const handlers = {}, cacheEntries = new Map(), cacheNames = new Set(['unrelated-site', 'isa-shell-%2Fhub%2F-old', 'isa-shell-%2Fother-project%2F-old']);
  const deleted = [], network = [], installRequests=[];let installedHTML='';
  let claimed = 0, skipped = 0;
  const caches = {
    keys: async () => [...cacheNames],
    delete: async name => { deleted.push(name); cacheNames.delete(name); return true; },
    open: async name => {
      cacheNames.add(name);
      return {
        addAll: async requests => { requests.forEach(request => {installRequests.push(request);cacheEntries.set(request.url, `saved:${request.url}`);}); },
        put: async (url,response)=>{const html=await response.text();if(url.endsWith('/index.html'))installedHTML=html;cacheEntries.set(url,`saved:${url}`);},
        match: async request => cacheEntries.get(typeof request === 'string' ? request : request.url)
      };
    }
  };
  const self = {
    registration: { scope: 'https://school.example/hub/' },
    addEventListener: (name, handler) => { handlers[name] = handler; },
    clients: { claim: async () => { claimed++; } },
    skipWaiting: () => { skipped++; }
  };
  vm.runInNewContext(source.replace('__BUILD_ID__', 'test').replace('__BUILD_ASSETS__', JSON.stringify(manifest)).replace('__BUILD_SHELLS__',JSON.stringify({'index.html':'<html>matched build</html>','schedule.html':'<html>schedule build</html>','chat.html':'<html>chat build</html>'})), {
    URL, Request, Response, self, caches, fetch: async request => { const url = request.url || request; network.push(url); return `network:${url}`; }
  });
  return {
    handlers, cacheEntries, deleted, network,installRequests,get installedHTML(){return installedHTML;}, get claimed() { return claimed; }, get skipped() { return skipped; },
    async lifecycle(name) { let promise; handlers[name]({ waitUntil: value => { promise = value; } }); await promise; },
    async request(path, { mode = 'cors', method = 'GET', authorization = false } = {}) {
      let handled = false, promise;
      const request = { url: new URL(path, self.registration.scope).href, mode, method, headers: { has: name => authorization && name === 'authorization' } };
      handlers.fetch({ request, respondWith: value => { handled = true; promise = value; } });
      return { handled, response: handled ? await promise : null };
    }
  };
}

test('worker precaches the complete build manifest relative to its deployment scope', async () => {
  const runtime = worker(); await runtime.lifecycle('install');
  assert.deepEqual([...runtime.cacheEntries.keys()].sort(), manifest.map(path => `https://school.example/hub/${path}`).sort());
});
test('cached hashed script, CSS and fonts load without network access', async () => {
  const runtime = worker(); await runtime.lifecycle('install');
  for (const asset of manifest.slice(1)) {
    const result = await runtime.request(asset);
    assert.equal(result.handled, true); assert.equal(result.response, `saved:https://school.example/hub/${asset}`);
  }
  assert.deepEqual(runtime.network, []);
});
test('root and index navigation use the same versioned shell', async () => {
  const runtime = worker(); await runtime.lifecycle('install');
  for (const path of ['', 'index.html']) {
    const result = await runtime.request(path, { mode: 'navigate' });
    assert.equal(result.handled, true); assert.equal(result.response, 'saved:https://school.example/hub/index.html');
  }
});
test('schedule navigation uses its own cached page', async () => {
 const runtime=worker();await runtime.lifecycle('install');
 const result=await runtime.request('schedule.html',{mode:'navigate'});
 assert.equal(result.handled,true);assert.equal(result.response,'saved:https://school.example/hub/schedule.html');
});

test('auth, admin, API, query and credential-bearing requests bypass the worker', async () => {
  const runtime = worker(); await runtime.lifecycle('install');
  for (const path of ['auth', 'auth/callback', 'admin', 'admin/permissions', 'api/schedules', 'assets/app-123.js?access_token=redacted']) {
    assert.equal((await runtime.request(path, { mode: 'navigate' })).handled, false, path);
  }
  assert.equal((await runtime.request('assets/app-123.js', { authorization: true })).handled, false);
  assert.equal((await runtime.request('assets/app-123.js', { method: 'POST' })).handled, false);
  assert.deepEqual(runtime.network, []);
});
test('Supabase and other cross-origin requests are never intercepted or cached', async () => {
  const runtime = worker(); await runtime.lifecycle('install');
  assert.equal((await runtime.request('https://project.supabase.co/rest/v1/schedules')).handled, false);
  assert.equal((await runtime.request('https://accounts.google.com/auth')).handled, false);
  assert.equal(runtime.cacheEntries.size, manifest.length);
});
test('arbitrary same-origin URLs are not runtime cached', async () => {
  const runtime = worker(); await runtime.lifecycle('install');
  assert.equal((await runtime.request('private-data.json')).handled, false);
  assert.equal((await runtime.request('other-page', { mode: 'navigate' })).handled, false);
});
test('missing static asset uses network without caching the response', async () => {
  const runtime = worker(); await runtime.lifecycle('install');
  runtime.cacheEntries.delete('https://school.example/hub/assets/app-123.js');
  const result = await runtime.request('assets/app-123.js');
  assert.equal(result.response, 'network:https://school.example/hub/assets/app-123.js');
  assert.equal(runtime.cacheEntries.has('https://school.example/hub/assets/app-123.js'), false);
});
test('activation removes only old school shell caches and claims clients', async () => {
  const runtime = worker(); await runtime.lifecycle('install'); await runtime.lifecycle('activate');
  assert.deepEqual(runtime.deleted, ['isa-shell-%2Fhub%2F-old']); assert.equal(runtime.claimed, 1);
});
test('update remains waiting until explicit user activation message', () => {
  const runtime = worker(); assert.equal(runtime.skipped, 0);
  runtime.handlers.message({ data: { type: 'OTHER_MESSAGE' } }); assert.equal(runtime.skipped, 0);
  runtime.handlers.message({ data: { type: 'ACTIVATE_UPDATE' } }); assert.equal(runtime.skipped, 1);
});

test("install uses build-matched embedded HTML and reloads hashed assets",async()=>{const runtime=worker();await runtime.lifecycle("install");assert.equal(runtime.installedHTML,"<html>matched build</html>");assert.equal(runtime.installRequests.length,3);assert.ok(runtime.installRequests.every(r=>r.cache==="reload"));});

test("chat navigation uses its own cached shell", async()=>{const runtime=worker();await runtime.lifecycle("install");const result=await runtime.request("chat.html",{mode:"navigate"});assert.equal(result.handled,true);assert.equal(result.response,"saved:https://school.example/hub/chat.html");});
