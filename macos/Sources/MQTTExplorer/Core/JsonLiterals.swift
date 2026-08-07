import Foundation

struct JsonLiteralLocation {
    /// Dot-separated property path ("a.b.0.c"), dots inside keys escaped.
    let path: String
    /// Zero-based line index in the scanned text.
    let line: Int
    /// String / Double / Bool, nil for JSON null.
    let value: Any?
}

/// Walks a formatted JSON document and records where each scalar literal
/// lives, so the value renderer can put a "plot this" icon next to plottable
/// lines.
enum JsonLiteralScanner {
    private struct Frame {
        var isArray: Bool
        /// Key (objects) or index (arrays) this container has within its parent.
        var identifier: String?
        var currentKey: String?
        var index = 0
        var expectingKey: Bool

        init(isArray: Bool, identifier: String?) {
            self.isArray = isArray
            self.identifier = identifier
            self.expectingKey = !isArray
        }
    }

    /// Returns literals keyed by zero-based line number. Never nil; an empty
    /// dictionary means no literals were found.
    static func literalsByLine(_ text: String) -> [Int: JsonLiteralLocation] {
        let chars = Array(text)
        var frames: [Frame] = []
        var literals: [JsonLiteralLocation] = []
        var line = 0
        var i = 0

        func record(_ value: Any?, at lineIndex: Int) {
            var parts: [String] = []
            for frame in frames.dropFirst() {
                if let identifier = frame.identifier {
                    parts.append(identifier)
                }
            }
            if let frame = frames.last {
                let identifier = frame.isArray ? String(frame.index) : frame.currentKey
                if let identifier { parts.append(identifier) }
            }
            literals.append(
                JsonLiteralLocation(path: parts.joined(separator: "."), line: lineIndex, value: value)
            )
        }

        while i < chars.count {
            let c = chars[i]
            if c == "\n" {
                line += 1
                i += 1
                continue
            }

            if c == "\"" {
                let startLine = line
                var buffer: [Character] = []
                var escaped = false
                i += 1
                while i < chars.count {
                    let sc = chars[i]
                    if sc == "\n" { line += 1 }
                    if escaped {
                        buffer.append(sc)
                        escaped = false
                    } else if sc == "\\" {
                        escaped = true
                    } else if sc == "\"" {
                        i += 1
                        break
                    } else {
                        buffer.append(sc)
                    }
                    i += 1
                }
                let value = String(buffer)
                if let lastIndex = frames.indices.last, !frames[lastIndex].isArray, frames[lastIndex].expectingKey {
                    frames[lastIndex].currentKey = value
                    frames[lastIndex].expectingKey = false
                } else {
                    record(value, at: startLine)
                }
                continue
            }

            switch c {
            case "{":
                let identifier = currentIdentifier(frames)
                frames.append(Frame(isArray: false, identifier: identifier))
                i += 1
            case "[":
                let identifier = currentIdentifier(frames)
                frames.append(Frame(isArray: true, identifier: identifier))
                i += 1
            case "}", "]":
                if !frames.isEmpty { frames.removeLast() }
                i += 1
            case ",":
                if let lastIndex = frames.indices.last {
                    if frames[lastIndex].isArray {
                        frames[lastIndex].index += 1
                    } else {
                        frames[lastIndex].expectingKey = true
                        frames[lastIndex].currentKey = nil
                    }
                }
                i += 1
            case ":", " ", "\t", "\r":
                i += 1
            case "t", "f", "n":
                let startLine = line
                if matches(chars, at: i, "true") {
                    record(true, at: startLine)
                    i += 4
                } else if matches(chars, at: i, "false") {
                    record(false, at: startLine)
                    i += 5
                } else if matches(chars, at: i, "null") {
                    record(nil, at: startLine)
                    i += 4
                } else {
                    i += 1
                }
            default:
                // Number
                let startLine = line
                var j = i
                while j < chars.count, "-+0123456789.eE".contains(chars[j]) {
                    if chars[j] == "\n" { break }
                    j += 1
                }
                let raw = String(chars[i..<j])
                if let value = Double(raw) {
                    record(value, at: startLine)
                }
                i = j
            }
        }

        return Dictionary(literals.map { ($0.line, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private static func currentIdentifier(_ frames: [Frame]) -> String? {
        guard let frame = frames.last else { return nil }
        return frame.isArray ? String(frame.index) : frame.currentKey
    }

    private static func matches(_ chars: [Character], at index: Int, _ word: String) -> Bool {
        let wordChars = Array(word)
        guard index + wordChars.count <= chars.count else { return false }
        for k in 0..<wordChars.count where chars[index + k] != wordChars[k] {
            return false
        }
        return true
    }
}
