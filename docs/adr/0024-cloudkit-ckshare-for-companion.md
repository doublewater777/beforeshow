# Use CloudKit + CKShare for companion invitations

## Status

Accepted — 2026-08-02

## Context

Companion (“同行”) previously stored invitation state only on-device and shared a plain-text message via the system share sheet. There was no bidirectional confirm or long-term sync without a self-hosted backend.

## Decision

Use Apple CloudKit private database records plus `CKShare` for companion sessions:

- Local `Show` (SwiftData) remains the UI cache for companion status and name.
- A custom private zone `CompanionSessions` holds shareable `CompanionSession` root records (CloudKit forbids sharing the default zone).
- Persist full record locators (`recordName` + `zoneName` + `ownerName`) for both the session and share, not bare record names.
- `CKShare` + `UICloudSharingController` deliver the invitation link (Messages, Mail, AirDrop, copy link, etc.).
- Scene-based acceptance uses `UIWindowSceneDelegate` + cold-launch `connectionOptions.cloudKitShareMetadata`.
- Accepting the share updates status to accepted only after a durable status write; write failures surface as retryable sync errors.
- Owner cancel revokes/deletes the `CKShare` in addition to writing `status=canceled`.
- Personal notes, tickets, and reminders stay out of the shared record.

## Consequences

- Requires an iCloud account on both devices; no custom login server.
- CloudKit container `iCloud.com.doublewaterapps.beforeshow` and schema must exist in the developer team.
- Network is required to create, accept, cancel, and sync; last known local status still displays offline, and offline cancel does not pretend remote revocation succeeded.
- Not a substitute for a China-domestic custom backend for other features (link parse still uses Tencent CloudBase).
