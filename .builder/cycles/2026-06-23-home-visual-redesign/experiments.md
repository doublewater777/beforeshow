# Home Visual Redesign Experiments

## Test Plan

- Run local iOS build and tests after implementation.
- Use simulator/manual QA across home states: before, today, post-show, ended, postponed, canceled, empty.
- Ask prototype users whether they can find all tools.

## Measured Signals

- Users open one of the two primary actions without scanning a dashboard.
- Users can expand All Tools and navigate to candidate songs, round-trip, preparation, videos, or fragments.
- Users understand the current show in My Shows through gradient highlight alone.
- Post-show users are not surprised by the 3-day retention behavior.

## Pass Threshold

- Build and regression tests pass.
- In manual QA, every home state has at most two primary entries plus expandable All Tools.
- Users can describe the selected current show and next action within a few seconds.

## Loop-Back Trigger

- Users miss key tools because All Tools is hidden.
- (Style selection removed; these triggers are no longer applicable.)
