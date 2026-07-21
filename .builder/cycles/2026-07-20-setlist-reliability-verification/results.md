# Setlist Reliability Verification Results

2026-07-20 result:

- Setlist-focused Node tests: 8 passed, 0 failed.
- Full iOS suite on iPhone 17: 182 passed, 0 failed.
- Full CloudBase suite: 51 passed, 1 unrelated live Damai integration failure because the third-party page omitted `startTime`.
- Live generation completed with 12 validated songs.
- Dismissing regeneration preserved the prior 12-song catalog after the cloud request window elapsed.
- Festival lineup opened with participating artists selected; a local deselection followed by Cancel was absent after reopening.
- Ended-show home copy remained “回看这场的歌单猜想”.
- The edit screen exposed drag handles and accessibility move actions; automated HID swipes did not trigger SwiftUI drop, so destination behavior is backed by focused unit tests rather than an automated drag screenshot.

Screenshots: `docs/screenshots/2026-07-20-setlist-verification/`.

Post-release responsiveness and real-user behavior have not been observed yet.
