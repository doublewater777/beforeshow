# App Store Connect Prep

## Completed

- App Store Connect app record created:
  - App ID: `6780078298`
  - Store URL: `https://apps.apple.com/us/app/id6780078298`
  - Name: `开场前`
  - SKU: `beforeshow-ios`
  - Primary language: `zh-Hans`
  - Version: `1.0`
  - Version ID: `09ededb4-02b4-4e84-9a4a-874ee21cbda3`
  - App Info ID: `affd6168-3d9a-4a61-9abd-b9cd8b428b77`
- Bundle ID created in Apple Developer / App Store Connect:
  - Bundle ID: `com.doublewaterapps.beforeshow`
  - Bundle ID resource ID: `5NWJ7ZT3UH`
  - Name: `BeforeShow`
  - Team ID / Seed ID: `29C8MS76CZ`
- Categories configured:
  - Primary: Music (`MUSIC`)
  - Secondary: Lifestyle (`LIFESTYLE`)
- Content rights configured:
  - `USES_THIRD_PARTY_CONTENT`
  - Reason: V2.1 references third-party music titles and user-selected gallery media, but does not host or play third-party video.
- Existing iOS Distribution certificate found:
  - Certificate ID: `XCJMLU87V5`
  - Name: `iOS Distribution: Yang Pan`
  - Expires: `2027-05-05T01:37:20.000+00:00`
  - SHA-1 fingerprint: `DC:56:8C:69:9D:63:FE:18:CE:04:86:27:D8:35:15:E2:64:5D:C2:9F`
- App Store provisioning profile created for BeforeShow:
  - Profile ID: `B47S84UKK6`
  - Name: `BeforeShow App Store`
  - UUID: `a9d4db41-da2e-4aba-91ae-85b956b46fda`
  - `get-task-allow`: `false`
- Distribution-signed archive created on 2026-06-16:
  - Path: `/tmp/beforeshow-asc/BeforeShow-distribution.xcarchive`
  - Signing identity: `iPhone Distribution: Yang Pan (29C8MS76CZ)`
  - Provisioning profile: `BeforeShow App Store`
- Distribution-signed manual IPA created on 2026-06-16:
  - Path: `/tmp/beforeshow-asc/BeforeShow-manual.ipa`
  - Size: about `2.8M`
  - Bundle ID: `com.doublewaterapps.beforeshow`

## App Store App Record

Created with these fields:

- Platform: iOS
- Name: `开场前`
- Bundle ID: `com.doublewaterapps.beforeshow`
- SKU: `beforeshow-ios`
- Primary language: Simplified Chinese (`zh-Hans`)
- Initial version: `1.0`
- Category: Music
- Secondary category: Lifestyle
- Subtitle: `开场之前，先进入状态`

## Later App Store Setup

- Configure StoreKit subscriptions:
  - Product IDs must exactly match the app catalog and local StoreKit config:
    - `com.doublewaterapps.beforeshow.pro.monthly`
    - `com.doublewaterapps.beforeshow.pro.yearly`
  - Pro monthly: `¥12/月`
  - Pro yearly: `¥68/年`
  - No free trial in V2.1
  - App Store Connect group created:
    - Group ID: `22160385`
    - Reference name: `BeforeShow Pro`
    - Group localization: `Pro会员` (`zh-Hans`)
  - App Store Connect subscriptions created:
    - Monthly subscription ID: `6780727285`, product ID `com.doublewaterapps.beforeshow.pro.monthly`, period `ONE_MONTH`, China price `CNY 12.0`
    - Yearly subscription ID: `6780727360`, product ID `com.doublewaterapps.beforeshow.pro.yearly`, period `ONE_YEAR`, China price `CNY 68.0`
  - Current subscription state on 2026-06-16: `MISSING_METADATA`; `asc validate subscriptions` can now see review screenshots for both products, but ASC still reports the state as missing metadata until the app has a build and remaining first-release setup is complete.
  - Review screenshot evidence from `asc validate subscriptions --app 6780078298`:
    - Monthly: `id=49e34188-f880-4802-9a4b-caf47b5398a6`
    - Yearly: `id=20a44dc5-ac64-486f-a9c8-2bd81b761487`
- Add privacy policy and support URLs before submission.
- Add age rating honestly; target low rating without lyrics, community, ticketing, or self-hosted media claims.
- Do not add lyrics, public community, ticketing, or self-hosted video playback metadata claims.

## Pro Subscription Review Copy

- Product name: `Pro会员`
- Subscription model: App Store subscription only; BeforeShow does not create a BeforeShow account.
- Pricing:
  - Monthly: `¥12/月`
  - Yearly: `¥68/年`
  - No free trial in V2.1
