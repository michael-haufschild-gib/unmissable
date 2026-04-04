# Development Guide

**Purpose**: Setup, building, running, and deploying Unmissable.
**Platform**: macOS 14.0+ (Sonoma) | Swift 6.3 with strict concurrency | SPM

---

## Prerequisites

| Requirement | Minimum Version | Install Command |
|-------------|-----------------|-----------------|
| macOS | 14.0 (Sonoma) | - |
| Xcode | 16+ | App Store |
| Swift | 6.3+ | Included with Xcode 26+ |
| SwiftFormat | Latest | `brew install swiftformat` |
| SwiftLint | Latest | `brew install swiftlint` |

---

## Quick Setup

```bash
# 1. Clone and enter project
cd /path/to/unmissable

# 2. Install dev tools
brew install swiftformat swiftlint

# 3. Configure OAuth (required for Google Calendar)
cp Config.plist.example Config.plist
# Edit Config.plist and add your Google OAuth credentials

# 4. Build
swift build

# 5. Run
./Scripts/run-dev.sh
```

---

## Key Commands

| Task | Command |
|------|---------|
| Build | `swift build` |
| Run | `./Scripts/run-dev.sh` |
| Test (XCTest) | `xcodebuild -scheme Unmissable -destination 'platform=macOS' test` |
| Test (comprehensive) | `./Scripts/run-comprehensive-tests.sh` |
| Format code | `./Scripts/format.sh` |
| Build + lint + test | `./Scripts/build.sh` |
| Build release | `./Scripts/build-release.sh` |
| Clean build | `swift package clean` |

---

## Configuration

### Google Calendar OAuth (Required)

**For local development**:
1. Copy `Config.plist.example` to `Config.plist`
2. Add your Google Cloud Console credentials:
   - `GOOGLE_OAUTH_CLIENT_ID`
   - Any other required keys

**For CI/Production**:
- Set environment variable: `GOOGLE_OAUTH_CLIENT_ID`

**File location**: `Config.plist` (project root, gitignored)

---

## Build Configurations

### Debug Build
```bash
swift build
# Output: .build/debug/Unmissable
```

### Release Build
```bash
swift build -c release
# Output: .build/release/Unmissable
```

### Build with Xcode
```bash
xcodebuild -scheme Unmissable -destination 'platform=macOS' build
```

---

## Running the App

### From Terminal
```bash
# Debug (builds + assembles .app bundle + launches)
./Scripts/run-dev.sh
```

> **Note:** Do not use bare `swift run` — it produces an executable without an `.app` bundle,
> so `UNUserNotificationCenter` and Sparkle crash on startup.

### From Xcode
1. Open `Package.swift` in Xcode
2. Select `Unmissable` scheme
3. Press Cmd+R

---

## Code Quality

### Format Before Commit
```bash
# Auto-format all code
./Scripts/format.sh

# Or directly
swiftformat .
```

### Lint Check
```bash
# Check for issues
swiftlint lint

# Enforced policy used by test scripts (fails on hard rules)
./Scripts/enforce-lint.sh

# Auto-fix where possible
swiftlint --fix
```

### Full Build Cycle
```bash
# Build + lint + format check + test
./Scripts/build.sh
```

---

## Testing

### Quick Test Run
```bash
xcodebuild -scheme Unmissable -destination 'platform=macOS' test
```

### Comprehensive Test Suite
```bash
# Runs: unit + integration + UI + performance + memory tests
./Scripts/run-comprehensive-tests.sh
```

### Specific Tests
```bash
# Run single test class
xcodebuild -scheme Unmissable -destination 'platform=macOS' test -only-testing:UnmissableTests/EventTests

# Run single test method
xcodebuild -scheme Unmissable -destination 'platform=macOS' test -only-testing:UnmissableTests/EventTests/testEventInitialization

# Run via xcodebuild
xcodebuild -scheme Unmissable -destination 'platform=macOS' test

# Optional smoke check (non-authoritative for this repo setup)
swift test
```

