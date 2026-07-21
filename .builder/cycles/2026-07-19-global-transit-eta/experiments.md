# Global Transit ETA Experiments

Implementation verification:

- Unit test that public transit selects ETA calculation while other map modes select route calculation.
- Unit test that an ETA-only transit result produces a generic, non-invented timeline.
- Unit test that a manual duration can produce a transit plan without route distance.
- iPhone 17 simulator verification of the saved transit card and Apple Maps action.

Product measurement after release:

- Observe whether transit users successfully save plans after selecting public transit.
- Capture feedback about missing in-app line and transfer details.

Pass threshold: tested flows save a plan through both ETA success and manual fallback, with no invented route facts.

Loop-back trigger: ETA coverage or Apple Maps handoff prevents users in a material region from completing the plan, or transfer details prove necessary for the core value.
