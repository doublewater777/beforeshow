# CloudBase Functions

## Timetable recognition

`iOS -> recognizeTimetable -> Bailian qwen3.7-flash -> TimetableExchangeDocument JSON`

The endpoint accepts app auth plus one to three timetable images (JPEG/PNG/WebP as base64). It calls Bailian / DashScope OpenAI-compatible chat completions with the server-side recognition prompt, does not store images, and returns only a version-1 exchange document the iOS `TimetableImportParser` can decode.

Request body:

```json
{
  "appInstanceId": "...",
  "appSignature": "beforeshow-app-signature-v1",
  "imageBase64": "<jpeg-base64>",
  "mimeType": "image/jpeg"
}
```

Or `images: [{ "mimeType": "image/jpeg", "base64": "..." }, ...]`.

Success response: `{ "ok": true, "document": { ... }, "model": "qwen3.7-flash", "usage": { ... } }`.

Rate limits (hashed instance id, hourly window, collection `timetableRecognitionRateLimits`):

- 10 recognitions per app instance per hour
- 200 recognitions globally per hour

Configure on the deployed function (keep out of the repo and out of the iOS app):

- `DASHSCOPE_API_KEY` — required
- `DASHSCOPE_BASE_URL` — optional; defaults to `https://dashscope.aliyuncs.com/compatible-mode/v1` (MaaS workspace URL also works)
- `TIMETABLE_MODEL` — optional; defaults to `qwen3.7-flash`

```bash
set -a && source .env && set +a
npm run prepare:deploy:recognizeTimetable
tcb fn deploy recognizeTimetable
# First deploy only: bind HTTP path as 云托管 (same host as parseShowLink / submitFeedback).
# Do not use --httpFn — that creates a 云函数 trigger and returns FUNCTIONS_PARAM_INVALID.
tcb service create -p recognizeTimetable -f recognizeTimetable
```

Production URL:

`https://beforeshow-d2g0gv0zz4cc249dc-1312569550.ap-shanghai.app.tcloudbase.com/recognizeTimetable`

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
