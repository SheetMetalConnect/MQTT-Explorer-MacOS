import SwiftUI

/// Live table of the child topics under a branch: what changed, how recently,
/// and what it says now. Sorted by most recent update so a busy namespace
/// sorts itself.
struct ActivityTableView: View {
    @Bindable var model: AppModel
    let node: UITopicNode

    @State private var recentOnly = false

    private static let recentWindow: TimeInterval = 10
    private static let rowLimit = 60

    private var children: [UITopicNode] {
        var rows = node.childOrder
            .compactMap { node.children[$0] }
            .filter { $0.message != nil }
        if recentOnly {
            let cutoff = Date().addingTimeInterval(-Self.recentWindow)
            rows = rows.filter { $0.lastUpdate >= cutoff }
        }
        rows.sort { $0.lastUpdate > $1.lastUpdate }
        return Array(rows.prefix(Self.rowLimit))
    }

    var body: some View {
        let rows = children
        let now = Date()
        return VStack(alignment: .leading, spacing: 6) {
            header(count: rows.count)
            if rows.isEmpty {
                Text(recentOnly ? "Nothing changed in the last \(Int(Self.recentWindow)) seconds." : "No values on the direct children.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.path) { index, child in
                        if index > 0 { Divider() }
                        row(child, now: now)
                    }
                }
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 8) {
            Text("Live values")
                .font(.headline)
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Toggle("Recent only", isOn: $recentOnly)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)
                .help("Show only topics that changed in the last \(Int(Self.recentWindow)) seconds")
        }
    }

    private func row(_ child: UITopicNode, now: Date) -> some View {
        let fresh = now.timeIntervalSince(child.lastUpdate) < 2
        return HStack(spacing: 10) {
            Circle()
                .fill(fresh ? Color.accentColor : Color.secondary.opacity(0.25))
                .frame(width: 6, height: 6)

            Text(child.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(child.preview)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160, alignment: .trailing)

            Text(DateFormatterFormatting.timeOnly(child.lastUpdate, locale: model.settings.timeLocale))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Text("\(child.messageCount)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(minWidth: 28, alignment: .trailing)
                .help("Messages received")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectTopic(child.path)
        }
    }
}
