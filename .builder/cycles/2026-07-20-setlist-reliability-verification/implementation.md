# Setlist Reliability Verification Implementation

- Generation snapshots distinguish progress from a validated final result.
- The session persists and marks usage only after receiving the explicit final snapshot.
- Truncated JSON is rejected instead of being synthesized from extracted items.
- Provider-local streamed drafts are held until the final response passes the contract; fallback output cannot mix with failed-provider items.
- Generation tasks use run identities so cleanup from an older task cannot clear a newer run.
- Festival artists added during first-generation selection remain drafts until confirmation.
- Existing lineup defaults, legacy repair, ended copy, and drop destination behavior have focused regression tests.

Dependencies: SwiftData, CloudBase SSE transport, provider response contracts, and the existing setlist design system.
