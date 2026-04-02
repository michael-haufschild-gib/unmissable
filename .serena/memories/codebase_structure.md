# Codebase Structure

```
Sources/Unmissable/
├── App/                    # Main application lifecycle & Menu Bar UI
│   ├── AppDelegate.swift   # App lifecycle management
│   ├── AppState.swift      # Application state
│   ├── MenuBarView.swift   # Menu bar UI
│   ├── ServiceContainer.swift # DI container for all services
│   └── UnmissableApp.swift # App entry point
│
├── Config/                 # Configuration & Secrets
│   └── GoogleCalendarConfig.swift # OAuth config loading
│
├── Core/                   # Shared Services
│   ├── ContinuationCoordinator.swift # Exactly-once continuation resumption
│   ├── CustomComponents.swift     # Reusable UI components (buttons, toggles)
│   ├── CustomContainers.swift     # Card and picker containers
│   ├── CustomThemeManager.swift   # Theme management
│   ├── DatabaseManager.swift      # SQLite via GRDB (actor)
│   ├── DatabaseManager+Extensions.swift # Search, maintenance, test helpers
│   ├── DatabaseModels.swift       # GRDB record conformances
│   ├── EventScheduler.swift       # Event scheduling logic
│   ├── HealthMonitor.swift        # App health monitoring
│   ├── HTMLSanitizer.swift        # XSS-safe HTML sanitization
│   ├── LinkParser.swift           # Meeting link extraction & validation
│   ├── MenuBarPreviewManager.swift # Menu bar timer display
│   ├── NotificationNames.swift    # Centralized notification constants
│   ├── Protocols.swift            # DI protocols (OverlayManaging, etc.)
│   ├── SoundManager.swift         # Audio alerts
│   ├── SyncManager.swift          # Calendar synchronization
│   └── UpdateManager.swift        # Sparkle auto-updates
│
├── Features/               # Isolated feature modules
│   ├── CalendarConnect/    # Calendar integration
│   │   ├── AppleCalendarAPIService.swift  # EventKit data fetching
│   │   ├── AppleCalendarAuthService.swift # EventKit permissions
│   │   ├── CalendarService.swift          # Multi-provider orchestrator
│   │   ├── GoogleCalendarAPIService.swift # Google Calendar API
│   │   ├── GoogleCalendarModels.swift     # API response Codable models
│   │   └── OAuth2Service.swift            # Google OAuth 2.0
│   │
│   ├── FocusMode/          # Focus/DND detection
│   │   └── FocusModeManager.swift
│   │
│   ├── MeetingDetails/     # Meeting info popup
│   │   ├── AttachmentsView.swift
│   │   ├── HTMLTextView.swift
│   │   ├── MeetingDetailsPopupManager.swift
│   │   └── MeetingDetailsView.swift
│   │
│   ├── Overlay/            # Full-screen alert
│   │   ├── OverlayContentView.swift
│   │   └── OverlayManager.swift
│   │
│   ├── Preferences/        # Settings UI
│   │   ├── AppearancePreferencesView.swift
│   │   ├── CalendarPreferencesView.swift
│   │   ├── PreferencesManager.swift
│   │   ├── PreferencesView.swift
│   │   └── PreferencesWindowManager.swift
│   │
│   └── Shortcuts/          # Global keyboard shortcuts
│       └── ShortcutsManager.swift
│
├── Models/                 # Data structures
│   ├── Attendee.swift
│   ├── CalendarInfo.swift
│   ├── CalendarProviderType.swift
│   ├── Event.swift
│   ├── EventAttachment.swift
│   ├── Provider.swift
│   ├── ScheduledAlert.swift
│   └── SyncStatus.swift
│
└── Resources/              # Assets

Tests/
├── UnmissableTests/        # Unit tests
├── IntegrationTests/       # Integration tests
├── SnapshotTests/          # UI snapshot tests
├── E2ETests/               # End-to-end tests
└── TestSupport/            # Shared test doubles

Scripts/                    # Development utilities
├── build.sh               # Full build cycle
├── format.sh              # Code formatting
├── run-comprehensive-tests.sh # Complete test suite
└── cleanup-test-data.sh   # Reset test state
```