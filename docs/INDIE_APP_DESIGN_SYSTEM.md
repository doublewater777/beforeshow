# Indie App Design System

Status: Draft v1
Owner: BeforeShow
Platform: iOS only

## Purpose

This design system is the product UI foundation for BeforeShow. It should make the app feel quiet, native, and emotionally close to the moment before a live show starts.

The system is not a generic company-wide design system yet. It is a BeforeShow-first system with enough structure to be reused in future DoubleWater indie apps if the patterns prove stable.

## Product Feeling

BeforeShow should feel like:

- A dark room before the stage lights come on.
- A focused iPhone app, not a mobile web page.
- A preparation tool with taste, not a decorative concert poster.
- Calm enough for repeated use before and after shows.
- Emotional in entrances and empty states, efficient in forms and lists.

The splash screen carries the strongest stage atmosphere. The rest of the app should be more restrained.

## Core Principles

1. Dark first.
2. Native iOS interaction first.
3. Black, white, and gray do most of the work.
4. Lighting gradients are accents, not page decoration.
5. Cards are for repeated objects, not every section.
6. Forms must be clear because adding a show is the core action.
7. AI, OCR, and parsing states should be useful, not magical.
8. Pro should be visible but not loud.
9. Build tokens and primitives first, then extract product components only after reuse appears.
10. No feature should require a visual style that breaks the system.

## Design Layers

### Tokens

Tokens define the shared visual language:

- Color
- Typography
- Spacing
- Radius
- Border
- Elevation
- Motion
- Icon sizing

### Primitive Components

Primitive components are reusable across many screens:

- Buttons
- Text fields
- Text areas
- List rows
- Section headers
- Empty states
- Processing states
- Toasts
- Badges
- Tags
- Bottom action bars

### Product Components

Product components are tied to BeforeShow concepts:

- Show card
- Add show option row
- Candidate song row
- Round trip plan row
- Show fragment item
- Pro feature gate
- Media reference row
- Voice clip row

Product components should be extracted only when the same structure appears in multiple places or is central enough to deserve consistency.

## Color

### Strategy

The app is dark-first. The palette should be small, semantic, and stable.

Avoid category colors for every feature. Do not create separate colors for AI, OCR, traffic, music, or platforms unless there is a real product need.

### Color Mood

BeforeShow's color mood is `dark-stage lighting before the show`.

It should feel like a live venue before the lights fully come on: a mostly black room, low ambient blue-black, and a small amount of blurred stage light starting to cut through.

Use this mood most strongly in entrance moments such as splash, launch marketing imagery, and rare brand surfaces. Product screens should keep the same color DNA but reduce the intensity so forms, lists, and repeated use stay calm.

The mood is:

- Dark, not gray.
- Stage-lit, not cyberpunk.
- Blurred and atmospheric, not sharp neon.
- Cold-warm mixed, not one-note blue or purple.
- Emotional at entrances, functional in daily UI.

The dominant ratio should be:

- 80-90% black / blue-black negative space.
- 5-15% cool light: cyan, blue, blue-purple.
- 3-8% warm light: amber, orange, soft pink.
- White text only at controlled opacity unless it is primary content.

Avoid:

- Full-page gradients in ordinary product screens.
- Constant glow around cards or buttons.
- Saturated neon outlines.
- Purple-blue dominance without warm counterweight.
- Beige, brown, or poster-like concert palettes.

### Core Semantic Colors

| Token | Purpose | Suggested Value |
| --- | --- | --- |
| `backgroundPrimary` | Main app background | `#000000` |
| `backgroundSecondary` | Slightly lifted page background | `#080808` |
| `surfacePrimary` | Rows, inputs, repeated objects | `#1C1C1E` |
| `surfaceSecondary` | Lower emphasis surfaces | `#141416` |
| `surfaceElevated` | Sheets, popovers, elevated panels | `#222226` |
| `textPrimary` | Main text | White 92-100% |
| `textSecondary` | Supporting text | White 62-70% |
| `textTertiary` | Metadata, helper text | White 38-48% |
| `borderSubtle` | Dividers, low emphasis borders | White 8-12% |
| `borderStrong` | Focused input, selected item | White 18-24% |
| `accentBlue` | Brand accent start | `#7ECFFF` |
| `accentPurple` | Brand accent middle | `#B388FF` |
| `accentOrange` | Brand accent end | `#FFB347` |
| `stageBlueBlack` | Low ambient dark stage background | `#020713` |
| `stageCyanGlow` | Cool light bloom, sparse use | `#37C7FF` |
| `stageVioletGlow` | Purple light bloom, sparse use | `#7A4DFF` |
| `stageAmberGlow` | Warm light bloom, sparse use | `#FF9A3D` |
| `stageSoftPink` | Secondary warm haze, rare use | `#F26BAA` |
| `success` | Completed state | `#32D74B` |
| `warning` | Recoverable issue | `#FFD60A` |
| `danger` | Destructive action | `#FF453A` |
| `pro` | Pro accent | `#FFB85C` |

