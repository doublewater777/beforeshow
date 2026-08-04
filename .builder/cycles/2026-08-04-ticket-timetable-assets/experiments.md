# Experiments

## Simulator verification

1. Verify Current shows ticket and timetable shortcuts for the selected show.
2. Add each image from PhotosPicker and confirm the preview, saved state, and viewer.
3. Replace and delete each asset, confirming the old revision is not displayed after a replacement.
4. Switch shows and verify assets never cross show boundaries.
5. Relaunch or trigger active reconciliation and verify valid records remain while orphan files/records are removed.
6. Clear local data and verify both records and app-owned files are removed without deleting system Photos originals.

## Measurement

- Pass: all local flows are reachable, persisted, show-isolated, and accessible.
- Pass: focused asset tests, navigation tests, and the full iOS suite pass with zero failures.
- Loop back: users need official ticket behavior, multiple assets per kind, or cannot distinguish the app copy from a valid admission credential.
