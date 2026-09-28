# BeforeShow

Monorepo for BeforeShow, a concert-prep companion focused on helping users enter the show mood during the 14 days before a live event.

## Structure

- `apps/web`: official Next.js website, app preview, legal pages, invitation landing page, and event tracking client.
- `packages/core`: shared product constants, copy, and domain logic.
- `packages/ui`: shared UI tokens and reusable web/mobile-friendly primitives.
- `packages/config`: shared tooling config placeholder.

## Run The Website

```bash
npm install
npm run dev
```

The website lives in `apps/web`. The interactive preview stores anonymous product events in browser localStorage.

For local build verification:

```bash
npm run build:web
```

## Validation

Fake-door evidence lives in `.builder/evidence/experiments/` in this repo. The current test checks whether users with a real upcoming show will leave an email and name that show.
