# School schedule concept refinement

The selected Reference direction keeps the purple school header and ruled timetable from the supplied concepts. Functional decisions are recorded separately in school-functional-plan.json. The existing class hub informs required features; it does not supply the visual direction.

## Installed design skills

Installed locally: Frontend Design from anthropics/skills, Impeccable from pbakaus/impeccable, Make Interfaces Feel Better from jakubkrehel/make-interfaces-feel-better, Grill Me and its Grilling companion from mattpocock/skills, and the Product Design skill suite from openai/plugins.

The current Impeccable suite has 24 commands. The current Product Design source contains 10 skills: audit, design-qa, get-context, ideate, image-to-code, index, research, share, url-to-code, and user-context. These are local skill installations; the Product Design marketplace plugin is not registered or connected. Shared Product Design resources and reference links were installed alongside the suite.

## Design choices

Use Manrope for the selected direction, with a local sans fallback. Keep neutral paper and ink surfaces, purple branding, and a quiet purple current-row highlight. Times remain monospaced to match the user's references. Use ruled rows rather than dashboard cards. Display subject codes consistently; disclose names on tap. Leave unconfirmed expansions visibly unconfirmed.

## Review coverage

Full review of the selected schedule concept and shared timetable interactions. Framework: plain HTML and JavaScript with scoped CSS. Boundary: illustrative concept, not the Supabase application or installed PWA.

| Category | Evidence inspected | Result |
| --- | --- | --- |
| Typography | Reference screen, phone reflow, countdown, date heading, subject disclosures | Refined |
| Surfaces | Purple header, ruled rows, current-row highlight, completed rows | Structural dividers preserved; no added cards |
| Animations | Source and disclosure interactions | Instant state feedback; no authored entrance motion |
| Icons | Native disclosure markers | No decorative icon assets needed |
| Performance | Source, syntax compilation, browser rendering, date selection updates | Date buttons retain their DOM; no transition-all or speculative GPU layers |

## Changes

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| LOW | Reference typography | Arial display, inconsistent tracking and wrapping | Manrope, balanced headings, pretty paragraph wrapping, tracking within −0.03em | More deliberate hierarchy with readable narrow layouts |
| LOW | Reference timer | Proportional figures and a bare 22 min | Tabular figures and explicit left label | Clarifies remaining time and prevents changing digit widths |
| MEDIUM | Subject labels across timetable, cycle and week | Mixed full names and codes | Codes with native expandable names and 44px minimum disclosure targets | Matches the confirmed preference and supports touch and keyboard use |
| MEDIUM | Phone daily schedule | Finished lessons occupy the top of the list | Earlier today disclosure, closed by default | Keeps current and remaining classes prominent |
| MEDIUM | Planner date buttons | Entire button list recreated on selection | Existing buttons retained and their state updated | Preserves keyboard focus during date changes |
| LOW | Reference supporting labels | Tracked capitals and faded completed rows | Sentence case, readable secondary colors and complete text | Reduces visual noise while retaining readable history |
| LOW | Browser surfaces | Unthemed default focus and selection | Palette-derived focus and selection colors | Makes keyboard focus clear on paper and purple header |
| LOW | Public notice sample | Ambiguous Classroom-linked copy | Explicit approved schoolwide notice copy | Reflects the publication decision without presenting private assignments publicly |

## Considered but rejected

| Location | Candidate | Rejected because |
| --- | --- | --- |
| Timetable rows | Add elevated cards or stronger shadows | Ruled rows already express the schedule and match the supplied direction |
| Countdown and subject disclosures | Add repeated entrance or press animations | Frequent schedule interactions need immediate feedback and stable reading |
| Unknown subject codes | Invent full subject names | The timetable image does not establish those names |

## Verification

JavaScript syntax compiled successfully. Impeccable's manual detector returned no findings. Browser inspection showed the populated desktop screen, Span expanding to Spanish, completed lessons hidden on the narrow layout and revealed by Earlier today, and the weekend calendar showing a holiday pause and Day 7 with four lessons. The measured narrow frame was 328px wide with no document horizontal overflow. Temporary viewport changes were reset.

Verdict: needs production validation. Concept interactions inspected above work. Dark appearance, all alternate directions after shared edits, all device/browser combinations, full accessibility conformance, live Supabase permissions, publication moderation, notification delivery and actual offline caching remain unverified. The offline control demonstrates copy only. Example bell times require school confirmation. Production fonts should be self-hosted for reliable offline use.
