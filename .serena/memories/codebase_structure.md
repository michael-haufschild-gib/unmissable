# Codebase Structure

```
Sources/Unmissable/
├── App/                    # Main application lifecycle & Menu Bar UI
│   ├── AppDelegate.swift   # App lifecycle management
│   ├── AppState.swift      # Application state
│   ├── MenuBarView.swift   # Menu bar UI
│   └── UnmissableApp.swift # App entry point
│
├── Config/                 # Configuration & Secrets
│   └── Config.plist.example
│
├── Core/                   # Shared Services
│   ├── DatabaseManager.swift      # SQLite via GRDB
│   ├── DatabaseModels.swift       # Database model definitions
│   ├── EventScheduler.swift       # Event scheduling logic
│   ├── SyncManager.swift          # Calendar synchronization
│   ├── LinkParser.swift           # Meeting link extraction
│   ├── SoundManager.swift         # Audio alerts
│   ├── TimezoneManager.swift      # Timezone handling
│   ├── HealthMonitor.swift        # App health monitoring
│   ├── ProductionMonitor.swift    # Production metrics
│   ├── Protocols.swift            # Shared protocols
│   └── CustomComponents.swift     # Reusable UI components
│
├── Features/               # Isolated feature modules
│   ├── Overlay/            # Full-screen alert implementation
│   │   ├── OverlayManager.swift
│   │   ├── OverlayContentView.swift
│   │   ├── OverlayRenderer.swift
│   │   └── OverlayTrigger.swift
│   │
│   ├── CalendarConnect/    # Google Calendar integration
│   │   ├── CalendarService.swift
│   │   ├── GoogleCalendarAPIService.swift
│   │   └── OAuth2Service.swift
│   │
│   ├── Preferences/        # Settings UI
│   │   ├── PreferencesManager.swift
│   │   ├── PreferencesView.swift
│   │   └── PreferencesWindowManager.swift
│   │
│   ├── MeetingDetails/     # Meeting info display
│   ├── FocusMode/          # Focus mode feature
│   ├── Shortcuts/          # Global keyboard shortcuts
│   └── QuickJoin/          # Quick meeting join UI
│
├── Models/                 # Data structures
│   ├── Event.swift         # Event model
│   ├── Attendee.swift      # Meeting attendee
│   ├── Provider.swift      # Calendar provider
│   ├── ScheduledAlert.swift # Alert scheduling
│   ├── CalendarInfo.swift  # Calendar metadata
│   └── EventAttachment.swift
│
└── GoogleCalendarConfig.swift # OAuth configuration

Tests/
├── UnmissableTests/        # Unit and integration tests
├── IntegrationTests/       # Integration test suite
└── SnapshotTests/          # UI snapshot tests

Scripts/                    # Development utilities
├── build.sh               # Full build cycle
├── format.sh              # Code formatting
├── run-comprehensive-tests.sh # Complete test suite
└── cleanup-test-data.sh   # Reset test state
```