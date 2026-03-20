import Foundation
import OSLog

@MainActor
final class GoogleCalendarAPIService: ObservableObject {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "GoogleCalendarAPIService")
    private let oauth2Service: OAuth2Service

    @Published
    var calendars: [CalendarInfo] = []
    @Published
    var events: [Event] = []
    @Published
    var isLoading = false
    @Published
    var lastError: String?

    /// URLSession with timeout configuration to prevent indefinite hangs
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30 // 30 seconds per request
        config.timeoutIntervalForResource = 60 // 60 seconds total
        return URLSession(configuration: config)
    }()

    init(oauth2Service: OAuth2Service) {
        self.oauth2Service = oauth2Service
    }

    // MARK: - Calendar Operations

    func fetchCalendars() async throws {
        logger.info("Fetching calendar list")
        isLoading = true
        lastError = nil

        defer { isLoading = false }

        do {
            let accessToken = try await oauth2Service.getValidAccessToken()
            guard let url = URL(string: "\(GoogleCalendarConfig.calendarAPIBaseURL)/users/me/calendarList")
            else {
                throw GoogleCalendarAPIError.invalidURL
            }

            logger.info("Making request to: \(url.absoluteString)")

            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            // Log that we have a valid token (without exposing token content)
            logger.info("Using valid access token for calendar request")

            let (data, response) = try await Self.urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleCalendarAPIError.invalidResponse
            }

            logger.info("Response status code: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                let errorMessage = "HTTP \(httpResponse.statusCode)"
                if httpResponse.statusCode == 404 {
                    logger.error(
                        "Calendar list fetch failed: 404 - Check API is enabled and correct endpoint"
                    )
                    logger.error("Request URL: \(url)")
                    // Try to get error details from response body
                    if let errorBody = String(data: data, encoding: .utf8) {
                        logger.error("Error response body: \(errorBody)")
                    }
                }
                logger.error("Calendar list fetch failed: \(errorMessage)")
                throw GoogleCalendarAPIError.requestFailed(httpResponse.statusCode, errorMessage)
            }

            let calendarList = try parseCalendarList(from: data)
            calendars = calendarList

            logger.info("Successfully fetched \(calendarList.count) calendars")
        } catch {
            logger.error("Failed to fetch calendars: \(error.localizedDescription)")
            lastError = error.localizedDescription
            throw error
        }
    }

    func fetchEvents(for calendarIds: [String], from startDate: Date, to endDate: Date) async {
        logger.info("Fetching events for \(calendarIds.count) calendars")
        isLoading = true
        lastError = nil

        defer { isLoading = false }

        var allEvents: [Event] = []
        var successfulCalendars = 0
        var skippedCalendars = 0

        for calendarId in calendarIds {
            do {
                let calendarEvents = try await fetchEventsForCalendar(
                    calendarId: calendarId,
                    startDate: startDate,
                    endDate: endDate
                )
                allEvents.append(contentsOf: calendarEvents)
                successfulCalendars += 1
                logger.info(
                    "Successfully fetched \(calendarEvents.count) events from calendar \(calendarId)"
                )
            } catch {
                skippedCalendars += 1
                lastError = error.localizedDescription
                logger.warning(
                    "Skipping calendar \(calendarId) due to error: \(error.localizedDescription)"
                )
                // Continue with other calendars instead of failing completely
            }
        }

        // Sort events by start date
        allEvents.sort { $0.startDate < $1.startDate }
        events = allEvents

        // Clear error if at least one calendar succeeded (partial success is not a total failure)
        if successfulCalendars > 0 {
            lastError = nil
        }

        logger.info(
            "Successfully fetched \(allEvents.count) events from \(successfulCalendars) calendars (\(skippedCalendars) skipped)"
        )
    }

    // MARK: - Private Methods

    private func fetchEventsForCalendar(calendarId: String, startDate: Date, endDate: Date)
        async throws -> [Event]
    {
        let accessToken = try await oauth2Service.getValidAccessToken()

        let dateFormatter = ISO8601DateFormatter()
        let timeMin = dateFormatter.string(from: startDate)
        let timeMax = dateFormatter.string(from: endDate)

        let encodedCalendarId =
            calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId

        guard var urlComponents = URLComponents(
            string: "\(GoogleCalendarConfig.calendarAPIBaseURL)/calendars/\(encodedCalendarId)/events"
        ) else {
            throw GoogleCalendarAPIError.invalidURL
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "250"),
            // CRITICAL: maxAttendees required to get attendee list (defaults to truncation without this)
            URLQueryItem(name: "maxAttendees", value: "100"),
            // Request comprehensive event fields including description, attendees, attachments, and status
            URLQueryItem(
                name: "fields",
                value: [
                    "items(id,summary,start,end,organizer,description,",
                    "location,attendees,attachments,hangoutLink,",
                    "conferenceData,status),nextPageToken",
                ].joined()
            ),
        ]

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

        let (events, _) = try parseEventList(from: data, calendarId: calendarId)
        return events
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
                colorHex: entry.colorId
            )
        }
    }

    private func parseEventList(from data: Data, calendarId: String) throws -> ([Event], String?) {
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

    private static let isoFormatter = ISO8601DateFormatter()
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func convertToEvent(from entry: GCalEventEntry, calendarId: String) -> Event? {
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

        return Event(
            id: id,
            title: summary,
            startDate: startDate,
            endDate: endDate,
            organizer: entry.organizer?.email,
            description: entry.description,
            location: entry.location,
            attendees: attendees,
            attachments: attachments,
            isAllDay: isAllDay,
            calendarId: calendarId,
            timezone: timezone,
            links: links,
            provider: provider
        )
    }

    private func parseDate(from dt: GCalDateTime) -> (Date, Bool)? {
        if let dateTimeString = dt.dateTime,
           let date = Self.isoFormatter.date(from: dateTimeString)
        {
            return (date, false)
        }
        if let dateString = dt.date,
           let date = Self.dayFormatter.date(from: dateString)
        {
            return (date, true)
        }
        return nil
    }

    private func extractMeetingLinks(from entry: GCalEventEntry) -> [URL] {
        var links: [URL] = []

        if let location = entry.location, let url = extractURL(from: location) {
            links.append(url)
        }

        if let description = entry.description {
            links.append(contentsOf: extractURLs(from: description))
        }

        if let entryPoints = entry.conferenceData?.entryPoints {
            for ep in entryPoints {
                if let uri = ep.uri, let url = URL(string: uri) {
                    links.append(url)
                }
            }
        }

        // Stable dedup preserving order
        var seen = Set<String>()
        return links.filter { seen.insert($0.absoluteString.lowercased()).inserted }
    }

    private func extractURL(from text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(
            in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)
        )

        return matches?.first?.url
    }

    private func extractURLs(from text: String) -> [URL] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(
            in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)
        )

        return matches?.compactMap(\.url) ?? []
    }

    // MARK: - Test Compatibility

    /// Converts a raw dictionary to GCalEventEntry for parsing. Used by existing tests.
    func parseEvent(from item: [String: Any], calendarId: String) -> Event? {
        guard let data = try? JSONSerialization.data(withJSONObject: item),
              let entry = try? JSONDecoder().decode(GCalEventEntry.self, from: data)
        else {
            return nil
        }
        return convertToEvent(from: entry, calendarId: calendarId)
    }

    /// Converts raw attendee dictionaries. Used by existing tests.
    func parseAttendees(from attendeesData: [[String: Any]]) -> [Attendee] {
        attendeesData.compactMap { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let parsed = try? JSONDecoder().decode(GCalAttendee.self, from: data),
                  let email = parsed.email
            else { return nil }
            return Attendee(
                name: parsed.displayName,
                email: email,
                status: AttendeeStatus(rawValue: parsed.responseStatus ?? "needsAction"),
                isOptional: parsed.isOptional ?? false,
                isOrganizer: parsed.isOrganizer ?? false,
                isSelf: parsed.isSelf ?? false
            )
        }
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