### Brand Gradient

Use only for:

- Splash title
- Brand moments
- Selected state in rare high-value contexts
- Pro or upgrade hero accents when appropriate

Do not use gradient backgrounds for standard pages, cards, or section decoration.

Gradient:

`#7ECFFF -> #B388FF -> #FFB347`

This gradient should read as stage light passing from cool blue through violet into amber. Keep it on text, selected strokes, or small accents. Do not turn it into a generic background wash.

### Splash Color Treatment

Splash is the highest-intensity expression of the color system.

Current splash direction:

- Black system launch screen and black app base to avoid white flash.
- Full-screen blurred lighting image on top of black.
- Light cluster centered slightly below the visual middle, with large dark space above and below.
- Cool blue/cyan light on the left and center.
- Violet and soft pink as secondary haze.
- Amber/orange light on the right as a warm counterpoint.
- Brand title uses the blue-violet-amber gradient.
- English brand name uses the same gradient at lower opacity.
- Slogan uses white at about 60% opacity.

Splash should not introduce:

- Decorative glowing orbs.
- Sharp lens flare.
- Hard spotlight cones.
- Confetti, crowd imagery, ticket imagery, or instrument imagery.
- A different brand palette from the rest of the app.

## Typography

### Strategy

Use the iOS system font. Do not introduce custom fonts in v1.

Brand feeling should come from spacing, weight, color, and motion rather than a custom typeface.

### Text Roles

| Role | Size | Weight | Usage |
| --- | ---: | --- | --- |
| `display` | 48-56 | Light | Splash title only |
| `pageTitle` | 28-34 | Light / Regular | Major page titles |
| `sectionTitle` | 17-20 | Semibold | Section headers |
| `body` | 15-17 | Regular | Main content |
| `bodyEmphasis` | 15-17 | Medium | Important row text |
| `caption` | 12-13 | Regular | Metadata |
| `button` | 16-17 | Semibold | Primary actions |
| `brandSmall` | 14-16 | Light | `BeforeShow` and small brand labels |

### Rules

- Use light weight for atmosphere, not for dense information.
- Do not use very thin text for body copy on dark backgrounds.
- Letter spacing can be used for brand text and splash text.
- Do not apply negative letter spacing.
- Long Chinese text should prefer readable line height over compactness.

## Spacing

### Scale

Use a compact scale:

- `4`
- `8`
- `12`
- `16`
- `20`
- `24`
- `28`
- `32`
- `40`
- `48`

### Layout Rules

- Screen horizontal padding: `20-24`.
- Dense list horizontal padding: `16-20`.
- Bottom fixed action padding should respect safe area.
- Atmosphere screens may use larger vertical spacing.
- Utility screens should reduce empty space and improve scanning.

## Radius

### Strategy

Use low to medium radius. Buttons may be rounder than content surfaces.

| Token | Value | Usage |
| --- | ---: | --- |
| `radiusSmall` | 8 | Small rows, compact controls |
| `radiusMedium` | 10-12 | Cards, inputs, list rows |
| `radiusLarge` | 16 | Sheets, prominent modules |
| `radiusPill` | 999 | Primary buttons, badges, chips |

### Rules

- Do not nest cards inside cards.
- Do not make every page section a floating card.
- Use round buttons for approachable actions.
- Keep repeated content objects calm and readable.

## Borders And Elevation

### Strategy

Dark UI needs subtle boundaries, not heavy shadows.

