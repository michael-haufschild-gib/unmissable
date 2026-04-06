import SwiftUI

// MARK: - Onboarding Screen Enum

/// The three screens in the first-launch onboarding flow.
@MainActor
enum OnboardingScreen: Int, CaseIterable {
    case welcome
    case connectCalendar
    case allSet
}

// MARK: - OnboardingView

/// A 3-screen first-launch experience: Welcome → Connect Calendar → You're All Set.
///
/// Presented in a standalone 500×600 window by ``OnboardingWindowManager``.
/// All actions flow through ``AppState`` to maintain the single-source-of-truth pattern.
struct OnboardingView: View {
    @Environment(AppState.self)
    private var appState
    @Environment(CalendarService.self)
    private var calendarService
    @Environment(\.design)
    private var design

    @State
    private var currentScreen: OnboardingScreen = .welcome
    @State
    private var connectingProvider: CalendarProviderType?

    var body: some View {
        ZStack {
            design.colors.background
                .ignoresSafeArea()

            Group {
                switch currentScreen {
                case .welcome:
                    welcomeScreen

                case .connectCalendar:
                    connectCalendarScreen

                case .allSet:
                    allSetScreen
                }
            }
            .animation(DesignAnimations.content, value: currentScreen)
        }
    }
}

// MARK: - Screen 1: Welcome

private extension OnboardingView {
    var welcomeScreen: some View {
        VStack(spacing: design.spacing.lg) {
            Spacer()

            Image(systemName: "bell.badge.circle.fill")
                .font(design.fonts.heroIcon)
                .foregroundStyle(design.colors.accent)
                .padding(.bottom, design.spacing.sm)

            Text("Welcome to Unmissable")
                .font(design.fonts.title1)
                .foregroundColor(design.colors.textPrimary)

            Text("Full-screen reminders you can't ignore.")
                .font(design.fonts.body)
                .foregroundColor(design.colors.textSecondary)
                .padding(.bottom, design.spacing.md)

            VStack(alignment: .leading, spacing: design.spacing.md) {
                featureBullet(
                    icon: "rectangle.inset.filled",
                    text: "Full-screen overlay before every meeting",
                )
                featureBullet(
                    icon: "link.circle.fill",
                    text: "One-click join for Zoom, Meet, Teams, and more",
                )
                featureBullet(
                    icon: "calendar.badge.checkmark",
                    text: "Works with Google Calendar and Apple Calendar",
                )
            }
            .padding(.horizontal, design.spacing.xxl)

            Spacer()

            Button("Continue") {
                currentScreen = .connectCalendar
            }
            .buttonStyle(UMButtonStyle(.primary, size: .lg))
            .accessibilityIdentifier("onboarding-continue-button")
            .padding(.bottom, design.spacing.xxl)
        }
        .padding(design.spacing.xxl)
    }

    func featureBullet(icon: String, text: String) -> some View {
        HStack(spacing: design.spacing.md) {
            Image(systemName: icon)
                .font(design.fonts.title3)
                .foregroundColor(design.colors.accent)
                .frame(width: Metrics.bulletIconWidth)

            Text(text)
                .font(design.fonts.body)
                .foregroundColor(design.colors.textPrimary)
        }
    }
}

// MARK: - Screen 2: Connect Calendar

private extension OnboardingView {
    var connectCalendarScreen: some View {
        VStack(spacing: design.spacing.lg) {
            Spacer()

            Image(systemName: "calendar.circle.fill")
                .font(design.fonts.heroIcon)
                .foregroundStyle(design.colors.accent)
                .padding(.bottom, design.spacing.sm)

            Text("Connect Your Calendar")
                .font(design.fonts.title1)
                .foregroundColor(design.colors.textPrimary)

            Text("Choose how you'd like to sync your meetings.")
                .font(design.fonts.body)
                .foregroundColor(design.colors.textSecondary)
                .padding(.bottom, design.spacing.md)

            VStack(spacing: design.spacing.md) {
                calendarProviderButton(
                    provider: .apple,
                    description: "Uses calendars from iCloud, Outlook, Exchange, and more.",
                    isRecommended: true,
                )

                calendarProviderButton(
                    provider: .google,
                    description: "Direct connection to your Google account.",
                    isRecommended: false,
                )
            }
            .padding(.horizontal, design.spacing.lg)
            .disabled(connectingProvider != nil)

            Spacer()

            if calendarService.isConnected {
                Button("Continue") {
                    currentScreen = .allSet
                }
                .buttonStyle(UMButtonStyle(.primary, size: .lg))
                .accessibilityIdentifier("onboarding-continue-connected-button")
                .padding(.bottom, design.spacing.xxl)
            } else {
                Button("Skip for now") {
                    currentScreen = .allSet
                }
                .buttonStyle(UMButtonStyle(.ghost))
                .accessibilityIdentifier("onboarding-skip-button")
                .disabled(connectingProvider != nil)
                .padding(.bottom, design.spacing.xxl)
            }
        }
        .padding(design.spacing.xxl)
    }

