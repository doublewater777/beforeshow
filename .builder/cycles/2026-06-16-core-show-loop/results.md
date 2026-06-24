# Core Show Loop Results

2026-06-16 implementation result:

- Tonight First Listen: implemented with CloudBase candidate generation, local candidate storage, picked-song display, and Pro repeat-generation gate.
- Round Trip Plan: implemented with user direction fields, CloudBase `roundTripDraft`, editable generated text, local save, and Pro repeat-generation gate for outbound/return drafts.
- Preview Before Show: implemented with local artist, venue/seat, entry, weather/traffic guidance plus CloudBase `showRecap`, lightweight Bilibili metadata storage, official external player/original page links, and Pro repeat-discovery gate.
- Show Preparation: implemented as a persistent checklist with reminder date and private notes.
- Show Fragments: already supports local text, gallery media references, and app-created audio; retained as a free local feature.
- Pro: StoreKit-backed product loading, purchase, restore, and entitlement persistence are present.

Verification:

- iOS tests: `78 tests`, `0 failures`.
- CloudBase tests: `39 tests`, `0 failures`.
- Live CloudBase smoke:
  - `candidateSongs`: returned `ok: true`.
  - `roundTripDraft`: returned `ok: true` with structured steps and evidence.
  - `showRecap`: returned `ok: true` with Bilibili metadata only.
  - Latest 2026-06-16 retry: `candidateSongs` returned 10 items, `roundTripDraft` returned 3 steps and 2 evidence items using the iOS request shape, and `showRecap` returned 3 items.

Release progress:

- Created App Store provisioning profile `BeforeShow App Store` (`B47S84UKK6`, UUID `a9d4db41-da2e-4aba-91ae-85b956b46fda`).
- Built distribution-signed archive at `/tmp/beforeshow-asc/BeforeShow-distribution.xcarchive`.
- Created distribution-signed manual IPA at `/tmp/beforeshow-asc/BeforeShow-manual.ipa`.
- Set App Store version `1.0` copyright to `2026 Yang Pan`; `asc validate` blocking count dropped from `34` to `33`.
- Verified StoreKit local config and shared Xcode scheme point at `BeforeShow/Resources/BeforeShow.storekit`; product IDs match `com.doublewaterapps.beforeshow.pro.monthly` and `com.doublewaterapps.beforeshow.pro.yearly`.
- Verified ASC app/version state: app ID `6780078298`, version ID `09ededb4-02b4-4e84-9a4a-874ee21cbda3`, state `PREPARE_FOR_SUBMISSION`, no uploaded builds.
- Verified subscription review screenshots are now visible to ASC:
  - Monthly review screenshot `49e34188-f880-4802-9a4b-caf47b5398a6`.
  - Yearly review screenshot `20a44dc5-ac64-486f-a9c8-2bd81b761487`.

Remaining blocker:

- Apple object-storage build uploads from this local environment still fail:
  - Historical screenshot upload attempts hit TLS/SSL failures at `northamerica-1.object-storage.apple.com`, but `asc validate subscriptions` now confirms both subscription review screenshots are attached.
  - Build upload: presigned `PUT` to `northamerica-1.object-storage.apple.com` failed with `EOF` after retries, including 2026-06-16 retries of `asc builds upload --app 6780078298 --ipa /tmp/beforeshow-asc/BeforeShow-manual.ipa --verify-timeout 60s`.
- TestFlight/manual device QA remains pending until the build can be uploaded.
- ASC readiness remains incomplete independent of the upload blocker: metadata URLs/copy, review contact, app availability, app screenshots, age rating, privacy policy URL, and App Privacy publish confirmation are still required.
