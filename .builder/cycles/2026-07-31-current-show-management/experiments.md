# Experiments

Test the section with seeded shows in at least these states: far before, same-day before, live, manually ended, postponed, and canceled.

Measure in a release build or usability pass:

- Whether users can add or open the current show without instruction.
- Whether live users can finish the show and choose the correct time path on the first attempt.
- Whether ticket, route, reminder, and companion remain visible and usable before, during, and after a show.
- Whether users can recover from an accidental end from the detail page.
- Whether users understand that Current shows only the nearest two later shows and can reach the complete secondary management page when more exist.
- Whether search and status filters locate future, ended, postponed, and canceled records without a hero card.

Pass threshold: all scripted flows complete without explanatory copy or an overflow menu; no invalid earlier curtain time can be saved; all state transitions update immediately.

Loop-back trigger: any scripted state hides a shortcut, Current expands beyond two later shows, a record disappears from every management filter, or users cannot locate correction/undo in detail.
