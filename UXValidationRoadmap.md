# Reliability and UI validation roadmap

## Current checkpoint

Preserve Daily / Journey / Settings and existing cards. Work in the permanent project only.
UI proposals use explicitly labelled sample data, never invented live status.

1. Baseline build and inspect existing changes; do not overwrite unrelated work.
2. Separate device download time from source update time. EPDK catalogue records have unknown source freshness and availability. A recent download permits candidate evaluation, not a claim of operational verification.
3. Audit backend cache timestamps, persistent refresh, coverage and partial failures. Seven supported brands are not all Turkey.
4. Replace straight-line station selection with real route geometry and driving detours.
5. Validate Macan-specific consumption/charging inputs. Vehicle telemetry remains unverified; manual battery inputs are estimates.
6. Unify inline destination search across Daily and Journey; verify Dynamic Type, scrolling, loading and recovery.
7. Test city, borderline, very-low battery, Istanbul–Bodrum and Istanbul–Ayvalık; explicitly reject unsupported multi-stop plans.
8. Simulator visual approval, then physical-device validation. No road-ready claim before acceptance.

## First implementation package

- EPDK source-update timestamps remain nil; device download time has a separate field.
- Merging no longer attaches a different provider's update time to the chosen record.
- Unknown source freshness does not receive high confidence.
- Recommendation labels catalogue source and unverified availability explicitly.
- No-charge wording is a prediction, not a safety guarantee.
- Actual route geometry, live availability, automated refresh and car telemetry remain separate work; they are not delivered by this package.

## Refresh follow-up

- Server fetch time and response time separated; cache hits retain original time.
- Timeout and malformed upstream payload preserve partial results.
- iOS reads server fetch time, rejects expired/future dates, preserves valid records in partly malformed responses and shows partial coverage even when a stop exists.
- Explicit rejection of unsupported/excess brand queries; no silent truncation.
- Backend has five isolated regression tests; iOS includes decoding/freshness/partial-result tests.
- Rollout and full visual validation must be recorded separately from local passing tests.

## Real road geometry checkpoint

- Google Routes returns real GeoJSON road geometry; tested live for Istanbul–Bodrum, Istanbul–Ayvalık and a short city route.
- Segment-based corridor filtering replaces gaps between sparse sampled vertices.
- Up to three candidate stations are checked using routes with a stopover; two legs determine reachability and added distance/time.
- Preferred charge limit and arrival reserve are respected; no verified road path means no selected station.
- Remaining decision: support multiple planned charging stops internally while showing one next action, or expose a full itinerary. Do not silently expand the single-stop UI scope.

## Approved decision: B, full itinerary

User selected all charging stops visible. Implemented complete-plan validation and ordered stop cards in Daily and Journey. The first stop is highlighted and navigable. Later stops stay visible; manual battery update and recalculation after charging is explicitly stated. Limits: three candidate plans, six stops, generic vehicle model, incomplete catalogue coverage, unknown live availability. No automatic arrival/charging detection.
