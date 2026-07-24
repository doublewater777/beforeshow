# Results

Removed the song/setlist-guess feature from the shipped iOS app:

- No home, library, detail, notification, or settings entry remains.
- Candidate-song and artist-interest SwiftData models are no longer registered.
- Generation, editing, sharing, music-platform, usage-limit, and prototype code was deleted.
- Pro now unlocks only unlimited saved shows.
- Photo-library add permission and stale local-data copy were removed.

Verification:

- `rg` found no candidate-song or setlist identifiers in iOS Swift or plist sources.
- The iOS app built successfully for the iPhone 17 simulator.
- All 76 iOS tests passed.
- The app launched successfully on iPhone 17 and the home screenshot contains only the current-show hero and countdown/state card.

Evidence:

- `docs/screenshots/2026-07-23-home-without-setlist-guess.png`
