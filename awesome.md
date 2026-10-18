# OpenCodeQuota — Code Review & Ideas

A thorough review of the current codebase: bugs, general issues, missing
features, and ideas for improvements. Items marked **[PR planned]** are ones
with high enough confidence that they're being implemented in follow-up PRs;
the rest are documented here for discussion.

---

## 1. Bugs

### 1.1 Widget reset countdowns are stale **[PR planned]**
`MyStatusWidgetExtension/MyStatusQuotaWidget.swift` — `resetSummaries(for:)`
prefers `metric.resetIn`, which is a **static string** formatted at fetch time
(e.g. `"1h 42m"`). The timeline renders entries every 5 minutes for up to the
whole refresh interval (15–180 min), but the displayed countdown never moves
because the string was baked when the snapshot was fetched.

Worse, the fallback `relativeResetSummary(until:)` calls `Date()`. WidgetKit
archives **all timeline entries at timeline-creation time**, so `Date()`
evaluates once when the timeline is built — every future entry shows the same
(immediately stale) countdown.

**Fix:** compute the countdown from `metric.resetAt` relative to the entry's
`date`, and only fall back to the static `resetIn` string when no `resetAt`
exists.

### 1.2 A failed refresh wipes good widget data **[PR planned]**
`RefreshService.refresh` unconditionally saves whatever the coordinator
returns. If the network is down (laptop asleep, VPN flap), the new snapshot
contains zero providers and N failures — and it **overwrites the last good
snapshot**. Widgets then show "No providers configured" until the next
successful refresh, violating the AGENTS.md constraint: *"Provider APIs are
unstable; fail gracefully and show stale/partial data."*

**Fix:** merge the fresh snapshot with the previous one — for each failed
provider, carry forward the last known `ProviderUsage` (its `fetchedAt` stays
old, so staleness is still visible) while keeping the failure recorded.

### 1.3 `parseNumeric` uses character count for `NSRange` **[PR planned]**
`Packages/QuotaCore/Sources/QuotaCore/Utilities.swift:46` —
`NSRange(location: 0, length: normalized.count)` uses Swift `Character` count,
but `NSRegularExpression` operates on UTF-16 code units. Any non-BMP character
(emoji, some CJK) in the string makes the range wrong and can mis-parse or
crash-adjacent truncate. Should be `normalized.utf16.count`.

### 1.4 `OpenAIUsageResponse.plan_type` is non-optional **[PR planned]**
`OpenAIClient.swift:101` — if OpenAI ever omits `plan_type` (these are
unofficial endpoints that change without notice), the whole decode throws and
the provider errors out, even though everything actually needed
(`rate_limit`) might be present. Should be `String?`.

### 1.5 README lists "GitHub Copilot" twice **[PR planned]**
`README.md` lines 11–12 — duplicate bullet.

### 1.6 Per-provider "enabled" setting exists but does nothing
`AppSettings.providers[].isEnabled` is modeled, persisted, and round-trip
tested — but `AppModel` always passes `allProvidersEnabled()` (everything
true) to the credential loader, and `currentSettings()` always writes
`isEnabled: true` back. There is no UI toggle either. So the setting is dead
weight today. See feature 3.1 **[PR planned]**.

### 1.7 Disabled/unconfigured providers vanish silently
`QuotaCoordinator.refresh` filters out configurations where
`isEnabled == false` (which the loader sets when credentials are missing), so
they never appear in `failures` with kind `.notConfigured` — the error kind
exists but is unreachable from the coordinator path. The dashboard "N
unavailable" count therefore under-reports relative to what users may expect.

---

## 2. General issues

### 2.1 Hex-color parsing is implemented five times
Nearly identical hex→RGBA parsing exists in:
- `Models.swift` (`normalizeHexColor`)
- `AppModel.swift` (`parseHexColor`)
- `MyStatusApp.swift` (`NSColor(hexString:)`)
- `MyStatusQuotaWidget.swift` (`Color(hexColor:)` **and** `backgroundBaseColor(from:)`)

These have already drifted (the widget version clamps alpha to ≥ 0.72 in one
copy). A single `HexColor` utility in `QuotaCore` would remove ~120 lines and
prevent future drift.

### 2.2 `monthEndDate` is misnamed
`Utilities.swift` — it returns the **start of the next month**, not the end of
the given month. The semantics callers want are correct, but the name invites
future misuse.

### 2.3 `reloadAllTimelines()` vs. the widget budget
AGENTS.md says to use `reloadTimelines(ofKind:)` only when data changes, but
`AppModel` calls `WidgetCenter.shared.reloadAllTimelines()` after every
refresh **and** every settings save (including each keystroke-ish color picker
change). macOS budgets widget reloads; rapid style tweaking can exhaust it and
make widgets go stale for the rest of the day.

### 2.4 Copilot internal API failures are reported as `.auth`
`CopilotClient.fetchInternalUser` returns `nil` for *any* non-2xx except 429
(including 500s), and the chain ends with a generic `.auth` error telling the
user to configure a PAT file — misleading when GitHub is simply having an
outage.

