import AppKit
import CoreGraphics
import SwiftUI

/// Visual mini-map of connected displays, mirroring macOS Display Settings arrangement.
/// Each display is a clickable rectangle that toggles its selection state.
struct DisplayArrangementView: View {
    @Environment(PreferencesManager.self)
    private var preferences
    @Environment(\.design)
    private var design

    /// Live screen list — refreshed on screen parameter changes.
    @State
    private var screenInfos: [ScreenInfo] = []

    // MARK: - Layout Constants

    private static let containerHeight: CGFloat = 160
    private static let labelFontScale: CGFloat = 0.8
    private static let selectedBorderWidth: CGFloat = 2
    private static let deselectedOpacity: Double = 0.35
    private static let selectedOpacity: Double = 1.0
    private static let paddingFraction: Double = 0.1
    private static let minimumScreenWidth: CGFloat = 40
    private static let minimumScreenHeight: CGFloat = 30
    private static let paddingMultiplier: Double = 2
    private static let deselectedBorderWidth: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let layout = computeLayout(in: geometry.size)
            ZStack {
                ForEach(screenInfos) { info in
                    screenRectangle(info: info, layout: layout)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: Self.containerHeight)
        .onAppear { refreshScreens() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification,
            ),
        ) { _ in
            refreshScreens()
        }
    }

    // MARK: - Screen Rectangle

    private func screenRectangle(info: ScreenInfo, layout: LayoutInfo) -> some View {
        let isSelected = preferences.selectedDisplayKeys.contains(info.identifier.persistenceKey)
        let rect = layout.rects[info.id] ?? .zero

        return Button {
            preferences.toggleDisplay(key: info.identifier.persistenceKey)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: design.corners.sm)
                    .fill(isSelected ? design.colors.accentSubtle : design.colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: design.corners.sm)
                            .stroke(
                                isSelected ? design.colors.accent : design.colors.borderSubtle,
                                lineWidth: isSelected
                                    ? Self.selectedBorderWidth : Self.deselectedBorderWidth,
                            ),
                    )

                VStack(spacing: design.spacing.xs) {
                    Text(info.identifier.localizedName)
                        .font(design.fonts.caption)
                        .foregroundColor(
                            isSelected ? design.colors.textPrimary : design.colors.textTertiary,
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(Self.labelFontScale)

                    if info.identifier.isBuiltIn {
                        Image(systemName: "laptopcomputer")
                            .font(design.fonts.caption)
                            .foregroundColor(design.colors.textTertiary)
                    }
                }
                .padding(design.spacing.xs)
            }
            .frame(
                width: max(rect.width, Self.minimumScreenWidth),
                height: max(rect.height, Self.minimumScreenHeight),
            )
            .opacity(isSelected ? Self.selectedOpacity : Self.deselectedOpacity)
            .animation(DesignAnimations.content, value: isSelected)
        }
        // swiftlint:disable:next no_plain_button_style
        .buttonStyle(.plain)
        .position(x: rect.midX, y: rect.midY)
        .accessibilityLabel(
            "\(info.identifier.localizedName), \(isSelected ? "selected" : "not selected")",
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Double-tap to toggle this display")
    }

    // MARK: - Layout Computation

    private struct LayoutInfo {
        let rects: [String: CGRect]
    }

    private func computeLayout(in containerSize: CGSize) -> LayoutInfo {
        guard !screenInfos.isEmpty else { return LayoutInfo(rects: [:]) }

        // Find the bounding box of all screens in macOS global coordinates
        let allFrames = screenInfos.map(\.frame)
        guard let boundsMinX = allFrames.map(\.minX).min(),
              let boundsMinY = allFrames.map(\.minY).min(),
              let boundsMaxX = allFrames.map(\.maxX).max(),
              let boundsMaxY = allFrames.map(\.maxY).max()
        else { return LayoutInfo(rects: [:]) }

        let totalWidth = boundsMaxX - boundsMinX
        let totalHeight = boundsMaxY - boundsMinY

        guard totalWidth > 0, totalHeight > 0 else { return LayoutInfo(rects: [:]) }

        // Inset the container to add padding
        let padding = min(containerSize.width, containerSize.height) * Self.paddingFraction
        let availableWidth = containerSize.width - padding * Self.paddingMultiplier
        let availableHeight = containerSize.height - padding * Self.paddingMultiplier

        // Scale to fit, preserving aspect ratio
        let scale = min(availableWidth / totalWidth, availableHeight / totalHeight)

        var rects: [String: CGRect] = [:]
        for info in screenInfos {
            let f = info.frame
            // Normalize origin relative to bounding box, apply scale, center in container.
            // Flip Y: macOS has Y-up, SwiftUI has Y-down.
            let x = padding + (f.minX - boundsMinX) * scale
            let y = padding + (boundsMaxY - f.maxY) * scale // Y-flip
            let w = f.width * scale
            let h = f.height * scale
            rects[info.id] = CGRect(x: x, y: y, width: w, height: h)
        }

        return LayoutInfo(rects: rects)
    }

    // MARK: - Screen Data

    private func refreshScreens() {
        screenInfos = NSScreen.screens.compactMap { screen in
            guard let id = DisplayIdentifier(screen: screen) else { return nil }
            return ScreenInfo(identifier: id, frame: screen.frame)
        }
    }
}

/// Snapshot of a connected screen for the arrangement view.
private struct ScreenInfo: Identifiable {
    let identifier: DisplayIdentifier
    let frame: CGRect

    var id: String {
        identifier.persistenceKey + "-" + identifier.localizedName
    }
}
