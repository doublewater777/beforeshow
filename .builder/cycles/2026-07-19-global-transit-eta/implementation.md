# Global Transit ETA Implementation

Build:

- Route calculation strategy distinguishes full route calculation from ETA calculation.
- Public transit maps ETA response into duration, optional distance, and no provider steps.
- Transit timeline displays a generic travel node directing users to Apple Maps for details.
- Transit ETA errors reveal a manual duration field and allow saving an estimate.
- Existing Apple Maps URL opens in transit mode.

Do not build:

- AMap, Google Routes, or another transit provider.
- Provider-specific transfer models.
- New map or form components outside the current design system.

Dependencies: MapKit, existing route provider boundary, existing form and home route card.

Handoff: if in-app transit details become required, replace only the transit implementation behind `TravelRouteProviding` and review provider display/attribution terms.
