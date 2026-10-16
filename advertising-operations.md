# Desktop advertising

Publisher: `ca-pub-4086740862036998`.
Manual ad unit: **Schedule Assistant desktop banner**, `1491668269`, 728×90.

## Setup status: 16 October 2026

- Published the exact AdSense-provided `ads.txt` line at
  `https://ssolarii.github.io/ads.txt`, in the host repository
  `ssolarii/ssolarii.github.io` (commit `b53edbb`).
- Google confirmed site ownership. Its status is **Getting ready** with
  **Review requested**. This is not approval to serve ads yet.
- Google's European-regulations consent editor opened as a blank/loading
  frame. Consent messages and age-treatment configuration are not complete.
  Keep `ads.ready` false; finish these controls before enabling live ads.

The account's school-directory Auto ads exclusion was saved for
`ssolarii.github.io/itzat-school-hub/` and all pages below it. This avoids
automatic mobile, anchor, vignette and other overlay placements on the school
site while preserving settings on unrelated GitHub Pages projects.

## Launch gate

`school-config.json` deliberately keeps `ads.ready` false until the school
site is approved and Google Privacy & messaging / age-appropriate ad controls
are configured. The provided SDK is connected through a conditional loader,
not an unconditional script on every page. Verification uses the publisher
meta tag. A pending AdSense account cannot produce confirmed revenue.

Before setting `ready: true`:

1. Confirm the site's Ready status in AdSense and the school-directory Auto ads
   exclusion is still saved. Keep Auto optimise from overriding the exclusion.
2. Configure the required Google-certified consent messages in AdSense Privacy
   & messaging. The ad-amount preference is not a substitute for that CMP.
3. Review site-level age treatment and advertiser-category restrictions for
   the school audience. Do not infer age from a user's class or send their
   name, class, interests, profile or chat content to the ad provider.
4. Review the factual privacy notice and provide the site's preferred direct
   contact for privacy/account requests.
5. Check root-domain verification / ads.txt requirements. A project-level
   `/itzat-school-hub/ads.txt` is not a replacement for the host's root file.

## User controls

- Settings offers Off, Standard (one placement), or More (up to two).
- The browser cookie is independent of Supabase and account roles.
- Close is a site control outside the creative. One accessible confirmation
  offers Keep ads / Turn off ads. Turning off removes all site placements and
  stops further site ad requests; there are no timers or access penalties.
- Changing density applies on the next page load. There is no automatic ad
  refresh or incentive to click/view ads.
- Only public schedule, calendar and ISA Updates screens are eligible.
  Landing, sign-in, settings, admin, profiles, Q+A and chat carry no ads.
- Mobile device detection and a desktop width/pointer check prevent loading
  the SDK on mobile. CSS also hides ad areas below 1100px / on touch pointers.
- Ad requests are non-personalized. Lazy loading occurs near the placement.
  Third-party ad code is never cached by the service worker.

Official references:
- https://support.google.com/adsense/answer/48182
- https://support.google.com/adsense/answer/9305577
- https://support.google.com/adsense/answer/13554116
- https://support.google.com/adsense/answer/9007197
