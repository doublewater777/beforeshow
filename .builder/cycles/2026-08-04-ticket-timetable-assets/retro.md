# Retro

## What we believed

Ticket and timetable images looked like an isolated local feature, but they share the same show lifecycle and SwiftData context as memory media.

## What we learned

The important invariant is broader than a ticket-specific media lock: every app-owned media commit and every operation that deletes a show must share one permit. Durable storage failures also need an explicit fail-closed path, and file cleanup after a committed database deletion must be reported as best-effort cleanup rather than an atomic rollback.

## Decision

Close this implementation cycle as implementation-complete and user-value-pending. Keep official ticket validation, OCR, and cloud synchronization out of scope until real-user evidence requires them.

## Next action

Use TestFlight or device feedback to measure whether Current users add and revisit either asset, and whether the local-only / non-official-ticket boundary is understood.
