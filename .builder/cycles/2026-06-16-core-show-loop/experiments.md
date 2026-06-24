# Core Show Loop Experiments

Test plan:

- Run iOS tests for model, generation contract, Pro gate, navigation, and local storage.
- Run CloudBase tests and smoke `/generate` for candidate songs plus representative round-trip and recap requests.
- Use TestFlight or local StoreKit to walk the loop: save one show, generate each AI feature once, hit repeat-generation Pro gates, buy/restore Pro, then retry.

Measured signals:

- First saved show reaches at least one generated or saved preparation artifact.
- Users can revisit edited round-trip and preparation content after app restart.
- Pro gate appears only on repeated generation or second saved show.
- No generated response stores lyrics, raw Bilibili media, ticket screenshots, comments, or account data.

Pass threshold:

- The loop is usable without developer intervention on a fresh install.
- Automated tests pass.
- Any ASC/TestFlight blocker has concrete evidence and a manual fallback.

Loop-back trigger:

- Generation quality is too generic to help.
- StoreKit products fail to load in TestFlight.
- SwiftData migration blocks existing installs.
