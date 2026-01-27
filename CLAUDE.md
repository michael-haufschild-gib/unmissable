# Unmissable - Project Context

## Overview
**Unmissable** is a macOS menu bar application designed to ensure users never miss meetings. It features a full-screen blocking overlay with a countdown timer, Google Calendar integration, and smart meeting detection.

## Tech Stack
- **Platform**: macOS 14.0+ (Sonoma)
- **Language**: Swift 6.0 with StrictConcurrency enabled
- **UI Frameworks**: SwiftUI (App UI), AppKit (Overlay/Windows)
- **Data Persistence**: SQLite (via GRDB.swift)
- **Authentication**: OAuth 2.0 (via AppAuth-iOS)
- **Build System**: Swift Package Manager (SPM)

## Architecture
The project follows a modular architecture within `Sources/Unmissable/`:
- **App/**: Entry point (`UnmissableApp.swift`), `AppDelegate`, `AppState`, `MenuBarView`.
- **Core/**: Business logic (`EventScheduler`, `DatabaseManager`, `SyncManager`, `LinkParser`).
- **Features/**: Feature-specific logic (`Overlay`, `CalendarConnect`, `FocusMode`, `Shortcuts`).
- **Models/**: Data structures (`Event`, `Provider`, `ScheduledAlert`).
- **Config/**: Configuration handling.

## Key Dependencies
- **AppAuth-iOS**: Google Calendar OAuth 2.0.
- **GRDB.swift**: Local SQLite database.
- **KeychainAccess**: Secure token storage.
- **Magnet**: Global keyboard shortcuts.
- **SnapshotTesting**: UI visual regression testing.

## Development Workflow

### Prerequisites
- Xcode 16+
- Swift 6.0+
- `swiftlint` and `swiftformat` (via Homebrew)

### Build & Run
- **Build**: `swift build` or `./Scripts/build.sh` (builds + runs checks)
- **Run**: `swift run`
- **Format Code**: `./Scripts/format.sh`

### Testing
The project has a comprehensive test suite.
- **Run All Tests**: `./Scripts/run-comprehensive-tests.sh` (Includes Unit, Integration, UI, Performance, Memory)
- **Run Unit Tests**: `swift test`
- **Run Specific Test Suite**: `xcodebuild -scheme Unmissable -destination 'platform=macOS' test -only-testing:"UnmissableTests"`

### Configuration
Google Calendar API requires OAuth credentials.
- **Local Dev**: Copy `Config.plist.example` to `Config.plist` and add credentials.
- **CI/Deployment**: Use `GOOGLE_OAUTH_CLIENT_ID` environment variable.

## Project Conventions
- **Formatting**: Strict adherence to `.swiftformat` and `.swiftlint.yml`. Run `./Scripts/format.sh` before committing.
- **Testing**: New features must include tests.
    - **Unit**: Core logic.
    - **Snapshot**: UI components.
    - **Integration**: Service interactions.
- **Privacy**: PII must be redacted in logs (using `OSLog`). No external telemetry.

## Directory Structure
```text
Sources/Unmissable/
├── App/            # Main application lifecycle & Menu Bar UI
├── Config/         # Configuration & Secrets
├── Core/           # Shared Services (DB, Sync, Audio, Time)
├── Features/       # Isolated feature modules
│   ├── Overlay/    # Full-screen alert implementation
│   ├── ...
├── Models/         # Codable structs & GRDB records
├── Resources/      # Assets
```

## Script Reference
- `Scripts/build.sh`: Full build/lint/test cycle.
- `Scripts/run-comprehensive-tests.sh`: Deep testing suite for production readiness.
- `Scripts/format.sh`: Auto-formatter.
- `Scripts/cleanup-test-data.sh`: Helper to reset state.
