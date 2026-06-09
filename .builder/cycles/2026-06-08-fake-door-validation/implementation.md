# Implementation

## Built

- `apps/fake-door` Vite app.
- Landing hero with real concert-prep visual.
- Interactive prototypes for countdown, setlist, festival planning, and AI traffic.
- Seven-door validation overview.
- Waitlist form with validation.
- Local event and lead storage.
- JSON and CSV export.
- Optional event endpoint hook through `VITE_BEFORESHOW_EVENT_ENDPOINT`.

## Not Built

- Backend aggregation.
- Server-side lead persistence.
- Email delivery.
- Real AI output.
- Real route planning.
- Real video player.

## Handoff Notes

Run with:

```bash
npm run dev
```

Build with:

```bash
npm run build:fake-door
```

When an event endpoint exists, set:

```bash
VITE_BEFORESHOW_EVENT_ENDPOINT=https://example.com/events
```
