# Code Style and Conventions

## Swift Version
- **Production code**: Swift 6.0 with StrictConcurrency enabled
- **Tests**: Swift 5 language mode for compatibility

## Formatting
- Strict adherence to `.swiftformat` and `.swiftlint.yml` configuration files
- Run `./Scripts/format.sh` before committing

## Naming Conventions
- Swift standard naming conventions apply
- Classes/Structs: PascalCase (e.g., `EventScheduler`, `OverlayManager`)
- Functions/Methods: camelCase (e.g., `scheduleAlert`, `showOverlay`)
- Properties: camelCase
- Constants: camelCase or UPPER_SNAKE_CASE for global constants

## Testing Requirements
New features must include tests:
- **Unit**: Core logic
- **Snapshot**: UI components
- **Integration**: Service interactions

## Privacy
- PII must be redacted in logs (using `OSLog`)
- No external telemetry

## Architecture Patterns
- Modular architecture with feature-based organization
- SwiftUI for App UI, AppKit for Overlay/Windows
- Manager pattern for business logic (e.g., `OverlayManager`, `SyncManager`)
- Service pattern for external integrations (e.g., `CalendarService`, `OAuth2Service`)