Use:

- Fine borders
- Slight surface changes
- Spacing
- Dividers

Avoid:

- Heavy drop shadows
- Bright outlines everywhere
- Floating card stacks

### Suggested Styles

- Standard divider: white 8%, 1 px.
- Focus border: white 22%, 1 px.
- Selected border: accent gradient or accent blue only in rare cases.
- Elevated sheets: surface color change, not shadow-heavy styling.

## Motion

### Strategy

Motion should clarify state and help the app feel alive. It should not perform for the user.

### Motion Tokens

| Token | Duration | Usage |
| --- | ---: | --- |
| `motionFast` | 120-180 ms | Press, selection, small state changes |
| `motionStandard` | 220-320 ms | Page element entrance, sheet content |
| `motionSlow` | 400-500 ms | Completion, meaningful transitions |
| `splashLong` | 800 ms | Splash background fade |

### Motion Patterns

- Entrance: fade in with slight upward movement.
- Selection: opacity or surface change.
- Completion: short confirmation, then settle.
- Processing: skeleton or structured loading.

Avoid:

- Large flying cards.
- Constant glow or shimmer.
- Complex stage-light animation inside ordinary screens.
- Blocking animation before every action.

## Iconography

### Strategy

Use SF Symbols for v1.

### Sizes

- `16`: metadata and compact row icons.
- `20`: standard row and button icons.
- `24`: primary action icons.
- `28`: empty state or prominent icon.

### Rules

- Do not rely on icon-only controls for important actions unless the icon is standard and obvious.
- Platform logos should be used only where needed, such as Apple Music or Spotify connection.
- Do not create a custom icon set in v1.

## Cards And Sections

### Hard Rules

- Cards are for repeated objects.
- Page sections are not cards by default.
- Do not nest cards.
- Do not put every feature into a gray rounded rectangle.
- Use typography, spacing, dividers, and surface hierarchy for sectioning.

### Approved Card Uses

- Show cards.
- Candidate song rows if presented as repeated objects.
- Show fragment items.
- Pro benefit items.
- Media references.

### Avoid Card Uses

- Whole page sections.
- Form groups when native grouped list works better.
- Marketing-style hero blocks inside the app.

## Buttons

### Button Types

| Type | Usage |
| --- | --- |
| `primary` | Main action: add, save, continue |
| `secondary` | Secondary action: retry, choose another method |
| `ghost` | Lightweight page action: edit, view all |
| `destructive` | Delete or irreversible actions |
| `pro` | Upgrade and unlock actions |

### Rules

- Do not create separate button styles for AI, OCR, traffic, or music.
- Use icon plus text when it improves scanning.
- Primary buttons should be visually obvious and comfortable to tap.
- Destructive buttons should be clear but not constantly visible.
- Pro buttons should be distinct without turning the app gold.

## Forms

### Strategy

Forms are a first-class part of the system. Adding a show must feel reliable, editable, and not like a fallback.

### Field Types

- Single line text field: show name, venue, city, link.
- Multiline text area: notes, fragment text.
- Date picker: show date.
- Time picker: opening time.
- Multi-value chip input: artists.
- Editable list: candidate songs.
- Media picker row: referenced photos and videos.
- Voice clip row: recorded audio snippets.

### Rules

- Manual input must always be a clear path.
- Field labels should be explicit.
- Placeholders should be short and not overly conversational.
- Errors appear near the field.
- Parsing and OCR results should always become editable fields.
- Do not force users to trust extracted data.

## Add Show Pattern

The add show entry must present three clear options in this order:

1. `截图识别`
2. `链接解析`
3. `手动填写`

Link parsing only promises:

- 大麦
- 秀动
- 猫眼
- Live Nation

Do not expose paste recognition as a separate feature in v1.

## Empty States

### Strategy

Empty states should combine mood and action.

### Structure

- Title
- Short body
- Primary action
- Optional secondary action
- Optional small SF Symbol

### Examples

Home empty:

- Title: `先添加一场现场`
- Body: `把要去的音乐现场放进来，慢慢靠近那一场。`
- Action: `添加第一场现场`

Candidate songs empty:

- Title: `还没有候选曲目`
- Body: `可以先生成一版，再按你的判断调整顺序。`
- Action: `生成候选曲目`

