# Live Activity ephemeral remote dispatch via Tencent Cloud

## Status

Accepted — 2026-10-21. Supplements ADR 0007.

## Context

ADR 0007 established that BeforeShow uses a lightweight Tencent Cloud backend that avoids long-term user data storage and primarily handles user-triggered requests.

When the iOS app is suspended or terminated in background during a festival or show, local Swift code cannot run on schedule to push `ActivityKit` updates or sound alerts at set transitions and 15-minute "want-to-see" milestones. Apple `ActivityKit` does not support offline multi-hour timeline scheduling on device; background updates require APNs remote push notifications.

## Decision

- **Ephemeral storage exception**: CloudBase is granted a strictly bounded, temporary exception to ADR 0007 to store active `LiveActivityBoundedTransitionPlan` payloads during a show's lifecycle.
- **Zero long-term user data**: The stored plan contains only presentation fields (artist name, stage name, start/end timestamps, step state) and device push tokens. It contains no photos, ticket files, companion records, user profiles, or Apple IDs.
- **Strict TTL auto-cleanup**: Plans are ephemeral. Records are deleted upon explicit revocation or automatically purged within 24 hours after the festival day's lifecycle end (`deadline + 24h`) via TTL indexing.
- **Installation ownership & auth**: Fixed `appSignature` serves as basic gateway check. Mutual ownership is enforced by a client-generated random `planSecret`; the server stores only `SHA-256(planSecret)` and verifies it on plan updates and revocations, preventing cross-installation tampering.
- **1-minute poll dispatch**: CloudBase runs a lightweight cron dispatcher checking due steps, sending HTTP/2 requests to APNs with `apns-push-type: liveactivity`, and recording step consumption idempotently.
- **Never miss safety net**: If network fails or plan sync does not complete prior to the 15-minute trigger point, the iOS `LiveActivityReminderLedger` keeps local notifications active as fallback.

## Consequences

- CloudBase database hosts the `liveActivityPlans` collection with TTL indexes.
- APNs authentication key (`.p8`) and team configuration live strictly in server environment variables (`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`), never in the client bundle, repo, or logs.
- Privacy disclosures clearly specify that temporary push routing metadata is automatically deleted after the event concludes.
