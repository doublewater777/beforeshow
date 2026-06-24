# Core Show Loop Implementation

Build:

- Connect Tonight First Listen to CloudBase candidate generation and saved candidate display.
- Connect Round Trip Plan to CloudBase `roundTripDraft`, editable text, local save, and Pro repeat gate.
- Connect Preview Before Show to local artist/venue/entry/weather guidance plus CloudBase `showRecap`, lightweight Bilibili metadata storage, official external playback, and Pro repeat gate.
- Add persistent Show Preparation checklist, reminder date, and notes.
- Keep Show Fragments local: text, gallery references, and app-created audio.
- Keep Pro membership and StoreKit purchase/restore as the limiter unlock.

Will not build:

- Ticket screenshot upload.
- Lyrics, media caching, Bilibili comments, or page scraping storage.
- Accounts or cloud sync.

Dependencies:

- CloudBase `/generate` HTTP function.
- StoreKit products in App Store Connect and local `.storekit`.
- SwiftData lightweight model update.

Release notes:

- V2.1 is a TestFlight-usable core loop, not yet a fully polished public launch.