### Test Reports
After running `./Scripts/run-comprehensive-tests.sh`:
- Logs: `test-reports/*.log`
- Results: `test-reports/*.xcresult`
- Coverage: `coverage/`

---

## Troubleshooting

### Build Fails with Missing Dependencies
```bash
# Reset package cache
swift package reset
swift package resolve
swift build
```

### Tests Fail with Permission Errors
```bash
# Grant accessibility permissions
# System Settings > Privacy & Security > Accessibility > Terminal (or Xcode)
```

### OAuth Callback Not Working
1. Verify URL scheme is registered in app
2. Check `GOOGLE_OAUTH_CLIENT_ID` is set correctly
3. Verify redirect URI matches Google Cloud Console

### SwiftFormat/SwiftLint Not Found
```bash
brew install swiftformat swiftlint
```

### Clean and Rebuild
```bash
swift package clean
rm -rf .build
swift build
```

---

## Project Scripts Reference

| Script | Purpose |
|--------|---------|
| `Scripts/build.sh` | Full build + lint + test cycle |
| `Scripts/format.sh` | Run SwiftFormat on codebase |
| `Scripts/run-comprehensive-tests.sh` | Complete test suite with reports |
| `Scripts/build-release.sh` | Create release build |
| `Scripts/cleanup-test-data.sh` | Reset test state/data |
| `Scripts/install.sh` | Install app locally |

---

## Development Workflow

### Adding a New Feature
1. Create feature branch: `git checkout -b feature/name`
2. Create feature folder: `Sources/Unmissable/Features/[Name]/`
3. Implement manager + views
4. Add tests in `Tests/UnmissableTests/`
5. Run `./Scripts/build.sh` to verify
6. Commit with descriptive message

### Fixing a Bug
1. Write failing test first
2. Fix the bug
3. Verify test passes
4. Run `./Scripts/build.sh`
5. Commit

### Before Committing
```bash
# Always run
./Scripts/format.sh
./Scripts/build.sh
```

---

## Environment Variables

| Variable | Purpose | Required |
|----------|---------|----------|
| `GOOGLE_OAUTH_CLIENT_ID` | Google Calendar OAuth | Production only |

---

## Common Mistakes

**Setup**:
- Don't skip creating `Config.plist` for local dev
- Do copy from `Config.plist.example` and fill in values
- Don't commit `Config.plist` (it's gitignored)
- Do use environment variables for CI

**Building**:
- Don't forget to run `swift package resolve` after adding dependencies
- Do clean build if you see strange errors: `swift package clean`
- Don't ignore SwiftLint warnings
- Do fix them before committing

**Running**:
- Don't run without granting accessibility permissions
- Do check System Settings > Privacy & Security
- Don't expect OAuth to work without valid credentials
- Do set up Google Cloud Console project first

**Testing**:
- Don't skip tests before committing
- Do run at least `xcodebuild -scheme Unmissable -destination 'platform=macOS' test`
- Don't commit with failing tests
- Do run comprehensive tests before PRs: `./Scripts/run-comprehensive-tests.sh`

---

## Performance Expectations

Unmissable is a lightweight menu bar app. It should be invisible when idle.

| Path | Budget | Measurement |
|------|--------|-------------|
| Cold launch to menu bar icon | < 2s | Stopwatch or `ProcessInfo.systemUptime` delta |
| Calendar sync cycle | < 10s (network-bound) | `SyncManager` logs elapsed time |
| DB query: fetchUpcomingEvents | < 100ms | `DatabaseManager.withTimeout` (30s hard cap) |
| Overlay window creation | < 200ms | `OverlayManager.showOverlay` logs response time |
| Idle memory | < 50 MB | `HealthMonitor.metrics.memoryUsageMB` (warns at 200 MB) |

**If a path exceeds its budget**: check `OSLog` output filtered by the relevant subsystem category. The `HealthMonitor` logs memory and reports stuck overlays.

**No automated performance regression tests exist** — the paths above are dominated by I/O (network, SQLite, AppKit window creation) where micro-benchmarks add noise, not signal. Monitor via `HealthMonitor` and OSLog in production.
