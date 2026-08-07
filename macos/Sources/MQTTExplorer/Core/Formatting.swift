import Foundation

/// Locale-aware date and time formatting.
enum DateFormatterFormatting {
    /// Building a DateFormatter costs more than formatting with one, and these
    /// run per visible row per redraw, so they are made once per locale.
    private struct Formatters {
        let date: DateFormatter
        let time: DateFormatter

        init(locale: Locale) {
            date = DateFormatter()
            date.locale = locale
            date.dateStyle = .short
            date.timeStyle = .none

            time = DateFormatter()
            time.locale = locale
            time.dateStyle = .none
            time.timeStyle = .medium
        }
    }

    nonisolated(unsafe) private static var cache: [String: Formatters] = [:]
    private static let lock = NSLock()

    private static func formatters(for locale: String?) -> Formatters {
        let value = locale.flatMap { Locale(identifier: $0) } ?? Locale.current
        let key = value.identifier
        lock.lock()
        defer { lock.unlock() }
        if let existing = cache[key] { return existing }
        let made = Formatters(locale: value)
        cache[key] = made
        return made
    }

    /// Time of day only, for dense tables where the date is noise.
    static func timeOnly(_ date: Date, locale: String?) -> String {
        formatters(for: locale).time.string(from: date)
    }

    /// Locale-aware date + time with milliseconds, or "time date" when
    /// timeFirst.
    static func format(_ date: Date, locale: String?, timeFirst: Bool = false) -> String {
        let formatters = formatters(for: locale)
        let datePart = formatters.date.string(from: date)
        let timePart = formatters.time.string(from: date)

        let millis = Int((date.timeIntervalSince1970 * 1000).rounded()) % 1000
        let timeWithMillis = "\(timePart).\(String(format: "%03d", millis))"

        return timeFirst ? "\(timeWithMillis) \(datePart)" : "\(datePart) \(timeWithMillis)"
    }

    /// Interval between two dates, e.g. "1.234 seconds", choosing
    /// hours / minutes / seconds / milliseconds.
    static func interval(from earlier: Date, to later: Date) -> String {
        let intervalMs = (later.timeIntervalSince(earlier)) * 1000

        let unit: (name: String, ms: Double)
        if intervalMs > 2 * 3_600_000 {
            unit = ("hours", 3_600_000)
        } else if intervalMs > 2 * 60_000 {
            unit = ("minutes", 60_000)
        } else if intervalMs > 500 {
            unit = ("seconds", 1000)
        } else {
            unit = ("milliseconds", 1)
        }
        return String(format: "%.3f %@", intervalMs / unit.ms, unit.name)
    }
}

/// Abbreviates large numbers for chart axes and broker statistics (12.3K).
enum NumberAbbreviation {
    static func abbreviate(_ value: Double) -> String {
        let units = ["K", "M", "B", "T"]
        let magnitude = abs(value)
        guard magnitude >= 1000 else {
            return value.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", value)
                : String(value)
        }
        var scaled = value
        var unitIndex = -1
        while abs(scaled) >= 1000 && unitIndex < units.count - 1 {
            scaled /= 1000
            unitIndex += 1
        }
        var text = String(format: "%.2f", scaled)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + units[unitIndex]
    }
}

/// Locale-aware number rendering.
enum NumberFormatting {
    static func format(_ value: Double, locale: String?, grouping: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale.flatMap { Locale(identifier: $0) } ?? Locale.current
        formatter.usesGroupingSeparator = grouping
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
