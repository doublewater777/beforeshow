# BeforeShow Design System

> Status: V2 direction contract. This document defines the intended product language for the iOS app and the onboarding prototype. It supersedes the visual and onboarding direction in `docs/INDIE_APP_DESIGN_SYSTEM.md` and `docs/agents/ux-plans/11-onboarding-splash.md`; those files remain implementation history. Existing production screens can migrate incrementally.

## 1. Atmosphere & Identity

BeforeShow should feel like the quiet minutes after the venue goes dark and before the first light lands on stage: personal, expectant, and cinematic without becoming loud. The product is not a ticket wallet or an event-management dashboard. It is a private place where one upcoming live show gradually becomes emotionally real.

The signature is **Poster Stage**:

- The show poster is the focal object and primary source of identity.
- Stage light is atmosphere, never decoration for its own sake.
- The countdown is the recurring brand symbol.
- Interface chrome recedes so the current show feels like the user's own object.

The product should be recognizable even with the wordmark removed: a portrait poster emerging from darkness, poster-aware light bleeding into the surrounding stage, and a restrained countdown lockup below it.

### Principles

1. **One screen, one star.** Every screen has one dominant content object and one primary action.
2. **Show the result before explaining the features.** A personalized poster and countdown communicate more than a feature tour.
3. **Gradient emits light; it does not paint the interface.** Avoid rainbow text and generic purple-blue SaaS gradients.
4. **The user's show supplies the personality.** Poster colors may tint the stage, while controls remain neutral and stable.
5. **Motion must mean arrival, focus, or state change.** No ambient floating or decorative micro-animation.

### Anti-references

- Generic black screen with centered marketing copy and a white pill button.
- Three equally weighted feature cards asking the user to make a tool choice.
- Rainbow feature icon colors.
- Glass cards everywhere.
- A long onboarding form before the first personalized result.
- Replaying a multi-second brand splash on every launch.

## 2. Color

The app is dark-only in V2. These tokens replace pure black plus unrestricted feature colors.

### Palette

| Role | Swift token | Prototype token | Value | Usage |
|---|---|---|---|---|
| Stage void | `BSColor.stageVoid` | `--stage-void` | `#050508` | Root background |
| Stage ink | `BSColor.stageInk` | `--stage-ink` | `#0B0B11` | Background tonal lift |
| Smoke | `BSColor.smoke` | `--smoke` | `#15151D` | Sheets and secondary surfaces |
| Smoke lifted | `BSColor.smokeLifted` | `--smoke-lifted` | `#20202A` | Pressed/selected surface |
| Chalk | `BSColor.chalk` | `--chalk` | `#F5F1E9` | Primary text and primary controls |
| Haze | `BSColor.haze` | `--haze` | `#AAA5AF` | Supporting text |
| Ash | `BSColor.ash` | `--ash` | `#85808C` | Tertiary text and disabled states |
| Hairline | `BSColor.hairline` | `--hairline` | `rgba(245,241,233,.12)` | Required separators only |
| Hairline strong | `BSColor.hairlineStrong` | `--hairline-strong` | `rgba(245,241,233,.22)` | Focused rims and selected surfaces |
| Electric light | `BSColor.electricLight` | `--electric` | `#84BFFF` | Cool stage light and focus ring |
| Electric soft | derived | `--electric-soft` | `rgba(132,191,255,.22)` | Decorative cool light only |
| Tungsten light | `BSColor.tungstenLight` | `--tungsten` | `#FFB36B` | Warm stage light and emphasis |
| Tungsten soft | derived | `--tungsten-soft` | `rgba(255,179,107,.22)` | Decorative warm light only |
| Success | `BSColor.success` | `--success` | `#62D69A` | Confirmed/saved state |
| Warning | `BSColor.warning` | `--warning` | `#F1B85B` | Caution |
| Error | `BSColor.error` | `--error` | `#FF7770` | Destructive and inline errors |

### Rules

- Electric and tungsten may blend only inside light, poster glow, countdown accents, or focus indication.
- Interactive controls use chalk, smoke, and poster-derived light. Tool categories do not each receive a separate color.
- Poster-derived ambient color is capped at low opacity and never changes text or control contrast.
- Body text must meet WCAG AA contrast. Tertiary copy is not used for essential instructions.
- New colors must serve a semantic role and be added here before implementation.

## 3. Typography

Typography should feel editorial and deliberate while remaining native and legible in Chinese.

### Font stack

- Chinese and UI body: `-apple-system`, `SF Pro Text`, `PingFang SC`, sans-serif.
- Display Chinese: native serif treatment (`Songti SC`/`STSong` when available) with system fallback, limited to short 22pt+ atmospheric headlines. It is never used for form labels or body copy.
- English wordmark: a dedicated wordmark asset when available. Until then, letter-spaced system text is secondary, never the hero.
- Countdown numbers: system rounded or default design with tabular figures.

