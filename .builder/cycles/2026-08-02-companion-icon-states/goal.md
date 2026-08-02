# Companion Icon States

## User problem

A music live-goer can share the current show with a friend, but the existing companion shortcut never tells them whether an invitation is waiting, confirmed, canceled, or already part of a shared footprint.

## Target user and behavior change

The target is an individual BeforeShow user coordinating one show with one friend. After this increment, they should open the stable companion shortcut, send an invitation, record confirmation or cancellation, and recognize the current state without leaving the Current surface.

## Success

- None, pending, confirmed, canceled, and ended-footprint presentations match the supplied prototype.
- Companion name and state survive an app restart.
- The system share sheet remains the invitation handoff.
- The full iOS test suite passes and iPhone 17 screenshots cover the changed UI.

## Out of scope

Accounts, server-delivered acceptance, multi-person groups, chat, location sharing, photos, and public social collections.
