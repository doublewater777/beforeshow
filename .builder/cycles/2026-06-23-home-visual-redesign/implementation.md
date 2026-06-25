# Home Visual Redesign Implementation

## Built

- Added `HomeStyle` preference (半屏封面, the only style). Style selection Settings removed.
- Reworked current-show home to remove the large status heading and keep only the "当前现场" caption.
- Added poster-led hero variants that use top-aligned cover imagery.
- Limited home primary entries to two state-aware actions plus expandable All Tools.
- Added a read-only horizontal music-festival lineup row.
- Removed the separate current-show section in My Shows; the selected show is now highlighted in-place with the existing gradient border.
- Updated automatic current-show selection so post-show retention wins over a near future show until the retention window expires.
- Added a regression test for the near-future retention handoff.

## Not Built

- New AI generation or Pro allowance behavior.
- Interactive festival artist tracking on home.
- New screenshot routes for each home style.

## Dependencies

- Existing SwiftData `Show` and `CurrentShowSelection` models.
- Existing `CurrentShowTimeState` cross-day and retention semantics.
- Existing tool destination screens.

## Release Notes

Home now feels closer to the SplashView stage language with a poster-led layout.
