// Shared by all three entry pages. Never send account or conversation data.
// https://developers.google.com/analytics/devguides/collection/ga4/reference/config
(() => {
  if (location.protocol !== 'https:' || ['localhost','127.0.0.1'].includes(location.hostname)) return;
  const authCallback = () => /[?&#](?:code|access_token|refresh_token|token_hash|error_description)=/.test(location.search + location.hash);
  if (authCallback()) return;
  const measurementId = 'G-K0NVG54KF2';
  const routes = new Set(['schedule','calendar','updates','qa','chat','profile','settings','admin','login']);
  const titles = {schedule:'Schedule',calendar:'School calendar',updates:'ISA Updates',qa:'Q+A',chat:'Chat',profile:'Profile',settings:'Settings',admin:'School admin',login:'Sign in'};
  let referrer = '';
  try { referrer = new URL(document.referrer).origin; } catch {}
  window.dataLayer = window.dataLayer || [];
  window.gtag = window.gtag || function () { window.dataLayer.push(arguments); };
  window.gtag('js', new Date());
  window.gtag('config', measurementId, {
    send_page_view: false,
    page_location: location.origin + location.pathname,
    page_referrer: referrer,
    allow_google_signals: false,
    allow_ad_personalization_signals: false,
  });
  let lastPage = '';
  function pageView() {
    if (authCallback()) return;
    const route = location.hash.slice(1), safeRoute = routes.has(route) ? route : '';
    const page = location.origin + location.pathname + (safeRoute ? '#' + safeRoute : '');
    if (page === lastPage) return;
    const params = {page_location:page,page_referrer:referrer,page_title:'Schedule Assistant' + (safeRoute ? ' · ' + titles[safeRoute] : '')};
    window.gtag('set', params);
    window.gtag('event', 'page_view', {...params,send_to:measurementId});
    lastPage = page;
    referrer = page;
  }
  pageView();
  addEventListener('hashchange', pageView);
  const tag = document.createElement('script');
  tag.async = true;
  tag.src = 'https://www.googletagmanager.com/gtag/js?id=' + measurementId;
  tag.referrerPolicy = 'origin';
  document.head.append(tag);
})();
