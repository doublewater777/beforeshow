# Implementation

- Add local SwiftData fragment/media records tied to a real `Show` identifier.
- Store app-owned media under Application Support and keep only durable relative paths in SwiftData.
- Add a chronological memory screen with one fixed create action, empty-state copy, media paging, editing, and confirmed deletion.
- Use the system camera controller without an app-defined duration limit and system PhotosPicker for ordered photo/video multi-selection.
- Stage imported/captured media before composition so temporary picker URLs are never treated as durable data.
- Extend the existing Current quick-action presentation to three equal-width cards in one row without changing Route or Companion behavior.
- Add camera and microphone usage descriptions; do not request full photo-library access.
- Add focused model/storage/flow tests and iPhone 17 screenshot evidence.

The concrete model, state, file, and concurrency structure follows the existing SwiftData/SwiftUI project rather than the earlier product document's illustrative class and method names.
