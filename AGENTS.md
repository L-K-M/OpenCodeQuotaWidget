# AGENTS.md

## What This Is

**OpenCodeQuota** is a standalone macOS desktop widget app that displays AI
provider quota/usage information. It reads credentials from local OpenCode config
files and shows usage data via WidgetKit widgets on the macOS desktop.

Supported providers: OpenAI, Zhipu AI, Z.ai, Google Cloud (Antigravity),
GitHub Copilot.

## Data Flow

1. Host app reads credentials from `~/.local/share/opencode/auth.json` and
   related OpenCode config files.
2. `QuotaCoordinator` fetches usage from each provider API in parallel.
3. Results are saved as a `QuotaSnapshot` JSON file to a shared location.
4. `WidgetCenter.shared.reloadTimelines(...)` triggers widget refresh.
5. Widget extension reads the snapshot JSON and renders the UI.

## Hard Constraints

- No build/runtime dependency on files outside this directory.
- Credentials loaded from local OpenCode config files, never manually entered.
- Credentials must not appear in source control, logs, or widget UI.
- Provider APIs are unstable; fail gracefully and show stale/partial data.

## Build

Requires macOS 14+, Xcode 15+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen   # if needed
xcodegen generate
open OpenCodeQuota.xcodeproj
```

Set `DEVELOPMENT_TEAM` in Xcode for your own Apple Developer team before
building.

## WidgetKit Notes

- Widgets ship as a Widget Extension target embedded in a macOS app.
- Timeline reloads are system-budgeted (~40-70/day). Keep entries >= 5 min apart.
- Use `WidgetCenter.reloadTimelines(ofKind:)` only when data actually changes.
- The containing app must be launched at least once for widgets to appear in the
  gallery.
- Widgets use SwiftUI only (no AppKit/UIKit representables).
