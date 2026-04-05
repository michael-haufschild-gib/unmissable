# Expand Meeting Service List to 20+

## Summary

Add support for detecting meeting links from additional video conferencing services. The current list covers 7 services (Google Meet, Zoom, Teams, WebEx, GoToMeeting, Whereby, Around). Competitors support 30-50+. Expanding to 20+ covers the long tail and eliminates "it doesn't detect my meetings" as a churn reason.

## Why This Matters

A user whose company uses Jitsi, BlueJeans, or Amazon Chime will find that Unmissable doesn't detect their meeting links and can't offer one-click join. They'll switch to MeetingBar (free, 50+ services) immediately. Meeting service breadth is a table-stakes feature — not a differentiator, but its absence is a disqualifier.

## Current State

### Trusted domains

`Sources/Unmissable/Core/LinkParser.swift:8-18` defines `trustedMeetingDomains`:

```swift
private static let trustedMeetingDomains = [
    "meet.google.com",
    "g.co",
    "zoom.us",
    "teams.microsoft.com",
    "teams.live.com",
    "webex.com",
    "gotomeeting.com",
    "whereby.com",
    "around.co",
]
```

### Custom URL schemes

`LinkParser.swift:98` defines `meetingURLSchemes`:

```swift
private static let meetingURLSchemes: Set<String> = ["zoommtg", "msteams", "webex"]
```

### Provider detection

`Sources/Unmissable/Models/Provider.swift` maps URLs to provider enum cases (`.meet`, `.zoom`, `.teams`, `.webex`, `.generic`). URLs from services not in this enum fall through to `.generic`, which uses a plain link icon.

### How detection works

`LinkParser.isMeetingURL(_:)` checks two things:
1. Is the URL's scheme in `meetingURLSchemes`? (for native app links like `zoommtg://`)
2. Is the URL's host in `trustedMeetingDomains`? (for HTTPS links)

`LinkParser.isValidMeetingURL(_:)` enforces HTTPS-only for domain-based detection (security measure — prevents `http://` phishing).

## Implementation Plan

### 1. Expand trusted domains

**File:** `Sources/Unmissable/Core/LinkParser.swift`

Add these domains to `trustedMeetingDomains`:

```swift
private static let trustedMeetingDomains = [
    // Existing
    "meet.google.com",
    "g.co",
    "zoom.us",
    "teams.microsoft.com",
    "teams.live.com",
    "webex.com",
    "gotomeeting.com",
    "whereby.com",
    "around.co",
    // New additions
    "meet.jit.si",              // Jitsi Meet
    "8x8.vc",                   // Jitsi (8x8 hosted)
    "bluejeans.com",            // BlueJeans
    "chime.aws",                // Amazon Chime
    "ringcentral.com",          // RingCentral
    "skype.com",                // Skype
    "join.skype.com",           // Skype join links
    "huddle.slack.com",         // Slack Huddles (via browser)
    "discord.gg",               // Discord
    "discord.com",              // Discord
    "livekit.io",               // LiveKit
    "daily.co",                 // Daily.co
    "cal.com",                  // Cal.com meeting links
    "gather.town",              // Gather
    "pop.com",                  // Pop (pair programming)
    "tuple.app",                // Tuple (pair programming)
    "jam.dev",                  // Jam (collaboration)
    "livestorm.co",             // Livestorm (webinars)
    "demio.com",                // Demio (webinars)
    "hopin.com",                // Hopin (events)
    "streamyard.com",           // StreamYard
    "vowel.com",                // Vowel
    "tandem.chat",              // Tandem
]
```

### 2. Expand custom URL schemes

**File:** `Sources/Unmissable/Core/LinkParser.swift`

```swift
private static let meetingURLSchemes: Set<String> = [
    "zoommtg",      // Zoom native
    "msteams",      // Microsoft Teams native
    "webex",        // WebEx native
    "callto",       // Skype
    "skype",        // Skype
    "discord",      // Discord native
    "slack",        // Slack native
    "ringcentral",  // RingCentral native
]
```

### 3. Expand Provider enum (optional)

**File:** `Sources/Unmissable/Models/Provider.swift`

Consider adding more specific provider cases for better icons and display names:

```swift
enum Provider: String, Codable, CaseIterable {
    case meet
    case zoom
    case teams
    case webex
    case jitsi
    case bluejeans
    case skype
    case slack
    case discord
    case ringcentral
    case generic
}
```

Each new case needs: `displayName`, `iconName`, `urlSchemes`, and a matching clause in `detect(from:)`.

**Trade-off:** More enum cases = more code to maintain, but better UX (correct provider name in meeting details popup). Alternative: keep only the top 5 providers with specific enum cases and route everything else to `.generic` with a "Video" label. The domain still gets detected; only the display name and icon differ.

**Recommendation:** Add specific enum cases only for the top 10 most common services. Everything else maps to `.generic`.

### 4. Update link priority in detectPrimaryLink

**File:** `Sources/Unmissable/Core/LinkParser.swift`

The `detectPrimaryLink(from:)` method (`LinkParser.swift:114-134`) currently prioritizes:
1. Google Meet
2. Zoom, Teams, WebEx (exact domain matching)
3. First valid link

This priority order is fine for the expanded list — new services will fall through to step 3 naturally. No change needed unless we want to prioritize specific new services.

## Services to Add (Priority Order)

| Priority | Service | Domain(s) | Scheme | Rationale |
|-|-|-|-|-|
| High | Jitsi Meet | meet.jit.si, 8x8.vc | - | Popular open-source, used by many companies |
| High | BlueJeans | bluejeans.com | - | Enterprise staple, Verizon-owned |
| High | Amazon Chime | chime.aws | - | AWS shops use this |
| High | RingCentral | ringcentral.com | ringcentral | Large enterprise presence |
| High | Skype | skype.com, join.skype.com | skype, callto | Still widely used |
| Medium | Slack Huddles | huddle.slack.com | slack | Common for quick calls |
| Medium | Discord | discord.gg, discord.com | discord | Gaming + dev communities |
| Medium | Daily.co | daily.co | - | Developer-focused |
| Medium | Gather | gather.town | - | Virtual office trend |
| Medium | LiveKit | livekit.io | - | Developer-focused |
| Low | Livestorm | livestorm.co | - | Webinar platform |
| Low | StreamYard | streamyard.com | - | Streaming/webinar |
| Low | Vowel | vowel.com | - | AI meeting platform |
| Low | Tuple | tuple.app | - | Pair programming |
| Low | Pop | pop.com | - | Screen sharing |

## Testing

- Unit test: `isMeetingURL` returns `true` for each new domain (add to `LinkParserTests.swift`)
- Unit test: `isValidMeetingURL` enforces HTTPS for new domains
- Unit test: new custom URL schemes are recognized
- Unit test: `Provider.detect(from:)` returns correct provider for new enum cases (if added)
- Parameterized test: expand `ProviderDetectionParameterizedTests.swift` with new URLs

## Estimated Scope

Small. The core change is adding strings to two arrays. Provider enum expansion and tests are the bulk of the work. Estimated: 1-2 hours including tests.
