# Separate full-playback capability from the active playback session

BeforeShow treats Apple Music authorization/subscription state and the currently active transport as separate concerns. A confirmed loss of full-playback capability (denied, restricted, or account-limited) ends an active full-catalog session without ejecting the disc or deleting local listening data; the current track remains selected and its progress resets. A transient capability-check failure does not end an already established full-catalog session, because an inability to verify access is not evidence that access was lost.

This preserves continuity without overstating access: cached records remain browsable, previews may continue, capability recovery never auto-plays or swaps an in-progress preview to full audio, and UI labels follow the actual active transport while separately surfacing uncertainty about future full playback.
