# Unmissable

## Identity
macOS menu bar app that ensures users never miss meetings via full-screen blocking overlays, calendar integration (Google + Apple), smart meeting link detection, and one-click join.

## Tech Stack
Swift 6 language mode / toolchain 6.3 (strict concurrency) | macOS 15.0+ (Sequoia) | SwiftUI + AppKit | GRDB.swift | Xcode project (xcodegen)

## Constraints

| Constraint | Rule |
|-----------|------|
| Concurrency | Swift 6 strict concurrency + ApproachableConcurrency in all targets. Sources use `defaultIsolation(MainActor.self)`. |
| UI tokens | All UI must use design system tokens. Raw values are lint errors. See `docs/meta/styleguide.md`. |
| Test safety | Never instantiate `OverlayManager` or `AppState()` in tests. Use `TestSafeOverlayManager` / `isTestEnvironment: true`. |
| Logging | `OSLog` only (subsystem `com.unmissable.app`). No `print()`. No PII. |
| IUO ban | No `!` (implicitly unwrapped optionals) in `Sources/`. Tests may use IUO for `setUp`/`tearDown`. |
| Privacy | No external telemetry. Redact sensitive data in logs. |

## Dependencies

AppAuth-iOS (OAuth 2.0) | GRDB.swift (SQLite) | KeychainAccess | Magnet (shortcuts) | SnapshotTesting

## Commands

| Task | Command |
|------|---------|
| Build | `xcodebuild build -project Unmissable.xcodeproj -scheme Unmissable -quiet` |
| Build + lint + test | `./Scripts/build.sh` |
| Lint only | `./Scripts/enforce-lint.sh` |
| Run | `./Scripts/run-dev.sh` |
| Release build | `./Scripts/build-release.sh` |
| Format | `./Scripts/format.sh` |
| Test (all) | `./Scripts/test.sh` |
| Test (specific target) | `./Scripts/test.sh UnmissableTests` |
| Test (UI / XCUITest) | `./Scripts/test-ui.sh` |
| Test (skip lint) | `./Scripts/test.sh --skip-lint` |
| Test (clean build) | `./Scripts/test.sh --clean` |
| Test (comprehensive) | `./Scripts/run-comprehensive-tests.sh` |
| Regenerate xcodeproj | `xcodegen generate` |

Do **not** run bare `swift test` or `xcodebuild test` without worker limits. `test.sh` outputs `PASS`/`FAIL`/`BUILD_FAIL`/`LINT_FAIL`/`TIMEOUT` and writes `.build/test-result.json`.

## Project Structure
`project.yml` is the source of truth for the Xcode project. Run `xcodegen generate` after editing it. The generated `Unmissable.xcodeproj` is committed to git.

## Configuration
Google Calendar OAuth: copy `Config.plist.example` to `Config.plist` (gitignored) and add credentials. CI uses `GOOGLE_OAUTH_CLIENT_ID` env var.

## Required Reading
@docs/architecture.md
@docs/testing.md
@docs/meta/styleguide.md

## On-Demand References

| Domain | Serena Memory |
|--------|---------------|
| Swift 6.3 changes & pitfalls | `swift_6_3_guide` |
