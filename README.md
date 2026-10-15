# BeforeShow（开场前）

iOS concert companion: count down to a show, get familiar with its songs, and keep footprints afterwards. Live on the App Store.

## Structure

- `apps/ios`: the app (SwiftUI, SwiftData, iOS 26+). `BeforeShow/` app, `BeforeShowWidgets/` widgets and Live Activity, `Shared/` code both need. Architecture: `apps/ios/ARCHITECTURE.md`.
- `apps/web`: website, legal pages and invitation landing (Next.js on Cloudflare Pages).
- `apps/cloudbase-functions`: feedback backend (Tencent CloudBase).
- `docs/adr/`: decisions. `GLOSSARY.md`: product language. `docs/archive/`: delivered plans, historical only.

## iOS

```bash
./scripts/setup-hooks.sh   # once per clone: commit-msg + architecture pre-commit hooks
cd apps/ios
xcodegen generate          # project.yml is the source of truth
xcodebuild -project BeforeShow.xcodeproj -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=29C8MS76CZ build
python3 scripts/check_architecture.py
```

Why the team flag matters: `AGENTS.md`.

## Web

```bash
npm install
npm run dev
npm run build:web
```
