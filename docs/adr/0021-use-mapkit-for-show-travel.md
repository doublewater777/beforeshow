---
status: accepted
---

# Use MapKit for show travel

BeforeShow will use Apple MapKit as the single default provider for outbound and return routes in 「怎么去」, superseding the earlier AMap decision. Driving, walking, and cycling use full MapKit route calculation. Public transit uses MapKit ETA because the public API does not expose complete transit route steps; BeforeShow shows only the estimated duration and opens Apple Maps for lines and transfers. If transit ETA is unavailable, the user may enter the duration manually. User-supplied custom travel is a separate product mode and does not map to `.any`. This keeps one globally available iOS provider while ensuring the app never invents transit stations, lines, or transfers.
