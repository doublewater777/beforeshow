# PostHog Self-driving Setup Report

_Generated 2026-08-18_

## Summary

PostHog Self-driving is now configured for BeforeShow (iOS). Error tracking, session replay, health checks, and support sources are wired to the inbox; a seven-scout troop — including three custom scouts tailored to this app's core funnels — is active and will start filing findings within ~30 minutes. View your inbox at: https://us.posthog.com/project/461647/inbox

---

## AI Data Processing

**Approved.** Organization-level AI data processing consent was confirmed before this run.

---

## GitHub

**Connected during this run.** Integration ID 229398, account: doublewater777. Self-driving can now research findings in the repo and open fix PRs.

---

## Products Enabled

| Product | Status | Notes |
|---|---|---|
| Session Replay | Enabled but inert | Mobile iOS app — server flip is on, but iOS SDK must be configured (`config.sessionReplayConfig.enabled = true` in `BeforeShowApp.swift`) before recordings start |
| Error Tracking | Enabled but inert | SDK already has `config.errorTrackingConfig.autoCapture = true`; issues will reach the inbox once the app ships to real users |
| Support (Conversations) | Enabled but inert | Tickets reach the inbox only after an inbound channel (email / inbox / Slack) is connected in PostHog |

> **Note:** `products-enable` was not available via the MCP on this deploy. Products were not programmatically toggled — enable them from **PostHog Settings** if they are not already on: Settings → Session replay ("Record user sessions"), Settings → Error tracking ("Enable exception autocapture"), and Support from the product sidebar.

---

## Signal Sources

| Source product | Source type | Action | Config ID |
|---|---|---|---|
| `signals_scout` | `cross_source_issue` | ON BY DEFAULT — no row needed | — |
| `health_checks` | `health_issue` | Enabled | `01a013f6-a9d4-7685-9637-b518f8f31163` |
| `error_tracking` | `issue_created` | Enabled | `01a013f6-ad12-7078-8555-ab8f7864c6fd` |
| `error_tracking` | `issue_reopened` | Enabled | `01a013f6-b1c0-729b-90dc-614829643483` |
| `error_tracking` | `issue_spiking` | Enabled | `01a013f6-b93b-740b-83cb-e9add574b38e` |
| `session_replay` | `session_analysis_cluster` | Enabled (server default: 10% sample rate) | `01a013f6-bae6-76b3-b9e4-e989010be3c2` |
| `conversations` | `ticket` | Enabled | `01a013f6-bc6d-7d7a-8497-3bd9b5730649` |
| `replay_vision` | scanner findings | Self-authorizing via `emits_signals` flag on scanners — no source row needed | — |
| `llm_analytics` | — | Skipped — not in use (no AI/LLM events) | — |
| `logs` | — | Skipped — not a v1 responder | — |

---

## Connected Tools

None selected. The user chose "None of these" in the issue-tracker prompt.

---

## Scout Troop

**7 enabled scouts** (ceiling: 10). Run budget: **100 runs/day** (early access default); **0 used today**.

> _Banner from PostHog:_ "Scouts are in early access. Each project gets up to 100 scout runs a day. Contact team-self-driving@posthog.com if you need more."

### Enabled

| Scout | Type | Reason |
|---|---|---|
| `signals-scout-general` | Canonical | Always on — cross-product correlations and surfaces no specialist covers |
| `signals-scout-product-analytics` | Canonical | Lifecycle events and custom events clearly instrumented in this app |
| `signals-scout-health-checks` | Canonical | New setup — will surface instrumentation gaps and PostHog health issues |
| `signals-scout-observability-gaps` | Canonical | New project — will flag events with no insight or dashboard coverage |
| `signals-scout-pro-conversion` | **Custom** | Pro paywall conversion funnel — not covered by any built-in scout |
| `signals-scout-show-add-funnel` | **Custom** | Show-add completion and free-tier friction — core funnel unique to this app |
| `signals-scout-dispersal-ceremony` | **Custom** | Post-show memory flow completion — unique to BeforeShow |

### Disabled (23 total)

| Scout | Reason |
|---|---|
| `signals-scout-error-tracking` | Covered by the native error-tracking source (issue_created / reopened / spiking) |
| `signals-scout-session-replay` | Covered by the native session-replay source (session_analysis_cluster) |
| `signals-scout-feature-flags` | No feature flags detected in this project |
| `signals-scout-surveys` | No surveys in use (0 found) |
| `signals-scout-revenue-analytics` | StoreKit IAP detected, but no Stripe/PostHog revenue integration |
| `signals-scout-ai-observability` | No `$ai_*` events or LLM usage |
| `signals-scout-web-analytics` | iOS mobile app — no web traffic |
| `signals-scout-experiments` | No A/B experiments detected |
| `signals-scout-logs` | PostHog logs product not in use |
| `signals-scout-csp-violations` | No CSP reporting configured |
| `signals-scout-customer-analytics` | No group/account analytics (B2C app) |
| `signals-scout-data-pipelines` | No CDP destinations or batch exports |
| All others | Not applicable to this project's current surfaces — enable from the inbox if needed |

