import AppKit
import Foundation

enum PayloadKind: Sendable {
    case json
    case text
    case binary
}

/// Payload decoding and formatting: JSON detection, pretty printing,
/// syntax highlighting and hex dumps.
enum MessageRendering {
    static func kind(of payload: Data) -> PayloadKind {
        guard let text = String(data: payload, encoding: .utf8) else { return .binary }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if (try? JSONSerialization.jsonObject(with: payload)) != nil {
                return .json
            }
        }
        return .text
    }

    /// Short decoded preview for tree rows (400 char limit). Only the leading
    /// bytes are decoded: the result is flattened to one line anyway.
    static func preview(for payload: Data?) -> String {
        guard let payload else { return "" }
        guard !payload.isEmpty else { return "<empty>" }
        guard !isProbablyBinary(payload) else { return "HEX \(payload.count) bytes" }
        let text = String(decoding: payload.prefix(1_200), as: UTF8.self)
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        if flat.count > 400 || payload.count > 1_200 {
            return String(flat.prefix(400)) + "…"
        }
        return flat
    }

    /// What a payload holds, judged cheaply from its first bytes. Used for the
    /// type marker in tree rows, where integration work means telling a JSON
    /// business record apart from a bare sensor reading at a glance.
    enum ValueType: String {
        case object = "{}"
        case array = "[]"
        case number = "#"
        case boolean = "T/F"
        case text = "Aa"
        case binary = "hex"
        case empty = "∅"

        var help: String {
            switch self {
            case .object: "JSON object"
            case .array: "JSON array"
            case .number: "Number"
            case .boolean: "Boolean"
            case .text: "Text"
            case .binary: "Binary"
            case .empty: "Empty payload"
            }
        }
    }

    static func valueType(of payload: Data?) -> ValueType? {
        guard let payload else { return nil }
        guard !payload.isEmpty else { return .empty }
        if isProbablyBinary(payload) { return .binary }

        let head = payload.prefix(64).drop { $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }
        switch head.first {
        case UInt8(ascii: "{"): return .object
        case UInt8(ascii: "["): return .array
        default: break
        }

        let text = String(decoding: payload.prefix(64), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if text == "true" || text == "false" { return .boolean }
        if payload.count <= 32, Plottable.parseString(text) != nil, text != "on", text != "off" {
            return .number
        }
        return .text
    }

    /// Control bytes other than tab/newline/return mean this is not text.
    private static func isProbablyBinary(_ payload: Data) -> Bool {
        payload.prefix(512).contains { $0 < 0x09 || ($0 > 0x0D && $0 < 0x20) }
    }

    static func prettyJSON(_ payload: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: payload, options: [.fragmentsAllowed]) else {
            return nil
        }
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: options) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Classic hex dump with an ASCII gutter.
    static func hexDump(_ payload: Data) -> String {
        let bytes = [UInt8](payload)
        var lines: [String] = []
        var offset = 0
        while offset < bytes.count {
            let chunk = bytes[offset..<min(offset + 16, bytes.count)]
            let hex = chunk.map { String(format: "%02x", $0) }.joined(separator: " ")
            let ascii = chunk.map { ($0 >= 0x20 && $0 < 0x7f) ? Character(UnicodeScalar($0)) : "." }
            lines.append(String(format: "%08x  %-47@  %@", offset, hex, String(ascii)))
            offset += 16
        }
        return lines.joined(separator: "\n")
    }

    /// Syntax-highlighted pretty JSON.
    static func highlightedJSON(_ payload: Data) -> AttributedString? {
        guard let pretty = prettyJSON(payload) else { return nil }
        return highlight(jsonText: pretty)
    }

    static func highlight(jsonText: String) -> AttributedString {
        var attributed = AttributedString(jsonText)

        // String values first, keys afterwards so keys win where they overlap.
        paint(#""(?:[^"\\]|\\.)*""#, color: .systemRed, text: jsonText, into: &attributed)
        paint(#""((?:[^"\\]|\\.)*)"\s*:"#, color: .systemBlue, text: jsonText, into: &attributed)
        paint(#"-?\b\d+(\.\d+)?([eE][+-]?\d+)?\b"#, color: .systemOrange, text: jsonText, into: &attributed)
        paint(#"\b(true|false|null)\b"#, color: .systemPurple, text: jsonText, into: &attributed)

        return attributed
    }

    private static func paint(_ pattern: String, color: NSColor, text: String, into attributed: inout AttributedString) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: fullRange) {
            guard let stringRange = Range(match.range, in: text),
                  let attrRange = Range<AttributedString.Index>(stringRange, in: attributed) else { continue }
            attributed[attrRange].foregroundColor = color
        }
    }

    /// Line-based diff between two payloads: "-" removed, "+" added lines.
    static func diff(old: Data?, new: Data) -> [(sign: String, line: String)] {
        let oldText = old.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let newText = String(data: new, encoding: .utf8) ?? ""
        let oldLines = oldText.components(separatedBy: "\n")
        let newLines = newText.components(separatedBy: "\n")

        // Myers is overkill here; LCS via dynamic programming handles the
        // payload sizes we show (bounded by maxPayload).
        let m = oldLines.count
        let n = newLines.count
        var lcs = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        if m * n <= 1_000_000 {
            for i in stride(from: m - 1, through: 0, by: -1) {
                for j in stride(from: n - 1, through: 0, by: -1) {
                    lcs[i][j] = oldLines[i] == newLines[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }

        var result: [(String, String)] = []
        var i = 0
        var j = 0
        while i < m && j < n {
            if oldLines[i] == newLines[j] {
                result.append((" ", oldLines[i]))
                i += 1
                j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                result.append(("-", oldLines[i]))
                i += 1
            } else {
                result.append(("+", newLines[j]))
                j += 1
            }
        }
        while i < m {
            result.append(("-", oldLines[i]))
            i += 1
        }
        while j < n {
            result.append(("+", newLines[j]))
            j += 1
        }
        return result
    }
}
