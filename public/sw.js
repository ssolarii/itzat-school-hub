/* Filled with exact content-hashed asset paths by scripts/build-sw.mjs. */
const BUILD_ID = '__BUILD_ID__';
const BUILD_ASSETS = __BUILD_ASSETS__;
const BUILD_SHELLS = __BUILD_SHELLS__;
const htmlPaths = Object.keys(BUILD_SHELLS);
const scope = new URL(self.registration.scope);
// Several GitHub Pages projects can share an origin. Keep their caches separate.
const CACHE_PREFIX = `isa-shell-${encodeURIComponent(scope.pathname)}-`;
const CACHE = `${CACHE_PREFIX}${BUILD_ID}`;
const assetURLs = new Set(BUILD_ASSETS.map(path => new URL(path, scope).href));
const shellURL = new URL('index.html', scope).href;
const htmlURLs = new Map(htmlPaths.map(path=>[new URL(path,scope).href,path]));

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(async cache => {
    await cache.addAll([...assetURLs].filter(url=>!htmlURLs.has(url)).map(url=>new Request(url,{cache:'reload'})));
    for(const [url,path] of htmlURLs)await cache.put(url,new Response(BUILD_SHELLS[path],{headers:{'Content-Type':'text/html; charset=utf-8'}}));
  }));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith(CACHE_PREFIX) && key !== CACHE).map(key => caches.delete(key)))).then(() => self.clients.claim()));
});
self.addEventListener('message', event => {
  if (event.data?.type === 'ACTIVATE_UPDATE') self.skipWaiting();
});
self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== scope.origin || /\/(?:auth|admin|api)(?:\/|$)/i.test(url.pathname)) return;
  // The worker never caches API responses or credential-bearing requests.
  if (request.headers.has('authorization') || url.search) return;
  if (assetURLs.has(url.href) && request.mode !== 'navigate') {
    event.respondWith(caches.open(CACHE).then(async cache => {
      const saved = await cache.match(request);
      return saved || fetch(request);
    }));
    return;
  }
  if (request.mode === 'navigate' && (url.pathname === scope.pathname || htmlURLs.has(url.href))) {
    // Match the HTML to this worker's hashed bundle; upgrades activate together.
    event.respondWith(caches.open(CACHE).then(async cache => (await cache.match(url.pathname===scope.pathname?shellURL:url.href)) || fetch(request)));
  }
});
