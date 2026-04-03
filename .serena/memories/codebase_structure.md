# Codebase Structure

```
Sources/Unmissable/
├── App/
│   ├── AppDelegate.swift          # App lifecycle management
│   ├── AppState.swift             # Application state coordinator
│   ├── MenuBarView.swift          # Menu bar UI
│   ├── ServiceContainer.swift     # DI container for all services
│   └── UnmissableApp.swift        # App entry point (@main)
│
├── Config/
│   └── GoogleCalendarConfig.swift # OAuth config loading from Config.plist
│
├── Core/
│   ├── Containers.swift           # UI containers: UMSection, .umCard(), .umGlass(), .umPickerStyle()
│   ├── ContinuationCoordinator.swift # Exactly-once continuation resumption
│   ├── DatabaseManager.swift      # SQLite via GRDB (actor)
│   ├── DatabaseManager+Extensions.swift # Search, maintenance, test helpers
│   ├── DatabaseModels.swift       # GRDB record conformances
│   ├── DesignTokens.swift         # Design system: ThemeManager, DesignColors/Fonts/Spacing/Corners/Shadows
│   ├── EventScheduler.swift       # Event scheduling logic
│   ├── HealthMonitor.swift        # App health monitoring
│   ├── HTMLSanitizer.swift        # XSS-safe HTML sanitization
│   ├── LinkParser.swift           # Meeting link extraction & validation
│   ├── LoggerSubsystem.swift      # Logger subsystem constant
│   ├── MenuBarPreviewManager.swift # Menu bar timer display
│   ├── NotificationNames.swift    # Centralized notification constants
│   ├── Protocols.swift            # DI protocols (OverlayManaging, CalendarAPIProviding, etc.)
│   ├── SoundManager.swift         # Audio alerts
│   ├── Styles.swift               # UI components: UMButtonStyle, UMToggleStyle, UMStatusIndicator, UMBadge
│   ├── SyncManager.swift          # Calendar synchronization
│   └── UpdateManager.swift        # Sparkle auto-updates
│
├── Features/
│   ├── CalendarConnect/           # Calendar integration
│   │   ├── AppleCalendarAPIService.swift  # EventKit data fetching
│   │   ├── AppleCalendarAuthService.swift # EventKit permissions
│   │   ├── CalendarService.swift          # Multi-provider orchestrator
│   │   ├── GoogleCalendarAPIService.swift # Google Calendar API
│   │   ├── GoogleCalendarModels.swift     # API response Codable models
│   │   └── OAuth2Service.swift            # Google OAuth 2.0
│   │
│   ├── FocusMode/
│   │   └── FocusModeManager.swift         # macOS Focus/DND detection
│   │
│   ├── MeetingDetails/
│   │   ├── AttachmentsView.swift          # Meeting attachment list
│   │   ├── HTMLTextView.swift             # AppKit-based HTML renderer
│   │   ├── MeetingDetailsPopupManager.swift # Popup lifecycle
│   │   └── MeetingDetailsView.swift       # Meeting info panel
│   │
│   ├── Overlay/
│   │   ├── OverlayContentView.swift       # Full-screen alert SwiftUI content
│   │   └── OverlayManager.swift           # Overlay window lifecycle (AppKit)
│   │
│   ├── Preferences/
│   │   ├── AppearancePreferencesView.swift # Theme/appearance settings
│   │   ├── CalendarPreferencesView.swift   # Calendar connection settings
│   │   ├── PreferencesManager.swift        # User defaults persistence
│   │   ├── PreferencesView.swift           # Settings tab container
│   │   └── PreferencesWindowManager.swift  # Settings window lifecycle
│   │
│   └── Shortcuts/
│       └── ShortcutsManager.swift         # Global keyboard shortcuts (Magnet)
│
├── Models/
│   ├── Attendee.swift
│   ├── CalendarInfo.swift
│   ├── CalendarProviderType.swift
│   ├── Event.swift                # Primary data model
│   ├── EventAttachment.swift
│   ├── Provider.swift             # Meeting service providers (Zoom, Meet, Teams, etc.)
│   ├── ScheduledAlert.swift
│   └── SyncStatus.swift
│
└── Resources/                     # Assets

Tests/
├── TestSupport/                   # Shared test doubles (TestSupport target)
├── UnmissableTests/               # Unit tests
├── IntegrationTests/              # Integration tests
├── E2ETests/                      # End-to-end tests
├── SnapshotTests/                 # UI snapshot tests
│   └── __Snapshots__/             # Reference images

Scripts/
├── build.sh                       # Full build + lint + test cycle
├── format.sh                      # SwiftFormat runner
├── test.sh                        # Test runner (4-worker limit)
├── run-comprehensive-tests.sh     # Complete test suite with reports
└── cleanup-test-data.sh           # Reset test state
```