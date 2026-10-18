# T08 — timetable positioning validation (#339)

## Decision (2026-10-18): keep the UIKit bridge

Not migrated. The matrix needs unconditional no-bounce plus directional lock; the iOS 27 SDK
offers only automatic / always / basedOnSize bounce strategies and no directional-lock modifier,
so the `UIScrollView` configuration bridge stays regardless. Moving only positioning to
`scrollPosition` would run two mechanisms on one scroll view without removing any code, so it
fails the ticket's "delete what becomes unused" bar. Revisit when SwiftUI exposes
directional lock and no-bounce.

Measured on iOS 27 simulator (bridge): return-to-now after a manual scroll lands within 0.5 s on
both the first and second request, horizontal lane unchanged.

Scope: iOS 17 minimum and iOS 27 latest. No persistence, visual matrix, or bottom-navigation changes.

## Contracts

`TimetableExperienceTests.testMatrixInitialPositionAndRepeatedReturnToNowPreserveHorizontalLane`
hosts the production matrix with six stages. It checks initial placement (now at 35% of the
vertical viewport), repeated return requests after manual scrolling, unchanged horizontal
lane, top/bottom clamping, and a request outside the day's range resetting to the top.
(A day must have stages — `TimetableDay` rejects empty days — so the empty-day axis is
covered at the layout level below.)
`testOvernightMatrixNowCoordinatesUseFestivalTimeZoneAndInclusiveBounds` checks literal
coordinates around midnight, inclusive schedule boundaries, inverse time mapping, and an
empty day's own 14:00–22:00 axis. Existing large-matrix coverage checks buffered card loading.

Run these contracts using the signed build command in AGENTS.md and
`-only-testing:BeforeShowTests/TimetableExperienceTests`.

## Native candidate

Apply `scrollPosition($position)` directly to the inner vertical `ScrollView`, with
`@State var position = ScrollPosition(edge: .top)`, and observe
`contentOffset.y + contentInsets.top` through `onScrollGeometryChange` into the existing
`TimetableMatrixViewport`. On the existing initial/day-change and return-request events,
call `position.scrollTo(y: max(0, (layout.nowY ?? 0) - gridHeight * 0.35))`.
Gate the candidate at its true availability, iOS 18, retaining the bridge for iOS 17.

Apple references:
- https://developer.apple.com/documentation/swiftui/scroll-views
- https://developer.apple.com/documentation/swiftui/view/onscrollgeometrychange(for:of:action:)

Geometry observation must be attached to the intended scroll view: Apple documents that
only the first scroll view participates when a modifier finds several. The SDK's bounce
strategies are automatic/always/basedOnSize; none replaces this matrix's unconditional
no-bounce plus directional-lock configuration. Positioning success alone does not justify
removing that configuration bridge.

## Manual acceptance sequence (both supported OS versions)

1. Open a live, six-stage timetable: now should start 35% down the grid, clamped at its ends.
2. Drag horizontally to later stages, then vertically and diagonally: headers stay pinned,
   columns align, the time ruler stays at the left, and axes do not drift together.
3. Drag beyond all four edges: no elastic bounce. Tap a performance, dismiss its inspector,
   and tap an empty slot: taps must still work after scrolling.
4. Scroll away and tap “回到现在” twice, scrolling between taps: return to now without changing
   the selected horizontal lane. Verify the animation and ability to interrupt it by touch.
5. Select a future date, an empty day, and the live day again: unavailable now controls disappear,
   empty/future days start at the top, and the live day repositions.
6. Use an overnight 22:00–02:00 set with now at 00:30 in the festival time zone: the same official
   day contains the now marker. Close/reopen the timetable and verify fresh initial positioning.
7. Repeat on a large timetable (12 stages × 24 sets); check visible cards load while scrolling,
   no sustained hitching, and no offscreen-card preparation regression.
