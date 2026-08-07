import SwiftUI

/// Line diff between the current payload and the compare message, with a
/// gutter that offers "plot this value" icons on plottable JSON lines.
struct CodeDiffView: View {
    @Bindable var model: AppModel
    let topic: String
    let old: Data
    let new: Data
    /// "previous" or "selected", shown in the diff-count line.
    let compareName: String
    /// Chart previews need at least two messages.
    let historyCount: Int

    @Environment(\.colorScheme) private var colorScheme
    @State private var rows: [DiffRow] = []
    @State private var addedCount = 0
    @State private var removedCount = 0

    private struct DiffRow: Identifiable {
        let id: Int
        let sign: String
        let content: AttributedString
        let newLineIndex: Int?
    }

    private var diffKey: String {
        "\(old.hashValue)#\(new.hashValue)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            diffCount
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        diffRow(row)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 240, alignment: .topLeading)
            .background(CodeBlockColors.current(colorScheme).background)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .task(id: diffKey) {
            buildRows()
        }
    }

    private var diffCount: some View {
        HStack(spacing: 4) {
            Text("Comparing with \(compareName) message:")
            Text("+ \(addedCount) line(s)")
                .foregroundStyle(Color(red: 10 / 255, green: 255 / 255, blue: 10 / 255))
            Text("- \(removedCount) line(s)")
                .foregroundStyle(Color(red: 255 / 255, green: 10 / 255, blue: 10 / 255))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func diffRow(_ row: DiffRow) -> some View {
        HStack(spacing: 0) {
            gutter(row)
                .frame(width: 33)
                .frame(maxHeight: .infinity)
                .background(CodeBlockColors.current(colorScheme).gutters)
            Text(row.content)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(lineBackground(row.sign))
        }
        .frame(minHeight: 16)
    }

    @ViewBuilder
    private func gutter(_ row: DiffRow) -> some View {
        HStack(spacing: 2) {
            if row.sign == "+" {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color(red: 10 / 255, green: 255 / 255, blue: 10 / 255))
                    .font(.system(size: 9))
            } else if row.sign == "-" {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Color(red: 255 / 255, green: 10 / 255, blue: 10 / 255))
                    .font(.system(size: 9))
            }
            if let lineIndex = row.newLineIndex, let literal = literalCache?[lineIndex],
               Plottable.isPlottable(literal.value) {
                Button {
                    model.registerChart(
                        topic: topic,
                        dotPath: literal.path.isEmpty ? nil : literal.path
                    )
                } label: {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 9))
                        .foregroundStyle(historyCount > 1 ? Color.accentColor : Color(hex: "AAAAAA"))
                }
                .buttonStyle(.borderless)
                .disabled(historyCount <= 1)
                .help(
                    historyCount > 1
                        ? "Add to chart panel"
                        : "Add to chart panel, not enough data for preview"
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func lineBackground(_ sign: String) -> Color {
        switch sign {
        case "+": Color(red: 10 / 255, green: 255 / 255, blue: 10 / 255).opacity(0.3)
        case "-": Color(red: 255 / 255, green: 10 / 255, blue: 10 / 255).opacity(0.3)
        default: .clear
        }
    }

    // MARK: Diff construction

    @State private var literalCache: [Int: JsonLiteralLocation]?

    private func buildRows() {
        let colors = CodeBlockColors.current(colorScheme)
        let isNewJSON = MessageRendering.kind(of: new) == .json
        let isOldJSON = MessageRendering.kind(of: old) == .json

        let newText: String
        let oldText: String
        var literals: [Int: JsonLiteralLocation]?

        if isNewJSON, let prettyNew = MessageRendering.prettyJSON(new) {
            newText = prettyNew
            oldText = (isOldJSON ? MessageRendering.prettyJSON(old) : String(data: old, encoding: .utf8)) ?? ""
            literals = JsonLiteralScanner.literalsByLine(prettyNew)
        } else {
            newText = String(data: new, encoding: .utf8) ?? MessageRendering.hexDump(new)
            oldText = String(data: old, encoding: .utf8) ?? ""
        }
        literalCache = literals

        let highlightedLines = isNewJSON
            ? Self.lines(of: MessageRendering.highlight(jsonText: newText))
            : []

        let rawDiff = MessageRendering.diff(old: Data(oldText.utf8), new: Data(newText.utf8))

        var built: [DiffRow] = []
        var newLineIndex = 0
        var added = 0
        var removed = 0
        for (index, entry) in rawDiff.enumerated() {
            let (sign, line) = entry
            let content: AttributedString
            switch sign {
            case "+":
                content = highlightedLine(at: newLineIndex, plain: line, highlighted: highlightedLines, colors: colors)
                newLineIndex += 1
                added += 1
            case " ":
                content = highlightedLine(at: newLineIndex, plain: line, highlighted: highlightedLines, colors: colors)
                newLineIndex += 1
            default:
                var plain = AttributedString(line)
                plain.foregroundColor = colors.text
                content = plain
                removed += 1
            }
            built.append(DiffRow(
                id: index,
                sign: sign,
                content: content,
                newLineIndex: sign == "-" ? nil : newLineIndex - 1
            ))
        }

        rows = built
        addedCount = added
        removedCount = removed
    }

    private func highlightedLine(
        at index: Int,
        plain: String,
        highlighted: [AttributedString],
        colors: CodeBlockColors
    ) -> AttributedString {
        if highlighted.indices.contains(index) {
            return highlighted[index]
        }
        var attributed = AttributedString(plain)
        attributed.foregroundColor = colors.text
        return attributed
    }

    /// Split a highlighted document into per-line AttributedStrings while
    /// preserving the syntax colors.
    private static func lines(of attributed: AttributedString) -> [AttributedString] {
        let ns = NSAttributedString(attributed)
        let text = ns.string
        var result: [AttributedString] = []
        var lineStart = text.startIndex
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let newline = text[searchStart...].firstIndex(of: "\n") {
            result.append(AttributedString(ns.attributedSubstring(from: NSRange(lineStart..<newline, in: text))))
            lineStart = text.index(after: newline)
            searchStart = lineStart
        }
        result.append(AttributedString(ns.attributedSubstring(from: NSRange(lineStart..<text.endIndex, in: text))))
        return result
    }
}
