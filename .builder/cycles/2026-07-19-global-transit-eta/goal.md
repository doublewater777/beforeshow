# Global Transit ETA Goal

Feature: Generate globally usable public-transit plans from MapKit ETA.

Linked stage: `.builder/stages/09-business-model.md`

Target user: BeforeShow iOS users planning travel to or from a show in any supported region.

User problem: selecting public transit currently fails because the app requests full transit route steps that MapKit does not expose through `calculate()`.

Desired behavior change: users can save a time-based public-transit plan, open Apple Maps for line and transfer details, and manually enter duration when ETA is unavailable.

Success criteria:

- Public transit uses `calculateETA()` and saves its duration and distance.
- Saved transit plans contain no invented stations, lines, or transfers.
- Transit ETA failure reveals a manual duration field without discarding the form.
- Saved non-custom plans retain a working Apple Maps action.

Out of scope:

- A global multi-provider transit backend.
- In-app transit station, line, fare, or transfer details.
- Changes to driving, walking, cycling, or custom-route behavior.
