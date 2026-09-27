# CloudBase Functions

## Feedback

BeforeShow feedback stays inside the app:

`iOS -> submitFeedback -> userFeedback`

The write endpoint accepts only the user-entered message, App version, and iOS version. It verifies the app signature and applies two fixed-window limits before writing:

- 5 submissions per app instance per hour
- 120 submissions globally per hour

The app-instance identifier is hashed with the current hourly window before it is written to the separate `feedbackRateLimits` collection.

### Prepare and deploy

```bash
npm run prepare:deploy
```

Deploy the feedback functions after staging:

```bash
tcb fn deploy submitFeedback --yes
tcb fn deploy listFeedback --yes
```

Configure `FEEDBACK_ADMIN_TOKEN` on the deployed `listFeedback` function before using it. Keep this token out of the repository and out of the iOS app.

### View recent feedback

Set the deployed admin endpoint and the same server-side token on the operator machine:

```bash
export FEEDBACK_ADMIN_URL="https://<cloudbase-host>/listFeedback"
export FEEDBACK_ADMIN_TOKEN="<operator-secret>"
npm run feedback:list -- --limit=50
```

The viewer defaults to 50 records and caps requests at 100. To get machine-readable output:

```bash
npm run feedback:list -- --limit=100 --json
```

`listFeedback` is read-only and returns only:

- feedback ID
- message
- App version
- iOS version
- submission time

It does not expose database IDs, rate-limit identifiers, app-instance IDs, or app signatures.
