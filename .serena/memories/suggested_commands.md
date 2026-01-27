# Suggested Commands

## Build & Run
- **Build**: `swift build` or `./Scripts/build.sh` (builds + runs checks)
- **Run**: `swift run`

## Testing
- **Run All Tests**: `./Scripts/run-comprehensive-tests.sh` (Includes Unit, Integration, UI, Performance, Memory)
- **Run Unit Tests**: `swift test`
- **Run Specific Test Suite**: `xcodebuild -scheme Unmissable -destination 'platform=macOS' test -only-testing:"UnmissableTests"`

## Code Quality
- **Format Code**: `./Scripts/format.sh`
- **Lint Check**: `swiftlint`

## Utility Scripts
- `Scripts/build.sh` - Full build/lint/test cycle
- `Scripts/run-comprehensive-tests.sh` - Deep testing suite for production readiness
- `Scripts/format.sh` - Auto-formatter
- `Scripts/cleanup-test-data.sh` - Helper to reset state

## macOS (Darwin) Utilities
- `git` - Version control
- `ls`, `cd` - Directory navigation
- `grep`, `rg` (ripgrep) - Text search
- `find` - File search
- `open` - Open files/directories in Finder or default app