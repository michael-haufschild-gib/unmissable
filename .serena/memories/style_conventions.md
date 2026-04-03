# Code Style and Conventions

## Swift Version
- **Production code**: Swift 6.1 with StrictConcurrency enabled
- **Tests**: Swift 5 language mode for compatibility

## Formatting (SwiftFormat)
- 4 spaces indent, 120 char max width, LF line breaks
- Trailing commas always, semicolons never
- Attributes on previous line (`@MainActor`, `@Published`)
- Wrap arguments before-first, balanced closing paren
- Blank line after each switch case
- Number grouping: groups of 3, starting at 5+ digits
- Run `./Scripts/format.sh` before committing

## Lint (SwiftLint)
- File: 500 lines, function body: 80 lines, type body: 500 lines
- Closure body: 100 lines, cyclomatic complexity: 12
- Line length: 120 chars (URLs exempt, comments not)
- All thresholds are warning=error (no separate warning tier)
- Custom test quality rules ban shallow assertions, raw Task.sleep, real OverlayManager, etc.

## Naming
- Types: PascalCase, 3-60 chars
- Identifiers: camelCase, 1-60 chars
- Protocols: `-Managing` (managers), `-Providing` (data providers)
- UI components: `UM` prefix (`UMButtonStyle`, `UMSection`)
- Design tokens: `Design` prefix (`DesignTokens`, `DesignColors`)

## Design System
All UI must use design tokens from `DesignTokens.swift`. Raw Color/Font/cornerRadius values are lint errors.
See Serena memory `design_system_patterns` for detailed examples.

## Architecture Patterns
- Modular architecture with feature-based organization
- SwiftUI for App UI, AppKit for Overlay/Windows
- Manager pattern for business logic (e.g., `OverlayManager`, `SyncManager`)
- Service pattern for external integrations (e.g., `CalendarService`, `OAuth2Service`)
- Protocol-based DI with factory pattern for test safety
- `ServiceContainer` as DI root — no singletons

## Logging
- `OSLog` with subsystem `com.unmissable.app`, category matching class name
- No `print()` in production code
- No PII in logs