# Unmissable

## Identity
macOS menu bar app that ensures users never miss meetings via full-screen blocking overlays, calendar integration (Google + Apple), smart meeting link detection, and one-click join.

## Tech Stack
Swift 6.3 (strict concurrency) | macOS 14.0+ | SwiftUI + AppKit | GRDB.swift | SPM

## Constraints

| Constraint | Rule |
|-----------|------|
| Concurrency | Swift 6 strict concurrency in all targets (Sources and Tests). |
| UI tokens | All UI must use design system tokens. Raw values are lint errors. See `docs/meta/styleguide.md`. |
| Test safety | Never instantiate `OverlayManager` or `AppState()` in tests. Use `TestSafeOverlayManager` / `isTestEnvironment: true`. |
| Logging | `OSLog` only (subsystem `com.unmissable.app`). No `print()`. No PII. |
| IUO ban | No `!` (implicitly unwrapped optionals) in `Sources/`. Tests may use IUO for `setUp`/`tearDown`. |
| Privacy | No external telemetry. Redact sensitive data in logs. |

## Dependencies
AppAuth-iOS (OAuth 2.0) | GRDB.swift (SQLite) | KeychainAccess | Magnet (shortcuts) | Sparkle (updates) | SnapshotTesting

## Commands

| Task | Command |
|------|---------|
| Build | `swift build` |
| Build + lint + test | `./Scripts/build.sh` |
| Lint only | `./Scripts/enforce-lint.sh` |
| Run | `swift run` |
| Format | `./Scripts/format.sh` |
| Test (all) | `./Scripts/test.sh` |
| Test (specific target) | `./Scripts/test.sh UnmissableTests` |
| Test (specific class) | Not supported in Swift 6.3 — use target-level filters |
| Test (skip lint) | `./Scripts/test.sh --skip-lint` |
| Test (clean build) | `./Scripts/test.sh --clean` |
| Test (comprehensive) | `./Scripts/run-comprehensive-tests.sh` |

Do **not** run bare `swift test` — it has no worker limit. `test.sh` outputs `PASS`/`FAIL`/`BUILD_FAIL`/`LINT_FAIL`/`TIMEOUT` and writes `.build/test-result.json`.

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
