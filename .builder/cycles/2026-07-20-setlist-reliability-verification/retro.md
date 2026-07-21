# Setlist Reliability Verification Retro

Belief: correctness at the final-response boundary is more important than rendering provider-local drafts immediately.

Learning: green happy-path tests did not protect against cleanly truncated streams, mismatched streamed/final data, stale task cleanup, or false-positive cancellation assertions. Explicit final-state types and adversarial tests made those boundaries enforceable.

Decision: implementation and simulator verification are complete for the reviewed scope. Keep UI responsiveness as a product observation and add a UI drag test when the automation stack can drive SwiftUI drag-and-drop reliably.