### Scale

| Level | iOS size | Weight | Line height | Tracking | Usage |
|---|---:|---:|---:|---:|---|
| Countdown | 80 | 300 | 0.95 | -1.0 | Days/state number |
| Display | 40 | 400 | 1.12 | -0.6 | Onboarding promise |
| Hero title | 32 | 600 | 1.18 | -0.4 | Current show name |
| H1 | 28 | 700 | 1.2 | -0.3 | Sheet/page title |
| H2 | 22 | 600 | 1.3 | -0.1 | Section heading |
| Body large | 18 | 400 | 1.65 | 0 | Onboarding support copy |
| Body | 16 | 400 | 1.65 | Default content |
| Body small | 14 | 400 | 1.55 | Secondary information |
| Caption | 12 | 500 | 1.4 | Metadata and privacy note |
| Eyebrow | 11 | 600 | 1.3 | Short brand/context label |

### Rules

- No essential mobile body text below 14pt.
- Use tabular figures for countdown and time.
- Avoid excessive tracking in Chinese. Wide tracking is reserved for a short English wordmark.
- Chinese copy uses semantic line breaks; do not leave a particle or short final phrase isolated.
- Headlines use sentence case and plain language.

## 4. Spacing & Layout

### Base unit

All spacing derives from 4pt.

| Token | Value | Usage |
|---|---:|---|
| `space-1` | 4 | Tight inline spacing |
| `space-2` | 8 | Icon-to-label, metadata |
| `space-3` | 12 | Compact control groups |
| `space-4` | 16 | Standard content gap |
| `space-5` | 20 | Mobile outer margin |
| `space-6` | 24 | Section inner spacing |
| `space-8` | 32 | Major content separation |
| `space-10` | 40 | Hero rhythm |
| `space-12` | 48 | Content-to-primary-action gap |
| `space-16` | 64 | Major stage separation |

### Mobile composition

- Reference viewport: iPhone 17 class, portrait.
- Horizontal safe content margin: 20pt; expressive entry stage may use 24pt.
- Minimum touch target: 44×44pt.
- Primary action remains reachable without scrolling on the onboarding entry and confirmation screens.
- The standard cover aspect ratio is 3:4. Source artwork keeps its natural crop inside a 3:4 container.
- Home and onboarding use asymmetric vertical composition: atmosphere above, action anchored toward the lower third.
- Radius tokens are 10pt for compact media, 16pt for controls, and 24pt for stage surfaces. Pills are reserved for status, not default containers.
- Native implementation supports Dynamic Type. At accessibility sizes, metadata stacks, decorative copy yields, and the primary action remains reachable.

### Responsive prototype

- The HTML prototype centers an iPhone frame up to 393×852; below that width, the screen reflows instead of shrinking its typography.
- At narrow browser widths the supporting notes move below the device; the phone itself stays readable without clipping.
- No production screen uses `100vh`; use dynamic viewport units or native safe areas.

## 5. Components

### `PosterStageBackground`

- **Structure:** stage void, poster-derived ambient light, directional tungsten/electric light, subtle grain, edge vignette.
- **Variants:** neutral onboarding, poster-aware current show, reduced-motion static.
- **States:** default, loading poster colors, poster colors resolved.
- **Accessibility:** decorative layers are hidden from assistive technologies; contrast remains independent of poster color.
- **Motion:** opacity and transform only; 500ms emphasis reveal.

### `ShowPosterHero`

- **Structure:** real poster image, top/bottom scrim, show metadata, optional countdown badge.
- **Variants:** unresolved placeholder, recognized preview, current show, failed cover.
- **States:** loading uses a poster-shaped luminous skeleton; error uses the existing stage artwork without error copy over the image.
- **Accessibility:** descriptive label contains show name and date; decorative crop is hidden.
- **Motion:** recognized artwork resolves from blur/scale to sharp/settled in 500–600ms.

### `CountdownLockup`

- **Structure:** tabular number or state phrase, unit, one supporting line.
- **Variants:** before, today, ended, postponed, canceled.
- **States:** static after arrival; never loops.
- **Accessibility:** read as one phrase, for example “距离开场还有 1 天”.
- **Motion:** one arrival transition when a show becomes current.

### `PrimaryStageAction`

- **Structure:** action-oriented label inside a chalk control on a dark stage.
- **Variants:** standard, loading, disabled, destructive.
- **States:** default, pressed, keyboard focus, loading, disabled.
- **Accessibility:** minimum 44pt; label states the next action, never “开始进入” or “继续” when a specific verb is available.
- **Motion:** 120ms press scale to 0.98; focus ring uses electric light.

### `QuietAction`

