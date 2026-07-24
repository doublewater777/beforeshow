# Retro

Belief updated: importing incomplete show data is safe only when missing required fields remain structurally missing. A visually plausible fallback time is too easy to mistake for provider data.

What worked:

- Moving `startTime` to an optional draft value made parser, form, validation, and tests agree on one invariant.
- Keeping notification activation after the successful SwiftData save avoided a partially committed add flow.
- Tracking only files inside the app-managed cover directory allowed cleanup without touching remote or user-owned URLs.
- Destination-owned success feedback removed the race between a toast and sheet dismissal.
- Simulator screenshots caught a cover image that was logically compact but still painting outside its frame; clipping after the fixed-height frame fixed the actual pixels.
- Accessibility inspection exposed the back button's undersized hit area, so the cancel action now owns a 44-point target.
- Treating status changes as reversible domain actions made cancellation and postponement easier to understand than a generic danger zone.

What remains uncertain:

- The first-save permission prompt may still feel abrupt even though its timing is now correct.
- Simulator automation could capture the changed form, but PhotosPicker and provider failure recovery still need an unlocked-device walkthrough.

Decision: implementation and simulator verification are complete; retain the cycle at business-model stage until user validation confirms the completion handoff.
