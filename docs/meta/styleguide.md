# Style Guide

**Purpose**: Immutable formatting, naming, and design system rules. Violations are lint errors.
**Enforced by**: `.swiftlint.yml`, `.swiftformat`, `Scripts/enforce-lint.sh`

---

## Formatting (SwiftFormat)

| Rule | Value |
|------|-------|
| Indent | 4 spaces |
| Max line width | 120 characters |
| Line breaks | LF |
| Trailing commas | Always required |
| Semicolons | Never |
| Wrap arguments | Before first |
| Closing paren | Balanced |
| Attributes | Previous line (`@MainActor`, `@Published`, etc.) |
| Switch cases | Blank line after each case |
| Number grouping | Groups of 3, starting at 5+ digits |

Run `./Scripts/format.sh` before committing. This runs `swiftformat .` with the project config.

---

## Length & Complexity Limits (SwiftLint)

| Metric | Limit | Notes |
|--------|-------|-------|
| Line length | 120 chars | URLs exempt, comments not exempt |
| File length | 500 lines | Comment-only lines excluded |
| Function body | 80 lines | Split if exceeded |
| Type body | 500 lines | |
| Closure body | 100 lines | |
| Cyclomatic complexity | 12 | Case statements count |
| Nesting (type) | 2 levels | |
| Nesting (function) | 3 levels | |
| Tuple size | 4 elements | |

---

## Naming

| Element | Convention | Limits |
|---------|-----------|--------|
| Types | PascalCase, 3-60 chars | `ThemeManager`, not `TM` |
| Identifiers | camelCase, 1-60 chars | `id`, `x`, `db` are allowed |
| Protocols | `-Managing` (managers), `-Providing` (data) | `OverlayManaging` |
| UI components | `UM` prefix | `UMButtonStyle`, `UMSection` |
| Design tokens | `Design` prefix | `DesignTokens`, `DesignColors` |

---

## Design System Enforcement

All UI code in `Sources/` must use the design token system. These are **lint errors**:

- Raw `Font.system(size:)` -> use `design.fonts.*`
- Raw `Color(red:)` / `Color(hue:)` / `Color(white:)` -> use `design.colors.*`
- `design: .rounded` -> use `.default` (SF Pro) or `.monospaced`
- `.cornerRadius(N)` -> use `.clipShape(RoundedRectangle(cornerRadius: design.corners.*))`
- `.buttonStyle(PlainButtonStyle())` -> use `.buttonStyle(UMButtonStyle(..))`
- Raw `.shadow(color: Color.*)` -> use `design.shadows.*`
- Hardcoded `.animation(.ease*(duration: N))` -> use `DesignAnimations.*`
- Legacy `Custom*` type names -> use `UM*` / `Design*` equivalents

New tokens go in `DesignTokens.swift`. New components go in `Styles.swift` or `Containers.swift`.

---

## Logging

| Rule | Detail |
|------|--------|
| Logger | `OSLog` with subsystem `com.unmissable.app` |
| No `print()` | Use `Logger` in all production code |
| No PII | Redact emails, names, personal data |
| Category | Match the class name: `Logger(subsystem: ..., category: "SyncManager")` |

---

## Production Safety

| Rule | Scope |
|------|-------|
| No force unwrapping (`!`) | `Sources/` only — UITests may use IUO (`Type!`) for XCTest `setUp`/`tearDown` |
| No `force_unwrapping` | Error severity in all code |
| `missing_docs` | Required for `public` and `open` declarations |
| `deployment_target` | macOS 15.0 minimum |

---

## Import Patterns

Use direct imports only. No barrel files or re-exports.

```swift
import Foundation
import OSLog
@testable import Unmissable  // tests only
```

## On-Demand References

| Domain | Serena Memory |
|--------|---------------|
| Full lint rule details | `lint_pipeline_notes` |
| Code conventions | `style_conventions` |
| Design system examples | `design_system_patterns` |
