# Unmissable

A macOS menu bar app that ensures you never miss meetings with full-screen overlay alerts and one-click join.

Vibecoded with [Claude Code](https://claude.ai/code).

## Features

- **Full-Screen Alerts** — Blocking overlay with countdown timer
- **Google Calendar Sync** — Secure OAuth 2.0 integration
- **Apple Calendar Sync** — Native EventKit integration (iCloud, Exchange, CalDAV)
- **Smart Link Detection** — Meet, Zoom, Teams, Webex
- **Multi-Display Support** — Alerts on all screens
- **Global Shortcuts** — Join/dismiss via keyboard
- **Snooze** — Postpone alerts with configurable snooze timers
- **Auto-Updates** — Sparkle-powered update checks

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 16.3+ / Swift 6.1

## Quick Start

```bash
# Install dev tools
brew install swiftlint swiftformat

# Configure Google OAuth (optional — Apple Calendar works without it)
cp Config.plist.example Config.plist
# Edit Config.plist with your Google OAuth Client ID

# Build and run
./Scripts/run-dev.sh
```

Get OAuth credentials from [Google Cloud Console](https://console.developers.google.com/) — Enable Calendar API — Create OAuth 2.0 credentials.

## Development

```bash
swift build          # Build
swift test           # Run unit tests via SPM
./Scripts/build.sh   # Full build + lint + test
./Scripts/format.sh  # Format code
```

## CI/CD

GitHub Actions runs on push/PR to `main`:
- Build verification (`swift build`)
- Code quality (SwiftLint strict, SwiftFormat lint)
- Unit tests (`swift test --filter UnmissableTests`)
- Integration tests (`swift test --filter IntegrationTests`)
- E2E tests (`swift test --filter E2ETests`)

## Dependencies

- [AppAuth-iOS](https://github.com/openid/AppAuth-iOS) — OAuth 2.0
- [GRDB.swift](https://github.com/groue/GRDB.swift) — SQLite
- [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess) — Keychain
- [Magnet](https://github.com/Clipy/Magnet) — Global shortcuts
- [Sparkle](https://github.com/sparkle-project/Sparkle) — Auto-updates

## Privacy

All data stays on your device. OAuth tokens in Keychain, events cached in SQLite. No telemetry.

## License

MIT — see [LICENSE](LICENSE).