    func isProviderConnected(_ provider: CalendarProviderType) -> Bool {
        calendarService.connectedProviders.contains(provider)
    }

    func calendarProviderButton(
        provider: CalendarProviderType,
        description: String,
        isRecommended: Bool,
    ) -> some View {
        Button {
            if !isProviderConnected(provider) {
                connectCalendar(provider: provider)
            }
        } label: {
            HStack(spacing: design.spacing.md) {
                Image(systemName: provider.iconName)
                    .font(design.fonts.title2)
                    .foregroundColor(isProviderConnected(provider) ? design.colors.success : design.colors.accent)
                    .frame(width: Metrics.providerIconWidth)

                VStack(alignment: .leading, spacing: design.spacing.xs) {
                    HStack(spacing: design.spacing.sm) {
                        Text(provider.connectionLabel)
                            .font(design.fonts.headline)
                            .foregroundColor(design.colors.textPrimary)

                        if isProviderConnected(provider) {
                            UMBadge("Connected", variant: .success)
                        } else if isRecommended {
                            UMBadge("Recommended", variant: .accent)
                        }
                    }

                    Text(description)
                        .font(design.fonts.footnote)
                        .foregroundColor(design.colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                if connectingProvider == provider {
                    ProgressView()
                        .controlSize(.small)
                } else if isProviderConnected(provider) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(design.colors.success)
                }
            }
            .padding(design.spacing.md)
            .background(design.colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: design.corners.md))
            .overlay(
                RoundedRectangle(cornerRadius: design.corners.md)
                    .stroke(
                        isProviderConnected(provider) ? design.colors.success : design.colors.borderSubtle,
                        lineWidth: Metrics.borderWidth,
                    ),
            )
        }
        .buttonStyle(UMButtonStyle(.ghost))
        .disabled(isProviderConnected(provider))
    }

    func connectCalendar(provider: CalendarProviderType) {
        connectingProvider = provider
        Task {
            await appState.connectToCalendar(provider: provider)
            connectingProvider = nil
            if calendarService.isConnected {
                currentScreen = .allSet
            }
        }
    }
}

// MARK: - Screen 3: You're All Set

private extension OnboardingView {
    var allSetScreen: some View {
        VStack(spacing: design.spacing.lg) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(design.fonts.heroIcon)
                .foregroundStyle(design.colors.success)
                .padding(.bottom, design.spacing.sm)

            Text("You're All Set!")
                .font(design.fonts.title1)
                .foregroundColor(design.colors.textPrimary)

            Text("Unmissable is running in your menu bar.")
                .font(design.fonts.body)
                .foregroundColor(design.colors.textSecondary)

            Text("Your next meeting will trigger a full-screen reminder.")
                .font(design.fonts.callout)
                .foregroundColor(design.colors.textTertiary)
                .padding(.bottom, design.spacing.md)

            Spacer()

            VStack(spacing: design.spacing.md) {
                Button("Show me how it looks") {
                    appState.showDemoOverlay()
                }
                .buttonStyle(UMButtonStyle(.secondary, size: .lg))
                .accessibilityIdentifier("onboarding-demo-button")

                Button("Done") {
                    appState.completeOnboarding()
                }
                .buttonStyle(UMButtonStyle(.primary, size: .lg))
                .accessibilityIdentifier("onboarding-done-button")
            }
            .padding(.bottom, design.spacing.xxl)
        }
        .padding(design.spacing.xxl)
    }
}

// MARK: - Metrics

private extension OnboardingView {
    enum Metrics {
        static let bulletIconWidth: CGFloat = 28
        static let providerIconWidth: CGFloat = 36
        static let borderWidth: CGFloat = 1
    }
}
