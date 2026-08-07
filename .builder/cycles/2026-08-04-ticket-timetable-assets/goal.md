# Ticket and Timetable Assets

## User problem

A concert attendee may have a ticket screenshot, a photographed ticket stub, or a venue timetable that they want at hand for the current show. BeforeShow currently has no private, show-bound place for those references.

## Target user and behavior change

The target is an individual BeforeShow user preparing for or attending one current show. After this increment, they should be able to add one ticket image and one timetable image from the Current surface, inspect them later, replace them, or remove them without treating either image as an official ticketing system.

## Success

- Current exposes stable, accessible shortcuts for ticket and timetable assets.
- Each show can retain at most one ticket and one timetable image.
- Images persist locally, remain bound to the correct show, and are absent from Companion CloudKit sharing.
- Deleting a show or clearing local data removes the app-owned asset records and files.
- The full iOS suite and focused asset/navigation tests pass.

## Out of scope

OCR, ticket validation, ticket-wallet integration, ticket resale, cloud sync, cross-device restoration, and automatic timetable extraction.
