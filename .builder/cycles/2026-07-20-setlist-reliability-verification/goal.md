# Setlist Reliability Verification Goal

Feature: Make 歌单猜想 generation, cancellation, lineup selection, editing, and ended-show copy trustworthy.

Linked stage: `.builder/stages/09-business-model.md`

Target user: BeforeShow users generating or editing a concert or festival setlist guess.

User problem: a partial or cancelled stream could be mistaken for a completed generation, concurrent runs could race, and festival lineup changes could persist before confirmation.

Success criteria:

- Persist generated songs only after an explicit, contract-valid final response.
- Cancellation and failed or truncated streams preserve the prior catalog and free allowance.
- Starting a new generation cannot be reset by cleanup from an older task.
- Festival lineup defaults and cancel semantics match what the UI promises.
- Editing supports correct destination indices and the ended surface keeps calling the result a guess.

Out of scope: redesigning the setlist surface or changing the Pro packaging.