> To re-enable any of these, go to **PostHog → Self-driving** and toggle the scout on.
> To switch a noisy scout to dry-run without disabling it, set `emit: false` on its config.

---

## Custom Scouts

### `signals-scout-pro-conversion`

**Watches:** Pro paywall conversion — `pro_purchase_completed / pro_paywall_viewed` ratio (conversion rate) and `pro_purchase_failed / (completed + failed)` failure rate.

**Discriminator:** Conversion rate or failure rate shifts sustained over 2+ consecutive days (single-day dips are noise). Requires `pro_paywall_viewed ≥ 5/day` to conclude.

**Why no built-in covers it:** `signals-scout-product-analytics` watches *saved funnel insights* — the project has none yet. `signals-scout-revenue-analytics` watches Stripe/PostHog revenue, not StoreKit IAP events. This is a genuinely uncovered funnel.

**Explore patterns:** 7-day conversion rate trend, failed purchase rate by day, plan distribution shift.

---

### `signals-scout-show-add-funnel`

**Watches:** Show-add completion — `show_added / (show_link_parsed + screenshot_recognized)` — and free-tier friction — `pro_limit_reached` as a share of parse attempts.

**Discriminator:** Completion rate drops >25% below 7-day baseline for 2+ days, or limit hit rate exceeds 30% for 2+ days. Requires ≥5 parse attempts/day.

**Why no built-in covers it:** Same as above — the product-analytics scout needs saved funnels. This is the core user journey (adding a show) and is unique to this app.

**Explore patterns:** Daily completion/limit rate table, entry-method breakdown (link parsing vs screenshot).

---

### `signals-scout-dispersal-ceremony`

**Watches:** Post-show dispersal ceremony — `dispersal_ceremony_completed / (completed + skipped)` — and skip trigger split (`trigger=close` vs `trigger=skip`).

**Discriminator:** Completion rate drops >20% below baseline for 2+ days. Requires ≥10 ceremony triggers/day to conclude.

**Why no built-in covers it:** This is a BeforeShow-specific post-show engagement flow. No built-in scout watches it.

**Explore patterns:** 7-day completion rate table, skip trigger breakdown by day.

---

### Surfaces considered and ruled out

| Surface | Filter |
|---|---|
| `memory_fragment_created` | Single-event watch; `signals-scout-observability-gaps` and `signals-scout-general` cover this adequately |
| Feature flag evaluation | No flags detected in the project |
| Surveys | 0 surveys in use |

---

## Replay Vision Scanners

Both skeleton scanners were **skipped**. BeforeShow is a pure mobile iOS app with no web surface in this PostHog project. The `fake-door` landing page uses its own `localStorage` tracking and does not send events to PostHog. The URL-based and `$rageclick`-based scanner skeletons only apply to web sessions, so neither scanner would ever match a recording.

Replay Vision quota is only spent when a scanner matches a recording — skipping both scanners means zero quota impact.

**Follow-up:** After enabling mobile session replay in the iOS SDK (see Follow-ups below), revisit this step and set up mobile Replay Vision scanners for the Pro paywall flow and the show-add flow.

---

## Follow-ups

- [ ] **Enable mobile session replay in iOS SDK** — in `apps/ios/BeforeShow/BeforeShowApp.swift`, add `config.sessionReplayConfig.enabled = true` (or equivalent iOS SDK config) to the PostHog init block before calling `PostHogSDK.shared.setup(config)`.
- [ ] **Enable products in PostHog Settings** — the `products-enable` API was not available on this deploy. Go to PostHog Settings and manually enable: Session replay → "Record user sessions", Error tracking → "Enable exception autocapture", and Support from the product sidebar.
- [ ] **Connect a support inbound channel** — Conversations is enabled as a signal source, but tickets only arrive once you connect an email, inbox, or Slack channel in PostHog. Go to the [Support settings](https://us.posthog.com/project/461647/settings/environment-integrations) to add a channel.
- [ ] **Set up Replay Vision scanners for mobile** — once mobile session replay is configured and recordings are flowing, create two mobile-appropriate scanners for the Pro paywall flow and the show-add flow. The web URL + rageclick skeletons do not apply to mobile sessions.
- [ ] **Build funnel insights in PostHog** — `signals-scout-product-analytics` watches *saved* funnel/retention/lifecycle insights. Create at least one funnel in PostHog (e.g., show_link_parsed → show_added) so this scout has a flow to monitor.
- [ ] **Consider issue-tracker integration** — no issue tracker was connected. If you start using GitHub Issues, Linear, or another tracker, re-run setup or connect it from [PostHog pipeline settings](https://us.posthog.com/project/461647/pipeline/new/source).

---

## What Happens Next

The scout coordinator picks up the new configs within ~30 minutes and fires the first runs. Each run draws from the project's daily budget (100 runs/day during early access — contact team-self-driving@posthog.com if you need more). Findings cluster into reports in the Self-driving inbox; immediately-actionable ones can auto-start coding tasks.

Scout runs close out empty when there's nothing to report — that's a correct outcome, not a problem. When a scout does find something, it files a report in the inbox with concrete evidence and a suggested fix.

**Your inbox:** https://us.posthog.com/project/461647/inbox