Round trip plan empty:

- Title: `还没有往返计划`
- Body: `去程和返程可以分开安排，先定一个也可以。`
- Action: `生成往返计划`

Show fragments empty:

- Title: `还没有现场碎片`
- Body: `可以记录出发前、现场中和散场后的瞬间。`
- Action: `添加碎片`

## Processing States

### Strategy

AI, OCR, and parsing states should be consistent and practical.

### Components

- `ProcessingView`: full screen or large block.
- `ProcessingRow`: inline list processing state.
- `Skeleton`: known result layout loading.
- `ProgressText`: clear short status.
- `RetryState`: recoverable failure.
- `PartialResultState`: incomplete result with editable fields.

### Copy Rules

Use direct copy:

- `正在识别截图`
- `正在解析链接`
- `正在整理候选曲目`
- `正在生成往返计划`

Avoid magical copy:

- `AI 正在施法`
- `正在创造惊喜`
- `马上见证奇迹`

### Failure Rules

- Always provide retry when the operation can be retried.
- Always provide manual edit when data can be corrected.
- Do not block the user behind a failed automation.

## Pro And Monetization

### Strategy

Pro should be low-key but clear.

### Visual Treatment

- Use a small `Pro` badge.
- Use `pro` accent only for upgrade or locked capabilities.
- Avoid large gold surfaces in normal pages.
- Upgrade screens can be richer, but should still feel native.

### Locked Feature Pattern

Show:

- Feature name.
- Short value statement.
- Preview when possible.
- Clear upgrade action.

Avoid:

- Hiding the entire feature.
- Scolding copy.
- Too many locked marks on one screen.

## Navigation

### Strategy

Do not add a multi-tab app shell before the product needs it.

### v1 Navigation

- Home
- Show detail
- Add show
- Settings
- Pro/paywall

### Rules

- Keep home as the product center.
- Use native navigation and sheets.
- Use bottom fixed actions for primary form actions.
- Avoid custom navigation patterns unless they solve a clear problem.

## List Density

### Strategy

Use different density for atmosphere and utility.

### Patterns

- Home current show: more spacious and prominent.
- Home other shows: compact and scannable.
- Candidate songs: compact, ordered list.
- Round trip plans: medium density with time/place/method.
- Show fragments: feed-like, more breathing room.

### Row Types

- `CompactRow`: dense utility information.
- `FeatureRow`: richer repeated object.
- `ActionRow`: tappable feature entry.
- `MediaRow`: referenced media or voice clip.

## Screen Patterns

### Splash

Splash may use the strongest brand atmosphere:

- Black launch screen.
- Full-screen blurred stage-light image.
- Mostly black / blue-black negative space.
- Cold-warm light mix: cyan, blue, violet, amber, soft pink.
- Gradient title using `#7ECFFF -> #B388FF -> #FFB347`.
- Lower-opacity English brand name.
- White slogan around 60% opacity.
- Staggered text animation.
- No visible skip button.

Splash should feel like `灯亮之前`: quiet, dark, and just beginning to glow. It should not feel like a poster, a nightclub flyer, or a generic neon tech app.

### Onboarding

Onboarding should be short and restrained:

- 1-2 steps preferred.
- Maximum 3 steps.
- No full reuse of splash visual.
- No skip button in current first-run flow.
- Clear final action into add show.

### Home

Home should not be empty after onboarding.

If no shows exist after onboarding, route to add first show.

Home should eventually support:

- Current or upcoming show focus.
- Recently ended shows retained for a short period.
- Quick access to details and preparation modules.

### Show Detail

Show detail is the operational center for one show:

- Show metadata.
- Candidate songs.
- Round trip plan.
- Show fragments.
- Editable fields.

Use atmosphere in the header, utility density in modules.

### Settings

Settings should feel native:

- Grouped list structure.
- Account and Pro status.
- Music platform preferences.
- Privacy and storage choices.
- Legal and ICP-related information when needed.

## SwiftUI Implementation Direction

### Suggested File Structure