- **Structure:** plain text action, no container unless focus is visible.
- **Variants:** secondary, tertiary, destructive.
- **States:** default, pressed, focus, disabled.
- **Accessibility:** minimum 44pt hit area even when visually quiet.

### `RecognitionPreview`

- **Structure:** poster thumbnail plus only the recognized required fields: name, date, time.
- **Variants:** parsing, confirmed, field needs attention.
- **States:** loading, editable, inline error, success.
- **Accessibility:** every editable field has a visible label and error relationship.
- **Motion:** fields enter together after the poster resolves; no staggered card parade.

### `ShowTip`

- **Structure:** one lightweight, time-aware suggestion tied to the current show lifecycle.
- **Variants:** candidate songs, outbound plan, preparation, fragment.
- **States:** default, pressed, loading, completed.
- **Accessibility:** explains why the suggestion is relevant now without presenting it as a required task.
- **Motion:** appears after the countdown settles; no looping decoration.

### `StageSheet`

- **Structure:** native sheet scaffold with clear title, back/dismiss route, body, sticky action area.
- **Variants:** add-show source, confirmation, tool result.
- **States:** default, scroll, keyboard, error.
- **Accessibility:** logical focus order and dismiss action.

## 6. Motion & Interaction

### Timing

| Type | Duration | Easing | Usage |
|---|---:|---|---|
| Press | 120ms | ease-out | Button response |
| Standard | 240ms | ease-in-out | Sheet and state changes |
| Stage reveal | 520ms | cubic-bezier(.16,1,.3,1) | Poster/light resolve |
| Activation | 640ms | cubic-bezier(.16,1,.3,1) | Recognized poster becomes current show |

### Rules

- Animate only `transform`, `opacity`, and carefully bounded `filter`.
- The hero motion has a narrative: unfocused stage → recognized poster → owned current show.
- The interface becomes tappable immediately; animation never blocks the primary action.
- Respect Reduce Motion: remove blur/scale travel and use a short crossfade.
- Returning users do not replay the first-launch brand sequence.
- System launch screen is a fast neutral bridge, not a marketing surface.

## 7. Depth & Surface

### Strategy: mixed, with one light source

Depth comes from tonal shift, poster occlusion, and tinted stage light. Borders and shadows are supporting tools, not the default card recipe.

| Level | Treatment | Usage |
|---|---|---|
| Stage | `stage-void` plus vignette | Root |
| Surface | `smoke` tonal lift | Sheets and grouped content |
| Lifted | `smoke-lifted` plus hairline rim | Selected/pressed/elevated controls |
| Poster | directional tinted shadow plus subtle rim | Hero focal object |

Rules:

- Lighting direction is consistent: cool light from upper left, warm light from upper right or poster edge.
- A card earns a container only when grouping or elevation communicates meaning.
- Blur is never used alone to claim “glass”; a translucent surface needs tint, rim, and controlled highlight.
- Grain is subtle and decorative; it must not reduce text clarity.

## Onboarding Experience Contract

### Goal

The onboarding does not ask a first-time user to prepare material before they understand the value. It demonstrates the product with a curated showcase example, then invites the user to add their own show.

**Activation moment:** the showcase example resolves into the redesigned home, making the cover, countdown, and one relevant Tip understandable before any commitment.

### Flow

1. **Immediate entry:** system launch transitions directly into a short promise and a low-commitment action, “看一场如何被准备”. No separate two-to-three-second splash.
2. **Guided demonstration:** the product automatically demonstrates local recognition and minimal confirmation with curated showcase data. The user watches; no screenshot, link, or personal data is required.
3. **Home reveal:** the showcase cover becomes the current show and the redesigned home arrives with a countdown, one lifecycle-appropriate Tip, and a quiet preview of what can be prepared.
4. **Invitation after value:** only after the reveal does the dominant action become “添加我的现场”. Screenshot, link, and manual entry appear in the following source sheet.
5. **Contextual permission:** ask for notifications only after the user's real show exists and the user can understand the benefit.

### Entry copy

- Brand: `开场前`
- Title: `你的那一场，会这样慢慢靠近`
- Body: `先看开场前如何认出一场现场，再把它变成属于你的倒计时。`
- Primary: `看一场如何被准备`
- Assurance: `使用演示数据，不需要准备任何资料`

### Confirmation copy

- Demonstration title: `正在认出这场示例现场`
- Recognized fields: showcase name, date/time, place, and a 3:4 cover.
- Progress labels: `读取必要信息` → `只保留现场信息` → `准备首页`.
- Privacy boundary: screenshot recognition extracts only show name, date, start time, place, artists, and cover. It never recognizes or stores order numbers, QR/barcodes, identity numbers, phone numbers, buyer names, or payment details. Partial or failed recognition falls back to editable fields or manual entry.

### Activation copy