- Free allowance:
  - Save 1 `现场`.
  - Use the first-experience package once per feature: candidate songs, outbound trip draft, and return trip draft.
  - Deleting a show does not reset the free AI allowance.
- Pro unlocks:
  - Unlimited saved `现场`.
  - Repeated candidate song generation.
  - Repeated outbound and return draft generation.
- Expired Pro behavior:
  - Existing local data, saved shows, show fragments, and manual edits remain accessible.
  - Users can keep adding show fragments and manually editing saved local content.
  - The app only limits new over-free saved shows and Pro-only generation.
- Copy guardrail: do not mention ads, ad removal, VIP community, account sync, or unlimited AI.

## Privacy And Data Review Notes

- Ticket screenshots: users choose screenshots themselves; V2.1 uses on-device OCR through iOS APIs and does not upload screenshots for recognition.
- OCR fields: extraction is limited to show-related fields such as show name, date/time, city, venue, artists/lineup, and seat/area. The app should not recognize or store order numbers, QR codes, barcodes, ID numbers, phone numbers, buyer names, or payment information.
- Gallery media: show fragments reference photos and videos in the system gallery. BeforeShow does not copy gallery originals into app storage, and clearing app data does not delete those originals.
- App-created audio: voice fragments recorded inside BeforeShow are app-owned sandbox data and are removed when the related app data is cleared.
- AI requests: candidate songs and trip drafts are user-triggered. Requests send only the fields needed for that generation path; the backend does not store long-term user show data.
- Feedback: feedback sends only the message/category and optional diagnostics selected by the user. It must not automatically attach show content, screenshots, gallery media, voice fragments, or generated results.
- Local-first stance: saved shows, preferences, fragments metadata, and app-created audio are local app data in V2.1; there is no BeforeShow account or cloud sync.

## Content Rights And Feature Boundaries

- Lyrics: BeforeShow does not display lyrics in candidate songs, home surfaces, screenshots, or marketing copy.
- Candidate songs: the app stores song title and artist only; it does not create platform playlists or claim an official setlist.
- Ticketing: BeforeShow is not a ticket wallet, ticket trading product, ticket validator, or venue entry tool.

## Human Submission Checklist

- [ ] Add privacy policy URL.
- [ ] Add support URL.
- [ ] Add final screenshots that match the shipped UI and do not show lyrics or private ticket identifiers.
- [x] Set version copyright to `2026 Yang Pan` for App Store version `1.0`.
- [x] Confirm StoreKit products are created in App Store Connect with the exact monthly/yearly prices and no trial.
- [x] Confirm the shared Xcode scheme uses `BeforeShow/Resources/BeforeShow.storekit` for local simulator purchase testing.
- [ ] Paste review notes covering on-device OCR, local-first storage, no lyrics, Pro subscription behavior, and feedback/privacy boundaries.

## TestFlight Manual QA

Run this on a fresh install before submitting the first external TestFlight build:

- [ ] Fresh launch starts without requiring an account and without asking for ticket screenshots.
- [ ] Add one `现场` manually; save succeeds and the new show becomes the current show.
- [ ] Open `候选曲目`; candidate songs generate once, store only song title and artist, and can be edited locally.
- [ ] Open `往返计划`; fill direction info, generate one outbound draft, edit and save it locally.
- [ ] Generate one return draft or save an undecided return note; repeated outbound/return generation as a free user opens Pro.
- [ ] Open `现场准备`; check and uncheck items, save a reminder time, save private notes, then leave and re-enter to confirm persistence.
- [ ] Open `现场碎片`; save text and optional gallery references or app-created audio locally, then re-enter to confirm persistence.
- [ ] Try adding a second `现场` as a free user; saving is blocked with the free limit message.
- [ ] Open `设置 > Pro会员`; monthly and yearly products load with App Store/TestFlight prices for `com.doublewaterapps.beforeshow.pro.monthly` and `com.doublewaterapps.beforeshow.pro.yearly`.
- [ ] Buy monthly Pro in the sandbox sheet; the Pro page shows active status.
- [ ] After purchase, add a second `现场`; save succeeds.
- [ ] After purchase, regenerate `候选曲目`; repeated generation succeeds and replaces the local candidate group after confirmation.
- [ ] Delete and reinstall, then use `恢复购买`; Pro entitlement restores from StoreKit.
- [ ] Verify privacy and copyright boundaries: no lyrics, no uploaded ticket screenshot flow, no self-hosted media playback, and no BeforeShow account/sync prompt.
- [ ] Repeat the free-limit path once with App Store sandbox/TestFlight products, not only the local `.storekit` file.
- [ ] Verify metadata uses approved product language: `现场`, `候选曲目`, `往返计划`, `Pro会员`.

