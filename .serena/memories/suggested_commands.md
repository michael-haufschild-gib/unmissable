# Commands Reference

## Build & Run
- `swift build` — Debug build
- `swift build -c release` — Release build
- `swift run` — Run debug build
- `./Scripts/build.sh` — Full build + lint + format + test cycle

## Testing
- `./Scripts/test.sh` — Run all tests (4-worker parallel limit, recommended)
- `./Scripts/test.sh UnmissableTests` — Run specific test target
- `./Scripts/test.sh UnmissableTests/ThemeManagerTests` — Run specific test class
- `./Scripts/run-comprehensive-tests.sh` — Deep test suite (unit + integration + E2E + performance)
- Do NOT run bare `swift test` — no worker limit, spawns unlimited processes

## Code Quality
- `./Scripts/format.sh` — Run SwiftFormat with project config
- `swiftlint lint` — Check for lint issues (informational)
- `swiftlint --fix` — Auto-fix where possible

## Configuration
- Google OAuth: copy `Config.plist.example` to `Config.plist`, add credentials
- CI: use `GOOGLE_OAUTH_CLIENT_ID` environment variable