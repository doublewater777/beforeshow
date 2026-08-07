# Implementation

- Add `ShowAsset` records for ticket and timetable images with one unique key per show/kind.
- Store versioned JPEG revisions under Application Support with backup exclusion and safe show/kind-relative paths.
- Add Current shortcuts, PhotosPicker import, preview, replacement, deletion, and a zoomable viewer.
- Keep assets out of the Companion CloudKit payload and explain upload, sharing, and iOS-backup boundaries in privacy copy.
- Coordinate ticket/timetable and memory media commits, reconciliation, show deletion, and local-data clearing with one app-wide media permit so SwiftData and file operations cannot interleave.
- Fail closed if the durable Application Support location is unavailable; do not persist user assets in a temporary directory.
- Preserve unrelated current-show memory-phase changes merged from `origin/main`.
