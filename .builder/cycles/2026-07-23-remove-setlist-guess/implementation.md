# Implementation

Remove:

- Candidate-song and artist-interest SwiftData models.
- Setlist generation, editing, sharing, and prototype UI.
- Home and show-detail entry points.
- Candidate-song Pro generation allowance and benefit copy.
- Candidate-song notification deep links.
- Candidate-song-specific local-data and photo-library copy.
- Candidate-song tests and Xcode project references.

Keep:

- Current-show selection and time-state logic.
- Show creation, editing, notifications, and subscription save limit.
- Shared CloudBase transport used by show-link parsing.

Verification:

- Regenerate the Xcode project after source deletion.
- Run the remaining iOS test suite.
- Build and launch on the iPhone 17 simulator.
- Save a screenshot showing the simplified home screen.
