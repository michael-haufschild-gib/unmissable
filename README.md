# Unmissable

A macOS menu bar app that ensures you never miss meetings with full-screen overlay alerts and one-click join.

## Features

- **Full-Screen Alerts** — Blocking overlay with countdown timer
- **Google Calendar Sync** — Secure OAuth 2.0 integration
- **Smart Link Detection** — Meet, Zoom, Teams, Webex
- **Multi-Display Support** — Alerts on all screens
- **Global Shortcuts** — Join/dismiss via keyboard
- **Snooze & Focus Mode** — Override Do Not Disturb

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 16+ / Swift 6.0

## Quick Start

```bash
# Install dev tools
brew install swiftlint swiftformat

# Configure Google OAuth (required)
cp Config.plist.example Config.plist
# Edit Config.plist with your Google OAuth Client ID

# Build and run
swift build && swift run
```

Get OAuth credentials from [Google Cloud Console](https://console.developers.google.com/) → Enable Calendar API → Create OAuth 2.0 credentials.

## Development

```bash
swift build          # Build
swift test           # Run tests
./Scripts/build.sh   # Full build + lint + test
./Scripts/format.sh  # Format code
```

## CI/CD

GitHub Actions workflows run automatically on push/PR:
- Code quality (SwiftLint, SwiftFormat)
- Unit, integration, performance, and memory tests
- Security scan and production readiness report

## Dependencies

- [AppAuth-iOS](https://github.com/openid/AppAuth-iOS) — OAuth 2.0
- [GRDB.swift](https://github.com/groue/GRDB.swift) — SQLite
- [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess) — Keychain
- [Magnet](https://github.com/Clipy/Magnet) — Global shortcuts
- [SnapshotTesting](https://github.com/pointfreeco/swift-snapshot-testing) — UI tests

## Privacy

All data stays on your device. OAuth tokens in Keychain, events cached in SQLite. No telemetry.

## License

Copyright © 2025 Unmissable. All rights reserved.
