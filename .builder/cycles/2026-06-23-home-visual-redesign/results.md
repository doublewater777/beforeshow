# Home Visual Redesign Results

2026-06-23 implementation result:

- Home uses a single poster-led layout (半屏封面). Style selection removed from Settings.
- Current home now keeps only the "当前现场" caption instead of a large status heading.
- Home primary actions are state-aware and limited to two entries, followed by expandable All Tools.
- Music festivals show a read-only horizontal lineup row.
- Ended-show home excludes feeling/recap-style entries and keeps the next-show prompt.
- My Shows no longer uses a separate current label/section; the current show is highlighted in place with a gradient border.
- Automatic selection keeps a recently ended show through the 3-day retention window even when a near-future show exists.

Verification:

- Focused selection tests: `9 tests`, `0 failures`.
- Full iOS test suite: `91 tests`, `0 failures`.