```text
BeforeShow/
├── DesignSystem/
│   ├── BSColor.swift
│   ├── BSTypography.swift
│   ├── BSSpacing.swift
│   ├── BSRadius.swift
│   ├── BSMotion.swift
│   ├── BSButtonStyle.swift
│   ├── BSListRow.swift
│   ├── BSEmptyState.swift
│   ├── BSProcessingView.swift
│   └── BSBadge.swift
├── Features/
│   ├── AddShow/
│   ├── Home/
│   ├── ShowDetail/
│   ├── Settings/
│   └── Pro/
└── Shared/
```

Use the `BS` prefix for reusable design system components until there is a better module boundary.

### Token Shape

Prefer semantic names:

```swift
enum BSColor {
    static let backgroundPrimary = Color.black
    static let stageBlueBlack = Color(red: 0.01, green: 0.03, blue: 0.07)
    static let surfacePrimary = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let textSecondary = Color.white.opacity(0.66)
    static let accentBlue = Color(red: 0.49, green: 0.81, blue: 1.0)
    static let accentPurple = Color(red: 0.70, green: 0.53, blue: 1.0)
    static let accentOrange = Color(red: 1.0, green: 0.70, blue: 0.28)
}
```

Avoid raw color values inside feature views unless the color is a one-off asset-specific overlay.

### Component Rules

- Feature views should compose design system primitives.
- Do not add a primitive just because one screen needs it once.
- Extract after repeated use or when consistency matters.
- Keep components plain SwiftUI unless a design need requires deeper abstraction.

## Accessibility

### Minimum Rules

- Text must support Dynamic Type where practical.
- Tap targets should be at least 44 x 44.
- Do not rely on color alone for meaning.
- Processing and failure states need accessible text.
- Icon-only controls need accessibility labels.
- Dark text contrast must be checked manually on real screens.

### Motion Accessibility

Respect reduced motion for non-essential animation:

- Splash can simplify.
- Page entrances can become fade-only.
- Skeleton shimmer can become static placeholders.

## Content Voice

### Tone

The app should sound calm, direct, and slightly atmospheric.

Use:

- Short sentences.
- Concrete actions.
- Music scene language when it helps.

Avoid:

- Over-explaining features.
- Excessive poetry.
- Aggressive conversion copy.
- Fake AI magic.

### Product Copy Examples

Good:

- `开场之前，先进入状态`
- `把要去的音乐现场放进来，慢慢靠近那一场。`
- `截图识别`
- `链接解析`
- `手动填写`
- `正在识别截图`
- `识别不完整，可以手动补充`

Avoid:

- `让 AI 帮你开启沉浸式音乐旅程`
- `一键智能生成你的专属演出宇宙`
- `不升级就无法继续`

## Version 1 Scope

### Must Define Now

- Color tokens.
- Typography tokens.
- Spacing and radius.
- Button styles.
- Form fields.
- List rows.
- Empty states.
- Processing states.
- Pro badge and locked feature pattern.
- Add show option row.

### Can Wait

- Full light mode.
- Custom icon set.
- Custom font.
- Full chart system.
- Complex media editor.
- Multi-tab navigation.
- Platform-specific visual theming.
- Generalized cross-app package.

## Design Review Checklist

Before accepting a new screen:

- Does it use dark-first tokens?
- Does it feel native on iOS?
- Are gradients used sparingly?
- Are there unnecessary cards?
- Are repeated objects visually consistent?
- Is the primary action obvious?
- Is manual edit available after AI/OCR/parsing?
- Are error and empty states useful?
- Is Pro visible without dominating the page?
- Does the screen remain readable on small iPhones?
- Does text fit without overlap?
- Are tap targets large enough?
- Does the screen still work with longer Chinese copy?

## Implementation Review Checklist

Before merging UI code:

- No raw repeated color literals in feature views.
- No card nesting.
- No new button style without design system reason.
- No one-off row layout if an existing row primitive works.
- No feature-specific accent color unless approved.
- No custom animation longer than necessary.
- No icon-only important action without accessibility label.
- Snapshot or simulator verification for important screens.

## Open Questions

These are intentionally left for later product work:

- How long ended shows remain prominent on home.
- Whether show fragments eventually need their own tab.
- Whether Pro gets a dedicated upgrade page or sheet-first flow.
- Whether light mode is needed after v1.
- Whether a future DoubleWater shared package should extract these primitives.
