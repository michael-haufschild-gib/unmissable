import Foundation
import OSLog

@MainActor
final class GoogleCalendarAPIService: ObservableObject, CalendarAPIProviding {
    private let logger = Logger(category: "GoogleCalendarAPIService")
    private let oauth2Service: OAuth2Service
    private let linkParser: LinkParser

    @Published
    var calendars: [CalendarInfo] = []
    @Published
    var events: [Event] = []
    @Published
    var lastError: String?
    @Published
    var calendarErrors: [String: String] = [:]

    /// URLSession with timeout configuration to prevent indefinite hangs.
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30 // 30 seconds per request
        config.timeoutIntervalForResource = 60 // 60 seconds total
        return URLSession(configuration: config)
    }()

    init(oauth2Service: OAuth2Service, linkParser: LinkParser) {
        self.oauth2Service = oauth2Service
        self.linkParser = linkParser
    }

    // MARK: - Calendar Operations

    @discardableResult
    func fetchCalendars() async -> [CalendarInfo] {
        logger.debug("Fetching calendar list")
        lastError = nil

        do {
            let accessToken = try await oauth2Service.getValidAccessToken()
            guard let url = URL(string: "\(GoogleCalendarConfig.calendarAPIBaseURL)/users/me/calendarList")
            else {
                lastError = GoogleCalendarAPIError.invalidURL.localizedDescription
                return calendars
            }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await Self.urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = GoogleCalendarAPIError.invalidResponse.localizedDescription
                return calendars
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = "HTTP \(httpResponse.statusCode)"
                if httpResponse.statusCode == 404 {
                    logger.error("Calendar list 404: \(url)")
                    if let errorBody = String(data: data, encoding: .utf8) {
                        logger.error("Response: \(errorBody)")
                    }
                }
                logger.error("Calendar list fetch failed: \(errorMessage)")
                lastError = GoogleCalendarAPIError.requestFailed(
                    httpResponse.statusCode, errorMessage
                ).localizedDescription
                return calendars
            }

            let calendarList = try parseCalendarList(from: data)
            calendars = calendarList

            logger.debug("Fetched \(calendarList.count) calendars")
        } catch {
            logger.error("Failed to fetch calendars: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }

        return calendars
    }

    @discardableResult
    func fetchEvents(for calendarIds: [String], from startDate: Date, to endDate: Date) async -> [Event] {
        logger.debug("Fetching events for \(calendarIds.count) calendars")
        lastError = nil
        calendarErrors = [:]

        var allEvents: [Event] = []
        var successfulCalendars = 0

        // Pre-fetch a valid access token before spawning concurrent tasks.
        // Each child task reuses this token, avoiding redundant token refreshes
        // and potential OAuth races from concurrent getValidAccessToken() calls.
        let prefetchedToken: String
        do {
            prefetchedToken = try await oauth2Service.getValidAccessToken()
        } catch {
            logger.error("Failed to get access token: \(error.localizedDescription)")
            lastError = error.localizedDescription
            return events
        }

        await withTaskGroup(of: (String, Result<[Event], Error>).self) { group in
            for calendarId in calendarIds {
                group.addTask {
                    do {
                        let calendarEvents = try await self.fetchEventsForCalendar(
                            calendarId: calendarId,
                            startDate: startDate,
                            endDate: endDate,
                            accessToken: prefetchedToken
                        )
                        return (calendarId, .success(calendarEvents))
                    } catch {
                        return (calendarId, .failure(error))
                    }
                }
            }

            for await (calendarId, result) in group {
                switch result {
                case let .success(calendarEvents):
                    allEvents.append(contentsOf: calendarEvents)
                    successfulCalendars += 1

                case let .failure(error):
                    calendarErrors[calendarId] = error.localizedDescription
                    logger.warning(
                        "Skipping calendar \(calendarId): \(error.localizedDescription)"
                    )
                }
            }
        }

        allEvents.sort { $0.startDate < $1.startDate }
        events = allEvents

        if !calendarErrors.isEmpty {
            let failedIds = calendarErrors.keys.sorted().joined(separator: ", ")
            lastError = "Failed to fetch \(calendarErrors.count) calendar(s): \(failedIds)"
        }

        logger.debug(
            "Fetched \(allEvents.count) events from \(successfulCalendars)/\(calendarIds.count) calendars"
        )

        return events
    }

    // MARK: - Private Methods

    /// Characters allowed in percent-encoded calendar IDs.
    /// Based on `.urlPathAllowed` with `#` explicitly removed — calendar IDs like
    /// `#contacts@group.v.calendar.google.com` must have `#` encoded to `%23`
    /// so it isn't misinterpreted as a URL fragment delimiter.
    private nonisolated static let calendarIdAllowedCharacters: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove("#")
        return set
    }()

    /// Fetches events for a single calendar, handling pagination. Marked `nonisolated` so that
    /// concurrent task group children can execute HTTP requests off the main actor.
    private nonisolated func fetchEventsForCalendar(
        calendarId: String,
        startDate: Date,
        endDate: Date,
        accessToken: String
    ) async throws -> [Event] {
        let maxEvents = 2000
        let dateFormatter = ISO8601DateFormatter()
        let timeMin = dateFormatter.string(from: startDate)
        let timeMax = dateFormatter.string(from: endDate)

        let encodedCalendarId =
            calendarId.addingPercentEncoding(withAllowedCharacters: Self.calendarIdAllowedCharacters)
                ?? calendarId

        var allEvents: [Event] = []
        var pageToken: String?

        repeat {
            guard var urlComponents = URLComponents(
                string: "\(GoogleCalendarConfig.calendarAPIBaseURL)/calendars/\(encodedCalendarId)/events"
            ) else {
                throw GoogleCalendarAPIError.invalidURL
            }
            var queryItems = [
                URLQueryItem(name: "timeMin", value: timeMin),
                URLQueryItem(name: "timeMax", value: timeMax),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "250"),
                URLQueryItem(name: "maxAttendees", value: "100"),
                URLQueryItem(
                    name: "fields",
                    value: [
                        "items(id,summary,start,end,organizer,description,",
                        "location,attendees,attachments,hangoutLink,",
                        "conferenceData,status),nextPageToken",
                    ].joined()
                ),
            ]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            urlComponents.queryItems = queryItems

            guard let url = urlComponents.url else {
                throw GoogleCalendarAPIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await Self.urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleCalendarAPIError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 404 {
                    logger.warning("Calendar \(calendarId) not found or not accessible, skipping")
                    return []
                }
                if httpResponse.statusCode == 403 {
                    logger.warning("Access denied to calendar \(calendarId), skipping")
                    return []
                }
                let errorMessage = "HTTP \(httpResponse.statusCode)"
                logger.error("Events fetch failed for calendar \(calendarId): \(errorMessage)")
                throw GoogleCalendarAPIError.requestFailed(httpResponse.statusCode, errorMessage)
            }

            let (events, nextToken) = try parseEventList(from: data, calendarId: calendarId)
            allEvents.append(contentsOf: events)
            pageToken = nextToken

            if allEvents.count >= maxEvents {
                logger.warning(
                    "Hit safety cap of \(maxEvents) events for calendar \(calendarId), stopping pagination"
                )
                break
            }
        } while pageToken != nil

        return allEvents
    }

    private func parseCalendarList(from data: Data) throws -> [CalendarInfo] {
        let response = try JSONDecoder().decode(GCalCalendarListResponse.self, from: data)
        guard let items = response.items else {
            throw GoogleCalendarAPIError.parseError
        }

        return items.compactMap { entry in
            guard let summary = entry.summary else { return nil }
            let isPrimary = entry.primary ?? false

            return CalendarInfo(
                id: entry.id,
                name: summary,
                description: entry.description,
                isSelected: isPrimary,
                isPrimary: isPrimary,
                colorHex: entry.colorHex
            )
        }
    }

    private nonisolated func parseEventList(from data: Data, calendarId: String) throws
        -> ([Event], String?)
    {
        let response = try JSONDecoder().decode(GCalEventListResponse.self, from: data)
        guard let items = response.items else {
            throw GoogleCalendarAPIError.parseError
        }

        let events = items.compactMap { entry in
            convertToEvent(from: entry, calendarId: calendarId)
        }

        return (events, response.nextPageToken)
    }

    // MARK: - Codable Event Conversion

    /// Creates a new ISO8601DateFormatter per call. These formatters are not thread-safe,
    /// so sharing a static instance across concurrent task group children is unsound.
    /// ISO8601DateFormatter is lightweight — allocation cost is negligible vs. network I/O.
    private nonisolated static func makeISOFormatter() -> ISO8601DateFormatter {
        ISO8601DateFormatter()
    }

    private nonisolated static func makeDayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// Truncates a string to a maximum length. Defense-in-depth against oversized API responses.
    private nonisolated static func truncate(_ string: String?, maxLength: Int) -> String? {
        guard let string, string.count > maxLength else { return string }
        return String(string.prefix(maxLength))
    }

    nonisolated func convertToEvent(from entry: GCalEventEntry, calendarId: String) -> Event? {
        guard let id = entry.id,
              let summary = entry.summary,
              let start = entry.start,
              let end = entry.end
        else {
            return nil
        }

        if entry.status == "cancelled" { return nil }

        // Parse dates
        guard let (startDate, isAllDay) = parseDate(from: start),
              let (endDate, _) = parseDate(from: end)
        else {
            return nil
        }

        // Convert attendees
        let attendees = (entry.attendees ?? []).compactMap { attendee -> Attendee? in
            guard let email = attendee.email else { return nil }
            return Attendee(
                name: attendee.displayName,
                email: email,
                status: AttendeeStatus(rawValue: attendee.responseStatus ?? "needsAction"),
                isOptional: attendee.isOptional ?? false,
                isOrganizer: attendee.isOrganizer ?? false,
                isSelf: attendee.isSelf ?? false
            )
        }

        // Filter declined
        if let selfAttendee = attendees.first(where: \.isSelf),
           selfAttendee.status == .declined
        {
            return nil
        }

        // Convert attachments
        let attachments = (entry.attachments ?? []).compactMap { attachment -> EventAttachment? in
            guard let fileUrl = attachment.fileUrl,
                  let title = attachment.title,
                  let mimeType = attachment.mimeType
            else { return nil }
            return EventAttachment(
                fileUrl: fileUrl,
                title: title,
                mimeType: mimeType,
                iconLink: attachment.iconLink,
                fileId: attachment.fileId
            )
        }

        // Extract meeting links
        let links = extractMeetingLinks(from: entry)
        let provider = links.first.map { Provider.detect(from: $0) }
        let timezone = start.timeZone ?? TimeZone.current.identifier

        // Truncate API response fields to defend against oversized payloads
        let truncatedTitle = Self.truncate(summary, maxLength: 500) ?? summary
        let truncatedDescription = Self.truncate(entry.description, maxLength: 10_000)
        let truncatedLocation = Self.truncate(entry.location, maxLength: 1000)
        let truncatedOrganizer = Self.truncate(entry.organizer?.email, maxLength: 320)

        return Event(
            id: id,
            title: truncatedTitle,
            startDate: startDate,
            endDate: endDate,
            organizer: truncatedOrganizer,
            description: truncatedDescription,
            location: truncatedLocation,
            attendees: attendees,
            attachments: attachments,
            isAllDay: isAllDay,
            calendarId: calendarId,
            timezone: timezone,
            links: links,
            provider: provider
        )
    }

    private nonisolated func parseDate(from dt: GCalDateTime) -> (Date, Bool)? {
        if let dateTimeString = dt.dateTime,
           let date = Self.makeISOFormatter().date(from: dateTimeString)
        {
            return (date, false)
        }
        if let dateString = dt.date,
           let date = Self.makeDayFormatter().date(from: dateString)
        {
            return (date, true)
        }
        return nil
    }

    private nonisolated func extractMeetingLinks(from entry: GCalEventEntry) -> [URL] {
        var links: [URL] = []

        // hangoutLink is the legacy Google Meet link — always meeting-relevant
        if let hangoutLink = entry.hangoutLink, let url = URL(string: hangoutLink) {
            links.append(url)
        }

        // conferenceData entryPoints come from Google's meeting infrastructure — always relevant
        if let entryPoints = entry.conferenceData?.entryPoints {
            for ep in entryPoints {
                if let uri = ep.uri, let url = URL(string: uri) {
                    links.append(url)
                }
            }
        }

        // Location and description may contain non-meeting URLs (e.g., docs, agendas).
        // Filter to only meeting-relevant URLs using LinkParser's centralized detection.
        if let location = entry.location {
            let locationURLs = extractURLs(from: location)
            links.append(contentsOf: locationURLs.filter { linkParser.isMeetingURL($0) })
        }

        if let description = entry.description {
            let descriptionURLs = extractURLs(from: description)
            links.append(contentsOf: descriptionURLs.filter { linkParser.isMeetingURL($0) })
        }

        // Stable dedup preserving order
        var seen = Set<String>()
        return links.filter { seen.insert($0.absoluteString.lowercased()).inserted }
    }

    private nonisolated func extractURLs(from text: String) -> [URL] {
        linkParser.extractURLs(from: text)
    }
}

enum GoogleCalendarAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case requestFailed(Int, String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid URL"
        case .invalidResponse:
            "Invalid response"
        case let .requestFailed(code, message):
            "Request failed with code \(code): \(message)"
        case .parseError:
            "Failed to parse response"
        }
    }
}
