# Setlist Reliability Verification Experiments

Implementation verification:

- Unit tests for truncated JSON, provider fallback, streamed/final disagreement, and explicit final snapshots.
- Session tests for cancellation, partial failure, clean close without final, usage marking, lineup defaults, draft persistence, legacy repair, and drop destination indices.
- Full iOS test suite on iPhone 17.
- iPhone 17 simulator walkthrough of live generation, dismiss cancellation, festival lineup cancel, editing affordances, and ended-show copy.

Pass threshold: all setlist-focused tests pass, the full iOS suite passes, and simulator evidence shows no partial overwrite after cancellation.

Loop-back trigger: a provider can still produce persisted partial data, a cancelled run consumes allowance, or a lineup cancellation changes saved interests.