### 2.5 Google OAuth client secret embedded in source
`GoogleAntigravityClient.swift` hard-codes the Antigravity OAuth
`client_secret`. For an installed-app OAuth flow this is by definition not
secret (it ships in the Antigravity binary too), but it's worth a comment
explaining that this is the well-known public client credential, so future
readers don't think a real secret was leaked.

### 2.6 No tests for any provider client
`QuotaCore` has a clean `HTTPClient` seam, but none of the four clients have a
single test. JSON-shape regressions (the most likely failure mode given
unofficial APIs) are entirely uncovered. **[PR planned]**

### 2.7 No CI
There is no GitHub Actions workflow. `QuotaCore` is a plain SwiftPM package —
`swift test` on a macOS runner would catch decode/logic regressions on every
PR. **[PR planned]**

### 2.8 History store does load-modify-save with no coordination
`QuotaHistoryStore.append` reads, mutates, writes. Today only the app writes
(MainActor-serialized), so it's safe, but the class is `@unchecked Sendable`
and nothing enforces single-writer. A note or an `NSFileCoordinator` would
future-proof it.

---

## 3. Missing features

### 3.1 Provider enable/disable toggles **[PR planned]**
The model supports it (see bug 1.6); wire it up: per-provider toggle in the
provider tabs, persist through `AppSettings.providers`, pass the real map to
the credential loader so disabled providers aren't fetched or shown.

### 3.2 Stale-data indicator in widgets **[PR planned]**
When the snapshot is older than ~2× the refresh interval (app quit, Mac
asleep), widgets show the old timestamp in the normal secondary color —
easy to miss. Tint the timestamp orange when data is stale so users know the
numbers can't be trusted.

### 3.3 Anthropic / Claude provider
The app is "OpenCode quota" but doesn't cover Claude Pro/Max OAuth accounts
stored in the same `auth.json` (key `anthropic`). The usage endpoint used by
community tools is unofficial and shifts frequently, so this is intentionally
*not* implemented blind — but it's the most-requested-shaped gap in coverage.

### 3.4 Threshold notifications
A local notification ("OpenAI 7-day limit below 10%") via
`UNUserNotificationCenter` when a metric crosses a configurable threshold.
The refresh loop already runs in the app; this is mostly plumbing + settings
UI.

### 3.5 Widget tap-through (`widgetURL`)
Tapping a widget currently does nothing useful. A custom URL scheme +
`.widgetURL(...)` could open the settings window or trigger a refresh.

### 3.6 Diagnostics export
The credential loader builds rich diagnostics strings; a "Copy diagnostics"
button in the Access tab would make bug reports dramatically better.

---

## 4. Novel / delightful ideas

### 4.1 Menu-bar "burn-down" sparkline
The menu bar icon already draws per-provider bars. A variant that draws the
*trend* (last 24 h of the most-constrained metric) as a tiny sparkline would
let you see at a glance whether you're burning quota fast — the depletion
heuristic from the trend widget (`depletionWarnings`) already exists and could
tint the sparkline red when you're projected to run out before reset.

### 4.2 "Quota weather" forecast
The trend widget already projects depletion (`depletionWarnings`). Take it
further: show a forecast line (dashed) extrapolating the recent slope to the
reset time, so the chart answers "will I make it?" visually instead of with a
one-line warning.

### 4.3 Reset-time party
When a metric resets (remaining jumps from <20% to ~100% between snapshots),
flash a subtle confetti/glow on the provider ring for the first timeline entry
after the reset. WidgetKit can't animate continuously, but a one-entry special
state is free.

### 4.4 Adaptive refresh cadence
Refresh faster when usage is changing fast or a reset is imminent, slower when
quotas are flat. The history store has everything needed to compute "interest"
per provider; this would respect the widget reload budget better than a fixed
interval.

### 4.5 Pace marker on rings
For time-windowed quotas (e.g. OpenAI's 7-day window), draw a small tick on
the ring at the "ideal pace" position (elapsed-window fraction). If the
remaining arc is behind the tick, you're over-pacing — a single glance tells
you more than the percentage does.

### 4.6 Focus-aware transparency
When the desktop wallpaper is dark, the `FancyWidgetBackground` glow looks
great; on light wallpapers less so. A toggle to follow system appearance for
the default background (it currently always renders the same gradient) would
make the "Default" preset feel native in light mode.

---

## Implementation plan (follow-up PRs)

| PR | Scope | Items |
|----|-------|-------|
| this PR | docs only | awesome.md, README duplicate fix (1.5) |
| QuotaCore fixes + tests | `Packages/QuotaCore`, `RefreshService` | 1.1-adjacent merge logic (1.2), 1.3, 1.4, 2.6 |
| Widget freshness | `MyStatusWidgetExtension` | 1.1, 3.2 |
| Provider toggles | `MyStatusApp` | 1.6, 3.1 |
| CI | `.github/workflows` | 2.7 |

PRs are partitioned by directory to minimize merge conflicts.
