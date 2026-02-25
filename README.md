# OpenCodeQuota macOS Widget

macOS desktop widget for opencode that shows AI account quota usage for:

- OpenAI
- Zhipu AI
- Z.ai
- Google Cloud (Antigravity)
- GitHub Copilot

## Requirements

- macOS 14+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Generate and Run

1. Install XcodeGen if needed:

```bash
brew install xcodegen
```

2. Generate the Xcode project:

```bash
xcodegen generate
```

Or run:

```bash
./scripts/bootstrap.sh
```

3. Open `OpenCodeQuota.xcodeproj` in Xcode.
4. Verify signing team in target settings (project defaults currently use team `293A48LC7B`; change if needed).
5. Ensure App Group identifier is the same in both entitlements files and `Shared/SharedConstants.swift`.
6. Run the `OpenCodeQuotaApp` target once, confirm OpenCode credentials are detected, then add the widget.
7. If config files show sandbox permission errors, click `Grant File Access` and select your OpenCode's auth JSON file once.