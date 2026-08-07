import Foundation

/// Locale-aware date and time formatting.
enum DateFormatterFormatting {
    /// Locale-aware date + time with milliseconds, or "time date" when
    /// timeFirst.
    static func format(_ date: Date, locale: String?, timeFirst: Bool = false) -> String {
        let localeValue = locale.flatMap { Locale(identifier: $0) } ?? Locale.current

        let datePart: String = {
            let formatter = DateFormatter()
            formatter.locale = localeValue
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }()

        let timePart: String = {
            let formatter = DateFormatter()
            formatter.locale = localeValue
            formatter.dateStyle = .none
            formatter.timeStyle = .medium
            return formatter.string(from: date)
        }()

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
