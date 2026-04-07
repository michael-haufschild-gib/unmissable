import Foundation

// MARK: - Adaptive Sync Scheduling

extension SyncManager {
    /// Off-hours multiplier applied to the sync interval outside business hours.
    static let offHoursMultiplier: Double = 5.0
    /// Maximum sync interval during off-hours (seconds). Caps the multiplied interval.
    static let offHoursMaxIntervalSeconds: TimeInterval = 300.0
    /// Apple Calendar safety-net interval (seconds). With EKEventStoreChanged providing
    /// reactive sync, periodic polling is only a safety net. 10 minutes is sufficient.
    static let appleCalendarSafetyNetInterval: TimeInterval = 600.0
    /// Start of business hours (7 AM local time, inclusive).
    static let businessHoursStart = 7
    /// End of business hours (8 PM / 20:00 local time, exclusive).
    static let businessHoursEnd = 20
    /// Calendar.weekday value for Sunday.
    static let weekdaySunday = 1
    /// Calendar.weekday value for Saturday.
    static let weekdaySaturday = 7

    /// Returns the sync interval adjusted for provider type and time of day.
    ///
    /// Apple Calendar: EKEventStoreChanged delivers reactive sync on every
    /// local/iCloud change, so periodic polling is a safety net only (10 min).
    ///
    /// Google Calendar: During business hours (7 AM–8 PM weekdays), returns the
    /// user-configured interval. Outside business hours, multiplies by 5x
    /// (capped at 5 min) to reduce overnight/weekend network activity.
    func effectiveSyncInterval() -> TimeInterval {
        if providerType == .apple {
            return Self.appleCalendarSafetyNetInterval
        }

        let base = syncInterval
        guard isOffHours() else { return base }
        // Off-hours should always be slower than business hours, never faster.
        // Cap at 5 min but ensure the result is at least `base`.
        return max(base, min(base * Self.offHoursMultiplier, Self.offHoursMaxIntervalSeconds))
    }

    /// Whether the current local time is outside business hours.
    /// Business hours: 7 AM – 8 PM, Monday through Friday.
    func isOffHours() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)

        let isWeekend = weekday == Self.weekdaySunday || weekday == Self.weekdaySaturday
        if isWeekend { return true }

        return hour < Self.businessHoursStart || hour >= Self.businessHoursEnd
    }
}
