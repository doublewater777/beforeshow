# BeforeShow Live Activity · verified product facts

- Prototype target: iPhone 17 class, 402×874 pt canvas.
- Product surface: a quiet countdown for the current show, not a ticket wallet or live event tracker.
- Product timing anchor: the existing local-notification rhythm already has a time-sensitive milestone at `T−3h`.
- Brand source of truth: `DESIGN.md` and `WidgetTheme`.
  - Background `#05070D`
  - Surface `#0D111B`
  - Raised surface `#151A27`
  - Foreground `#F2F3F7`
  - Muted `#9399AA`
  - Dim `#646B7D`
  - Accent `#E8C78E`
  - Live red `#FF6B75`
- Apple platform constraints, verified 2026-08-24:
  - A standard Live Activity can remain active for up to eight hours.
  - After it ends, the Lock Screen presentation may remain for up to four additional hours.
  - `staleDate` marks content as out of date; it does not dismiss the Live Activity.
  - Scheduled Live Activities are available on iOS 26 and require an alert configuration.
  - Live Activities do not use WidgetKit timelines; system time data sources can update displayed time without running app code.
- Apple HIG layout guidance, verified 2026-08-24:
  - Support compact, minimal, expanded, and Lock Screen presentations.
  - Compact content should contain only the most important current information.
  - Expanded content should preserve the relative placement of compact elements and wrap tightly around the TrueDepth camera.
  - Lock Screen content uses a standard 14-point margin and should avoid imitating a notification.
  - Dynamic Island backgrounds remain opaque black; custom color belongs on key text and content.
  - Locale testing must account for text length, date/time formatting, layout direction, and font variation.
  - HIG discourages using color as the only accessible state signal. This prototype uses color as the only *visual* phase signal in compact/expanded island presentations while providing explicit phase semantics to VoiceOver.

Sources:

- https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- https://developer.apple.com/documentation/activitykit/activitycontent/staledate
- https://developer.apple.com/documentation/swiftui/timedatasource
- https://developer.apple.com/design/human-interface-guidelines/live-activities
- https://developer.apple.com/design/human-interface-guidelines/accessibility
- https://developer.apple.com/design/human-interface-guidelines/layout
