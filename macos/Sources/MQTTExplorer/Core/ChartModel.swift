import Foundation
import Observation

/// Values that can be charted: numbers, booleans as 1/0, numeric strings,
/// "on"/"off" and decimal-comma strings.
enum Plottable {
    static func value(_ raw: Any?) -> Double? {
        switch raw {
        case let number as NSNumber:
            if number === kCFBooleanTrue { return 1 }
            if number === kCFBooleanFalse { return 0 }
            return number.doubleValue
        case let bool as Bool:
            return bool ? 1 : 0
        case let double as Double:
            return double
        case let int as Int:
            return Double(int)
        case let string as String:
            return parseString(string)
        default:
            return nil
        }
    }

    static func parseString(_ value: String) -> Double? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if text.lowercased() == "on" { return 1 }
        if text.lowercased() == "off" { return 0 }
        if Double(text) != nil { return Double(text) }
        // European decimal comma: "123,45"
        if text.range(of: #"^[0-9]*,[0-9]+$"#, options: .regularExpression) != nil {
            return Double(text.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    static func isPlottable(_ raw: Any?) -> Bool {
        value(raw) != nil
    }
}

struct ChartSample: Sendable, Hashable {
    let date: Date
    let value: Double
}

enum ChartInterpolation: String, Codable, CaseIterable, Sendable {
    case curve
    case linear
    case cubicBasisSpline = "cubic_basis_spline"
    case stepAfter = "step_after"
    case stepBefore = "step_before"

    var label: String {
        rawValue.replacingOccurrences(of: "_", with: " ")
    }
}

enum ChartWidth: String, Codable, CaseIterable, Sendable {
    case big
    case medium
    case small
}

/// Persisted chart configuration.
struct ChartParameters: Codable, Hashable, Sendable {
    var topic: String
    var dotPath: String?
    var interpolation: ChartInterpolation?
    var rangeFrom: Double?
    var rangeTo: Double?
    /// A duration string like "5m" or "1h30m"; nil = everything.
    var timeRangeUntil: String?
    var width: ChartWidth?
    var color: String?

    var key: ChartKey { ChartKey(path: topic, field: dotPath) }
}

struct ChartKey: Hashable, Sendable {
    let path: String
    /// nil = the whole payload is the number; otherwise a dot-separated JSON
    /// field path inside a JSON object payload.
    let field: String?

    var title: String {
        field.map { "\(path) → \($0)" } ?? path
    }
}

/// One live chart. Samples are capped at 500.
@Observable
@MainActor
final class ChartSeries {
    let key: ChartKey
    var parameters: ChartParameters
    var samples: [ChartSample] = []
    /// Frozen copy of the samples while the chart is paused.
    var frozenSamples: [ChartSample]?

    static let maxSamples = 500

    var id: ChartKey { key }

    var paused: Bool { frozenSamples != nil }

    init(parameters: ChartParameters) {
        self.key = parameters.key
        self.parameters = parameters
    }

    func add(_ sample: ChartSample) {
        samples.append(sample)
        if samples.count > Self.maxSamples {
            samples.removeFirst(samples.count - Self.maxSamples)
        }
    }

    var displaySamples: [ChartSample] {
        let base = frozenSamples ?? samples
        guard let until = parameters.timeRangeUntil, let seconds = DurationParser.seconds(until) else {
            return base
        }
        let cutoff = Date().addingTimeInterval(-seconds)
        return base.filter { $0.date >= cutoff }
    }
}

/// Parses duration strings: "10s", "5m", "1h30m", "1d", "500ms", "2w".
enum DurationParser {
    static func seconds(_ text: String) -> TimeInterval? {
        let units: [(String, Double)] = [
            ("milliseconds", 0.001), ("millisecond", 0.001), ("msecs", 0.001), ("msec", 0.001), ("ms", 0.001),
            ("seconds", 1), ("second", 1), ("secs", 1), ("sec", 1), ("s", 1),
            ("minutes", 60), ("minute", 60), ("mins", 60), ("min", 60), ("m", 60),
            ("hours", 3600), ("hour", 3600), ("hrs", 3600), ("hr", 3600), ("h", 3600),
            ("days", 86400), ("day", 86400), ("d", 86400),
            ("weeks", 604800), ("week", 604800), ("wks", 604800), ("wk", 604800), ("w", 604800),
            ("years", 31_557_600), ("year", 31_557_600), ("yrs", 31_557_600), ("yr", 31_557_600), ("y", 31_557_600),
        ]

        let pattern = "([0-9]*\\.?[0-9]+)\\s*([a-zA-Z]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return nil }

        var total: TimeInterval = 0
        var matchedLength = 0
        for match in matches {
            guard let numberRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let number = Double(text[numberRange]) else { return nil }
            let unitText = text[unitRange].lowercased()
            guard let unit = units.first(where: { $0.0 == unitText }) else { return nil }
            total += number * unit.1
            matchedLength += match.range.length
        }
        return matchedLength > 0 ? total : nil
    }
}

extension ChartSeries: @MainActor Identifiable {}

/// Owns all active charts and feeds them samples from tree deltas.
@Observable
@MainActor
final class ChartStore {
    private(set) var series: [ChartSeries] = []
    private var index: [ChartKey: ChartSeries] = [:]

    func hasChart(for path: String) -> Bool {
        index.keys.contains { $0.path == path }
    }

    /// Values plottable for charting in a JSON payload: any scalar that
    /// Plottable accepts (numbers, booleans, numeric strings, on/off).
    static func plottableFields(in payload: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: payload),
              let dict = object as? [String: Any] else { return [] }
        return dict.keys.filter { Plottable.isPlottable(dict[$0]) }.sorted()
    }

    func addChart(parameters: ChartParameters) {
        guard index[parameters.key] == nil else { return }
        let chart = ChartSeries(parameters: parameters)
        index[chart.key] = chart
        series.append(chart)
    }

    func addChart(path: String, field: String?) {
        addChart(parameters: ChartParameters(topic: path, dotPath: field))
    }

    func updateChart(topic: String, dotPath: String?, mutate: (inout ChartParameters) -> Void) {
        guard let chart = index[ChartKey(path: topic, field: dotPath)] else { return }
        mutate(&chart.parameters)
    }

    func removeChart(_ chart: ChartSeries) {
        series.removeAll { $0.key == chart.key }
        index.removeValue(forKey: chart.key)
    }

    func removeCharts(for path: String) {
        let keys = index.keys.filter { $0.path == path }
        for key in keys {
            index.removeValue(forKey: key)
        }
        series.removeAll { keys.contains($0.key) }
    }

    /// Swap a chart with the previous one.
    func moveUp(topic: String, dotPath: String?) {
        guard let idx = series.firstIndex(where: { $0.key == ChartKey(path: topic, field: dotPath) }),
              idx > 0 else { return }
        series.swapAt(idx, idx - 1)
    }

    func clearData(_ chart: ChartSeries) {
        chart.samples.removeAll()
        chart.frozenSamples = nil
    }

    func togglePause(_ chart: ChartSeries) {
        if chart.paused {
            chart.frozenSamples = nil
        } else {
            chart.frozenSamples = chart.samples
        }
    }

    func clear() {
        series.removeAll()
        index.removeAll()
    }

    /// Feed one topic update to any charts registered for it.
    func ingest(update: NodeUpdate) {
        let charts = index.keys.filter { $0.path == update.path }
        guard !charts.isEmpty, let message = update.message, !message.payload.isEmpty else { return }

        for key in charts {
            guard let value = Self.value(in: message.payload, field: key.field) else { continue }
            index[key]?.add(ChartSample(date: message.received, value: value))
        }
    }

    /// Seed a freshly added chart from existing history.
    func seed(path: String, field: String?, from history: [StoredMessage]) {
        guard let chart = index[ChartKey(path: path, field: field)] else { return }
        for message in history.reversed() {
            guard let value = Self.value(in: message.payload, field: field) else { continue }
            chart.add(ChartSample(date: message.received, value: value))
        }
    }

    /// Plottable value from a payload: whole payload (field == nil) or a JSON
    /// dot-path inside it.
    static func value(in payload: Data, field: String?) -> Double? {
        if field == nil {
            guard let text = String(data: payload, encoding: .utf8) else { return nil }
            return Plottable.parseString(text)
        }
        guard let object = try? JSONSerialization.jsonObject(with: payload) else { return nil }
        var current: Any = object
        for part in field?.split(separator: ".").map(String.init) ?? [] {
            if let dict = current as? [String: Any], let next = dict[part] {
                current = next
            } else if let array = current as? [Any], let idx = Int(part), array.indices.contains(idx) {
                current = array[idx]
            } else {
                return nil
            }
        }
        return Plottable.value(current)
    }

    var persistedParameters: [ChartParameters] {
        series.map(\.parameters)
    }

    func restore(_ parameters: [ChartParameters]) {
        clear()
        for chart in parameters {
            addChart(parameters: chart)
        }
    }
}
