# Unmissable - Project Overview

## Purpose
Unmissable is a macOS menu bar application designed to ensure users never miss meetings. It features a full-screen blocking overlay with a countdown timer, Google Calendar integration, and smart meeting detection.

## Tech Stack
- **Platform**: macOS 14.0+ (Sonoma)
- **Language**: Swift 6.0 with StrictConcurrency enabled
- **UI Frameworks**: SwiftUI (App UI), AppKit (Overlay/Windows)
- **Data Persistence**: SQLite (via GRDB.swift)
- **Authentication**: OAuth 2.0 (via AppAuth-iOS)
- **Build System**: Swift Package Manager (SPM)

**Note**: Tests use Swift 5 language mode for compatibility; production code uses Swift 6.

## Key Dependencies
- **AppAuth-iOS**: Google Calendar OAuth 2.0
- **GRDB.swift**: Local SQLite database
- **KeychainAccess**: Secure token storage
- **Magnet**: Global keyboard shortcuts
- **SnapshotTesting**: UI visual regression testing

## Prerequisites
- Xcode 16+
- Swift 6.0+
- `swiftlint` and `swiftformat` (via Homebrew)

## Configuration
Google Calendar API requires OAuth credentials.
- **Local Dev**: Copy `Config.plist.example` to `Config.plist` and add credentials
- **CI/Deployment**: Use `GOOGLE_OAUTH_CLIENT_ID` environment variable