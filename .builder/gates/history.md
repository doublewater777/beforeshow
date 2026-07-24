# Gate History

## 2026-06-08

Stage: fake-door

Cycle: `.builder/cycles/2026-06-08-fake-door-validation/`

Decision: implementation-ready, not validated yet.

Reason: the fake-door surface now exists and can collect local evidence, but no target-user traffic has been run.

## 2026-06-14

Stage: business-model

Cycle: `.builder/cycles/2026-06-14-pro-membership/`

Decision: hypothesis only, not validated.

Reason: Pro membership is now part of the intended V2.1 packaging, but free allowance, price, and payment behavior evidence are still undecided.

## 2026-06-16

Stage: business-model

Cycle: `.builder/cycles/2026-06-16-core-show-loop/`

Decision: implementation in progress, validation pending.

Reason: the V2.1 goal has shifted from membership alone to a TestFlight-usable loop across Tonight First Listen, round-trip planning, preview, preparation, fragments, and Pro repeat-generation limits.

## 2026-06-23

Stage: business-model

Cycle: `.builder/cycles/2026-06-23-home-visual-redesign/`

Decision: implementation in progress, validation pending.

Reason: the V2.1 loop exists, but the home surface needs a stronger theatrical visual language, clearer current-show focus, and a simpler two-entry action model before user validation.

## 2026-07-19

Stage: business-model

Cycle: `.builder/cycles/2026-07-19-global-transit-eta/`

Decision: implementation in progress, validation pending.

Reason: MapKit can return public-transit ETA globally where supported but does not expose complete transit route steps; the product will test whether ETA, manual-duration fallback, and Apple Maps handoff are sufficient for trip planning.

## 2026-07-20

Stage: business-model

Cycle: `.builder/cycles/2026-07-20-setlist-reliability-verification/`

Decision: implementation and simulator verification complete; user validation pending.

Reason: generation now requires an explicit contract-valid final response, cancellation preserves the prior catalog, and festival lineup edits remain local until confirmation; responsiveness and real-user trust still require release observation.

## 2026-07-23 · Add Show Reliability

Stage: business-model

Cycle: `.builder/cycles/2026-07-23-add-show-flow-reliability/`

Decision: implementation and simulator verification complete; user validation pending.

Reason: required time data, notification activation, duplicate-save protection, actionable recovery, and local cover cleanup now share tested invariants; release-user observation is still needed for the permission and completion handoff.
