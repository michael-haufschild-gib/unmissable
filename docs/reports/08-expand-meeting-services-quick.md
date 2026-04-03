# Expand Meeting Services (Quick Implementation)

## Summary

This is a condensed, action-oriented version of the full meeting services report (`04-expand-meeting-services.md`). The goal: add 13+ services to get from 7 to 20+ in a single focused session.

## Why This Matters

MeetingBar supports 50+. In Your Face supports 30+. Unmissable supports 7. Users of Jitsi, BlueJeans, Amazon Chime, RingCentral, or Skype will find the app doesn't detect their meetings.

## What to Change

### File 1: `Sources/Unmissable/Core/LinkParser.swift`

Replace `trustedMeetingDomains` (line 8-18) with expanded list:

```swift
private static let trustedMeetingDomains = [
    // Major providers (existing)
    "meet.google.com",
    "g.co",
    "zoom.us",
    "teams.microsoft.com",
    "teams.live.com",
    "webex.com",
    "gotomeeting.com",
    "whereby.com",
    "around.co",
    // Tier 2: Enterprise & popular
    "meet.jit.si",
    "8x8.vc",
    "bluejeans.com",
    "chime.aws",
    "ringcentral.com",
    "skype.com",
    "join.skype.com",
    // Tier 3: Collaboration & dev tools
    "discord.gg",
    "discord.com",
    "daily.co",
    "gather.town",
    "livestorm.co",
    "vowel.com",
    "pop.com",
    "tuple.app",
    "demio.com",
    "hopin.com",
    "streamyard.com",
    "tandem.chat",
]
```

Replace `meetingURLSchemes` (line 98) with expanded list:

```swift
private static let meetingURLSchemes: Set<String> = [
    "zoommtg", "msteams", "webex",
    "callto", "skype",
    "discord",
    "ringcentral",
]
```

### File 2: `Tests/UnmissableTests/LinkParserTests.swift`

Add test cases for each new domain:

```swift
func testNewServiceDomains() {
    let newDomains = [
        "https://meet.jit.si/MyRoom",
        "https://8x8.vc/company/meeting",
        "https://bluejeans.com/123456",
        "https://chime.aws/123456",
        "https://app.ringcentral.com/join/123",
        "https://join.skype.com/abc123",
        "https://discord.gg/invite123",
        "https://daily.co/myroom",
        "https://gather.town/app/room",
    ]
    for urlString in newDomains {
        let url = URL(string: urlString)!
        XCTAssertTrue(
            linkParser.isMeetingURL(url),
            "Expected \(urlString) to be detected as meeting URL"
        )
    }
}

func testNewServiceDomainsRequireHTTPS() {
    let httpDomains = [
        "http://meet.jit.si/MyRoom",
        "http://bluejeans.com/123",
    ]
    for urlString in httpDomains {
        let url = URL(string: urlString)!
        XCTAssertFalse(
            linkParser.isValidMeetingURL(url),
            "Expected \(urlString) to fail HTTPS validation"
        )
    }
}

func testNewURLSchemes() {
    let schemes = [
        "callto://+1234567890",
        "skype://user?call",
        "discord://channels/123/456",
        "ringcentral://meeting/123",
    ]
    for urlString in schemes {
        let url = URL(string: urlString)!
        XCTAssertTrue(
            linkParser.isMeetingURL(url),
            "Expected \(urlString) scheme to be detected as meeting URL"
        )
    }
}
```

### File 3: `Tests/UnmissableTests/ProviderDetectionParameterizedTests.swift`

Add parameterized test entries for new domains that map to `.generic` (or to new Provider enum cases if you expand the enum — see `04-expand-meeting-services.md` for that optional step).

## What NOT to Change

- **Provider enum** — don't expand it in this quick pass. New services will correctly map to `.generic` via `Provider.detect(from:)`, showing as "Other" with a link icon. That's acceptable. Expanding the enum is a separate enhancement.
- **Link priority** — `detectPrimaryLink` already handles new domains correctly (they fall through to `validLinks.first`). No change needed.

## Verification

After making changes, run:
```bash
swift test --filter LinkParserTests
swift test --filter ProviderDetectionParameterizedTests
swift test --filter ProviderTests
```

## Estimated Time

30-60 minutes including tests.
