# Retro

What worked:

- Reusing the existing `Show`, current-show selection, notification, widget, and detail navigation logic kept the feature connected to real data.
- Modeling user-confirmed completion as an authoritative `endedAt` boundary made live, ended, edit, and undo behavior consistent across the app and shared timing code.
- Direct user feedback showed that phase-based shortcut visibility reduced discoverability, so the row now remains stable across states.
- Ambient treatment should communicate color and atmosphere without repeating recognizable cover geometry behind the actual poster; otherwise the two layers read as a layout error.
- A reusable image view's own clipping is not sufficient after an outer fixed frame changes its proposed size; the final hero container must own the definitive clip shape.
- The phrase “现场管理” was ambiguous between the existing tab, the countdown card, and the new secondary page. The resolved structure is: Current owns a two-row summary, the new destination owns complete management, and the existing tab remains untouched.

Follow-up learning:

- Future UI coverage should assert that all four shortcuts remain present across the complete live-to-ended transition.
- The existing floating app navigation overlaps the final shortcut row until the content is scrolled slightly; this is pre-existing app chrome and was retained because the requested scope was the current-show section only.
