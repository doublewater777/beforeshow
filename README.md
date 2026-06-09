# BeforeShow

Monorepo for BeforeShow, a concert-prep companion focused on helping users enter the show mood during the 14 days before a live event.

## Structure

- `apps/fake-door`: demand-validation landing page, app preview, waitlist surface, and event tracking client.
- `packages/core`: shared product constants, copy, and domain logic.
- `packages/ui`: shared UI tokens and reusable web/mobile-friendly primitives.
- `packages/config`: shared tooling config placeholder.

## Run The Fake Door

```bash
npm install
npm run dev
```

The fake-door app lives in `apps/fake-door`. It stores events and waitlist submissions in browser localStorage, then lets you export JSON or CSV from the experiment panel.

For local build verification:

```bash
npm run build:fake-door
```

For a hosted test with server-side event capture, set `VITE_BEFORESHOW_EVENT_ENDPOINT` before building or running the app.

## Validation

Fake-door evidence lives in `.builder/evidence/experiments/` in this repo. The current test checks whether users with a real upcoming show will leave an email and name that show.