## Current External Blockers

- [x] Deploy the CloudBase `generate` HTTP function. On 2026-06-16, `POST https://beforeshow-d2g0gv0zz4cc249dc-1312569550.ap-shanghai.app.tcloudbase.com/generate` returned `ok: true` with `response.type = candidateSongs`.
- [x] Keep `parseShowLink` deployed. On 2026-06-16, the deployed `/parseShowLink` endpoint accepted the iOS-style JSON body with `appInstanceId` and `appSignature`.
- [x] Before CloudBase deployment, run `npm run prepare:deploy` in `apps/cloudbase-functions` so both `generate` and `parseShowLink` are staged under `.cloudbase/functions`.
- [x] After deployment, repeat the `/generate` smoke test with a non-private test show and confirm it returns `ok: true` with `response.type = candidateSongs`.
- [x] On 2026-06-16, repeat the `/generate` smoke test for `roundTripDraft`; the live endpoint returned `ok: true`, `response.type = roundTripDraft`, and valid evidence.
- [x] Upload App Store review screenshots for subscription IDs `6780727285` and `6780727360`; `asc validate subscriptions` now confirms both review screenshot IDs.
- [ ] Resolve remaining first-release subscription state; current `asc validate subscriptions` warnings are missing optional promotional images, app build count `0`, and app availability comparison unavailable.
- [ ] Run the real TestFlight/manual loop on device after the build is uploaded: free first show, one candidate generation, Pro gate on second show/regeneration, purchase/restore, and post-purchase unlock.

### 2026-06-16 ASC Readiness Snapshot

- `asc apps view --id 6780078298` confirms app name `开场前`, bundle ID `com.doublewaterapps.beforeshow`, primary locale `zh-Hans`, and content rights declaration `USES_THIRD_PARTY_CONTENT`.
- `asc versions list --app 6780078298` confirms iOS version `1.0` / version ID `09ededb4-02b4-4e84-9a4a-874ee21cbda3` is `PREPARE_FOR_SUBMISSION`.
- `asc builds list --app 6780078298` returns `total=0`; no TestFlight build is present yet.
- `asc pricing availability view --app 6780078298` reports app availability is not initialized.
- `asc validate --app 6780078298 --version 1.0 --platform IOS` after setting copyright reports `33` blocking errors, down from `34`.
- Remaining blocking groups:
  - zh-Hans metadata: description, keywords, support URL.
  - Review contact fields: first name, last name, email, phone.
  - Build: no build attached/uploaded.
  - App availability: missing initial availability record.
  - App screenshots: no screenshot sets found.
  - Age rating: all questionnaire fields are still missing.
  - Privacy policy URL: required because subscriptions exist.
  - App Privacy publish state: not verifiable via public API and must be confirmed in ASC.

### 2026-06-16 Upload Blocker Evidence

- Subscription screenshot upload failed at Apple object storage:
  - Host: `northamerica-1.object-storage.apple.com`
  - Operation: presigned `PUT`
  - Error: `LibreSSL SSL_connect: SSL_ERROR_SYSCALL` / HTTP `000`
- Build upload also failed at Apple object storage:
  - Command: `asc builds upload --app 6780078298 --ipa /tmp/beforeshow-asc/BeforeShow-manual.ipa --verify-timeout 60s`
  - Error: `upload operation 0: retry limit exceeded after 4 retries ... Put "https://northamerica-1.object-storage.apple.com/...": EOF`
  - Retry: 2026-06-16 12:02 Asia/Shanghai, same command and same Apple object-storage `EOF`.
  - Latest retry: 2026-06-16 12:09 Asia/Shanghai, same command and same Apple object-storage `EOF`.
- Xcode export with both automatic and manual signing did not produce an IPA because it hung at `IDEDistributionUploadAccountStep`.
- App Store Connect API itself is reachable; the repeated failure is isolated to Apple object-storage upload URLs from the local environment.
- Next manual action: disable or change the local/system proxy or DNS interception, then retry `asc builds upload`. If object storage remains unreachable, upload the build from another network or machine. App Store product screenshots are still separate from subscription review screenshots and remain required for submission.

## Verification Evidence

- iOS tests on 2026-06-16:
  - Command: `xcodebuild test -project apps/ios/BeforeShow.xcodeproj -scheme BeforeShow -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`
  - Result: `78 tests`, `0 failures`
- CloudBase tests on 2026-06-16:
  - Command: `npm test` in `apps/cloudbase-functions`
  - Result: `39 tests`, `0 failures`