- Countdown accessibility phrase: the real day difference between today and the showcase start date.
- Tip: `先从候选曲目找到熟悉感`
- Primary: `添加我的现场`

### Must not include

- Multi-page feature carousel.
- Equal-weight source cards.
- Pro promotion or rating request.
- Permission prompts before the first show is created.
- Full metadata form before activation.
- A repeating launch animation for returning users.
- Ticket barcodes, order numbers, identity data, buyer information, or payment details in onboarding examples.

### Validation

- The production native first screen is tappable within one second on a cold first launch. The HTML exploration may first load its pinned prototype runtime.
- A user reaches the sample home without leaving the app or preparing any material.
- The guided demonstration finishes in roughly 6–8 seconds and can be paused, replayed, or skipped to the reveal.
- The redesigned home keeps its countdown and “添加我的现场” action legible on an iPhone 17 class viewport.
- VoiceOver announces a coherent flow and each action is specific.
- Reduce Motion keeps the same information and task order.
- Product analytics should compare: first-show creation rate, time to personalized countdown, source-selection abandonment, confirmation abandonment, and Tip engagement.

## Home Experience Contract

The home is not a dashboard of equal cards. It is a living stage for one current show.

1. **Current show hero:** an atmospheric showcase or user-provided 3:4 cover occupies the upper half. Name, date, and place sit inside its scrim.
2. **Countdown bridge:** the number visually crosses from the cover into the content area, tying emotion to time.
3. **One timely Tip:** only the most relevant suggestion is promoted. At twelve days, candidate songs are appropriate; at one day, preparation replaces them.
4. **Preparation rail:** songs, route, and fragments are visible as quiet destinations with state, not equal promotional cards.
5. **Primary ownership action:** empty/sample home uses “添加我的现场”; a real current show uses contextual actions and a quiet switcher.
6. **No permanent onboarding chrome:** demonstration progress and replay controls disappear for returning users.

### Home concept B: Poster Atlas

This alternative is more emotional and less dashboard-like than the first redesigned home.

- The complete 3:4 cover stands upright at the center and occupies roughly three quarters of the usable width instead of becoming a background crop.
- A blurred, low-opacity echo of the cover supplies surrounding atmosphere; the readable cover itself remains sharp and uncropped.
- The countdown becomes an oversized typographic beat directly below the cover. It aligns with the cover edge but never overlaps or competes with the artwork.
- Show name, place, and date live on the cover scrim so the artwork and identity are read as one object.
- After the large countdown, home promotes exactly one “今天可以做” action and a quiet time-to-show track.
- Secondary destinations remain text actions. No three-card tool grid and no permanent tab bar are introduced.
- Motion is one cover-settling transition followed by the countdown; the surface remains still afterward.

### Home concept C: Native Poster Continuity

This alternative starts from the currently shipped iOS home rather than replacing its scale system.

- Preserve the iPhone 17 baseline: a roughly 367×489pt 3:4 cover and the existing oversized countdown rhythm.
- Remove the separate top utility row (`当前现场`, add, more). It consumes atmosphere and repeats the cover's role.
- Do not replace that row with another label. Keep only one quiet 44pt overflow action inside the cover's top-right scrim.
- Keep show identity inside the lower cover scrim exactly as the native home does.
- Preserve the current vertical order below the cover: countdown, one Tips card, horizontal tools, and floating tab bar.
- The cover becomes the first visible product surface below the system status area; no replacement marketing header is added.
- Let a blurred, low-opacity echo of the real cover extend beyond its edges. It supplies atmosphere without sacrificing the sharp 3:4 artwork.
- Keep the oversized countdown to the number and unit only. Do not repeat the target date, location, or lifecycle state beside it.
- Leave a deliberate 20pt pause between the cover and countdown so they read as two beats rather than one crowded block.
- Tighten vertical padding around the unchanged large countdown so the complete Tips card clears the floating tab bar on first appearance.

## Prototype Scope

The HTML prototype demonstrates the product before asking for user data:

1. Low-commitment entry stage.
2. Automatic showcase local-recognition demonstration.
3. Automatic showcase minimal-confirmation demonstration.
4. Redesigned sample home with a date-derived countdown.
5. Candidate-song Tip preview and final “添加我的现场” invitation.

The source sheet appears only after the user chooses to add their own show. Link parsing and manual entry remain visible as alternatives but are intentionally not expanded in this concept prototype.

### Prototype showcase data

- Name: `【南京】爱在南京嘉年华 2026 周杰伦世界巡回演唱会`
- Date: `2026.09.24–09.26`
- Place: `南京市 · 南京奥体中心体育场`
- Cover: user-selected 1020×1360 artwork, rendered in its native 3:4 ratio.
- Countdown: derived from the first date, `2026.09.24`; the July 10, 2026 prototype capture reads `76 天`.
