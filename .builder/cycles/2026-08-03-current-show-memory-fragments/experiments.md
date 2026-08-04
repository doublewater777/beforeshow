# Experiments

## Simulator verification

On an iPhone 17 simulator:

1. Verify Current shows Route, Companion, and Memory Fragments as one row of three equal-width cards.
2. Open an empty memory timeline and create, edit, and delete a text fragment.
3. Import multiple ordered photos/videos as one fragment with one caption.
4. Verify canceling capture creates no fragment and deleting requires explicit confirmation.
5. Switch the current show and verify counts/content never cross shows; switch back and verify persistence.
6. Relaunch and verify fragment metadata and app-owned media remain readable.

Physical-device camera behavior cannot be proven in Simulator; validate camera availability fallback there and keep a device follow-up for real capture.

## Measurement

- Pass: every local flow is reachable, persisted, accessible, and visually consistent with Current.
- Pass: focused persistence/media tests and the full iOS suite pass.
- Loop back: capture requires redundant choices, media order changes, content crosses shows, or users believe former-show content was deleted.

Release-user frequency and emotional value remain unmeasured until TestFlight use.
