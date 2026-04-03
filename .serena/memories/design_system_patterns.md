# Design System Patterns

## Architecture

The design system lives in three files in `Sources/Unmissable/Core/`:

- **DesignTokens.swift** — Token definitions: `ThemeManager`, `DesignTokens`, `DesignColors`, `DesignFonts`, `DesignSpacing`, `DesignCorners`, `DesignShadows`, `DesignAnimations`, `DesignTracking`
- **Styles.swift** — Interactive components: `UMButtonStyle`, `UMToggleStyle`, `UMStatusIndicator`, `UMBadge`
- **Containers.swift** — Layout components: `UMSection`, `.umCard()`, `.umGlass()`, `.umPickerStyle()`

## Theme System

`ThemeManager` is an `ObservableObject` that resolves theme mode (light/dark/system) and accent color.

### Theme Modes
- `.light`, `.dark`, `.system` (auto-detects macOS appearance)

### Accent Colors
Each `AccentColor` case provides `.color`, `.hoverColor`, `.pressedColor` variants.

### Color Palettes
`DesignColors` has 5 base palettes resolved by theme:
- `darkBluePalette` — hue 250 deep navy
- `darkPurplePalette` — hue 300 violet
- `darkBrownPalette` — hue 55 walnut
- `darkBlackPalette` — near-zero chroma
- `lightPalette` — clean zinc

## Using Tokens in Views

```swift
struct MyView: View {
    @Environment(\.design) var design

    var body: some View {
        Text("Hello")
            .font(design.fonts.headline)
            .foregroundStyle(design.colors.textPrimary)
            .padding(design.spacing.md)
    }
}

// Apply theme at root:
ContentView()
    .themed(themeManager)
```

## UMButtonStyle

```swift
// Variants: .primary, .secondary, .ghost, .danger
// Sizes: .small, .medium, .large
Button("Action") { }
    .buttonStyle(UMButtonStyle(.primary, size: .medium))
```

## UMToggleStyle

```swift
Toggle("Option", isOn: $value)
    .toggleStyle(UMToggleStyle())
```

## Containers

```swift
// Glass card
VStack { ... }
    .umGlass(cornerRadius: design.corners.lg)

// Standard card
VStack { ... }
    .umCard(.elevated)  // Styles: .subtle, .elevated

// Section with header
UMSection("General", icon: "gear") {
    // content
}

// Picker styling
Picker("Theme", selection: $theme) { ... }
    .umPickerStyle()
```

## Status & Badges

```swift
// Status indicator: .connected, .disconnected, .syncing, .error
UMStatusIndicator(.connected, size: 8)

// Badge variants: .accent, .success, .warning, .error, .muted
UMBadge("New", variant: .accent)
```

## Animation Tokens

```swift
withAnimation(DesignAnimations.press) { ... }    // Quick tap feedback
withAnimation(DesignAnimations.hover) { ... }    // Hover state
withAnimation(DesignAnimations.content) { ... }  // Content transitions
withAnimation(DesignAnimations.emphasis) { ... } // Attention-drawing
withAnimation(DesignAnimations.ambient) { ... }  // Slow background
```

## Tracking Tokens

```swift
Text("SECTION")
    .tracking(DesignTracking.sectionLabel)  // 1.5 wide spacing for labels
```

## Lint Rules

SwiftLint custom rules enforce the design system in all `Sources/` files (except the token files themselves):
- `no_raw_font_system_call` — bans `.system(size: N)`
- `no_raw_color_rgb` — bans `Color(red:)` etc.
- `no_design_rounded` — bans `design: .rounded`
- `no_hardcoded_corner_radius` — bans `.cornerRadius(N)`
- `no_plain_button_style` — bans `PlainButtonStyle()`
- `no_hardcoded_animation_duration` — bans hardcoded easing durations
- `no_raw_shadow` — bans raw `.shadow(color: Color.*)`
- `no_old_custom_components` — bans legacy `Custom*` type names