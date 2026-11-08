# Companions are local names

## Status

Accepted — 2026-11-07. Supersedes ADR 0024 and ADR 0034.

## Context

Companions were CloudKit invitations (ADR 0024, 0034): the friend had to install the app, sign in to iCloud and accept before the show counted as shared. Most friends never install the app, so the usual answer to "who did you go with" was never recorded. Invite / pending / end / leave / revoke states confused users, and the companion sheet counted exact name sets while footprint detail counted each person, so "how many times with A" had two answers. Acquisition moves to share images (#387).

## Decision

- A show's companions are `Show.companionNames`, typed or picked from names used on other shows. Non-empty means the show has companions. Add, rename and a single remove are the only edits, available before the show and on past footprints.
- 「与 A 第 N 次」 counts every footprint whose names include A, whoever else came. The companion sheet, the per-person history and footprint detail share this rule (`CompanionHistory`). Name matching and its limits stay as in ADR 0027.
- The CloudKit invite flow is removed: sessions, share UI, invite preparation, join confirmation, clipboard detection, pending inbox, cloud-sync markers, invited onboarding and the shared-footprint card.
- One-time migration `LocalCompanionMigration` (UserDefaults `companion.local-record-migration.v1`): confirmed names stay, pending and canceled names are cleared, `none` is untouched. Deprecated `@Model` fields (`companionStatusRawValue`, `companionMembers`, `companionInvitationShared`, CloudKit locators, `companionIsOwner`) stay in the schema, unread. Old CloudKit records are not deleted.
- `ShowCreationOrigin.companionImport` keeps meaning "does not consume free capacity", now also for shows added from an old invite link.
- Old `/join/<token>` and `beforeshow://join/<token>` links still open the app. A decodable token adds the inviter's name to a matching local show, or opens add-show prefilled (inviter as companion, origin `companionImport`), after onboarding if needed. Undecodable tokens and raw iCloud share URLs just open the app.

## Consequences

- No iCloud or network is needed to record companions; the CloudKit container and entitlements stay until separately evaluated.
- Companions are not synced between people; each person records their own.
