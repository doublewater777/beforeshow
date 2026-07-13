# Home horizontal clipping, 2026-07-13

## Symptom

On the iPhone 17 home screen, the bottom home tools area was clipped on both sides:

- The `Tips` card started off the left edge.
- The `也可以顺手看看` section title and shortcut cards used the same oversized width.
- The floating bottom navigation was visually present but was not the cause of this issue.

Reference screenshots:

- Before: `apps/ios/screenshots/manual-qa-2026-07-13/home-clip-fix-2026-07-13.png`
- After: `apps/ios/screenshots/manual-qa-2026-07-13/home-horizontal-clipping-fixed-2026-07-13.png`

## Root Cause

`GeometryReader` inside the current tab container reported a layout width around `547pt`, while the actual iPhone 17 viewport was `402pt`.

The home content then computed widths from the reported container width. A `511pt` content area was centered in a `402pt` viewport, which pushed the tools section roughly `54pt` off both sides.

## Fix Pattern

When sizing home content from `GeometryReader`, clamp the container width to the real viewport before subtracting horizontal insets:

```swift
min(containerWidth, viewportWidth) - horizontalInset * 2
```

This is captured in `HomeLayoutMetrics.contentWidth(for:viewportWidth:)` and covered by `NavigationTests.testHomeContentWidthKeepsSymmetricHorizontalInsets`.

## Debug Checklist

If this comes back:

1. Confirm the visible viewport width from the simulator or UI test.
2. Log or assert the `GeometryReader` width used by the affected section.
3. Compare the first clipped element frame against the viewport frame.
4. Verify shared content width is applied to the poster, Tips card, and shortcut grid.
5. Re-save a screenshot on iPhone 17 after the fix.

Expected iPhone 17 values from this fix:

- Viewport width: `402pt`
- Horizontal inset: `18pt`
- Content width: `366pt`

## Verification Used

- `xcodebuild test -project BeforeShow.xcodeproj -scheme BeforeShow -destination 'platform=iOS Simulator,name=iPhone 17'`
- Manual UI screenshot: `apps/ios/screenshots/manual-qa-2026-07-13/home-horizontal-clipping-fixed-2026-07-13.png`
