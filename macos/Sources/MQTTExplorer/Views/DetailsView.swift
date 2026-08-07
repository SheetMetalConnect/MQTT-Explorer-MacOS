import SwiftUI
import AppKit

/// Details tab: breadcrumb, metadata, current value (diff/raw), message
/// history and topic statistics.
struct DetailsView: View {
    @Bindable var model: AppModel
    @State private var history: [StoredMessage] = []

    var body: some View {
        if let node = model.selectedNode {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    breadcrumb(node)
                    metadataBar(node)
                    currentValueToolbar(node)
                    currentValue(node)
                    HistoryView(model: model, topic: node.path, history: history)
                    statistics(node)
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
            .task(id: historyKey(node)) {
                history = await model.history(for: node.path)
            }
        } else {
            emptyState
        }
    }

    /// Reload the history whenever the selection changes or new messages
    /// arrive for the selected topic.
    private func historyKey(_ node: UITopicNode) -> String {
        "\(node.path)#\(node.messageCount)"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("Select a topic to view details")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Breadcrumb + copy + delete

    private func breadcrumb(_ node: UITopicNode) -> some View {
        HStack(spacing: 6) {
            Text(node.path)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Button {
                Clipboard.copy(node.path)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy topic path")

            if node.childTopicCount == 0 {
                Button {
                    Task { await model.clearTopic(path: node.path, recursive: false) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete this topic")
            } else {
                Button {
                    Task { await model.clearTopic(path: node.path, recursive: true) }
                } label: {
                    Image(systemName: "folder.badge.minus")
                }
                .buttonStyle(.borderless)
                .help("Delete topic and all subtopics")
            }
        }
    }

    // MARK: Metadata (date, retained, qos)

    private func metadataBar(_ node: UITopicNode) -> some View {
        HStack(spacing: 8) {
            Text(DateFormatterFormatting.format(
                node.lastUpdate,
                locale: model.settings.timeLocale
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            if let message = node.message {
                if message.retain {
                    Text("Retained")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("QoS \(message.qos)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Current value toolbar (Diff/Raw, copy, save, delete retained)

    private func currentValueToolbar(_ node: UITopicNode) -> some View {
        HStack(spacing: 8) {
            Text("Current Value")
                .font(.headline)
            Spacer()

            Picker("", selection: $model.settings.valueRendererDisplayMode) {
                Text("Diff").tag(ValueRendererDisplayMode.diff)
                Text("Raw").tag(ValueRendererDisplayMode.raw)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 120)
            .help("Diff: Show difference between the current and the last message. Raw: Raw / formatted JSON.")
            .onChange(of: model.settings.valueRendererDisplayMode) {
                model.saveConfig()
            }

            Button {
                if let message = node.message, let text = String(data: message.payload, encoding: .utf8) {
                    Clipboard.copy(text)
                }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy value")

            Button {
                if let message = node.message, let text = String(data: message.payload, encoding: .utf8) {
                    FileDialogs.saveText(text, suggestedName: node.name + ".txt")
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .help("Save value to file")

            if let message = node.message, message.retain {
                Button {
                    Task { await model.clearTopic(path: node.path, recursive: false) }
                } label: {
                    HStack(spacing: 2) {
                        Text("retained")
                        Image(systemName: "xmark")
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Delete retained topic")
            }
        }
    }

    // MARK: Value rendering

    /// The message to diff against: an explicitly selected history message,
    /// otherwise the second-newest message, otherwise the current one.
    private func compareTarget(_ node: UITopicNode) -> (message: StoredMessage, name: String) {
        if let explicit = model.compareMessage {
            return (explicit, "selected")
        }
        if history.count > 1 {
            return (history[1], "previous")
        }
        return (node.message ?? StoredMessage(payload: Data(), qos: 0, retain: false, received: Date(), sequence: 0), "previous")
    }

    @ViewBuilder
    private func currentValue(_ node: UITopicNode) -> some View {
        if let message = node.message {
            switch model.settings.valueRendererDisplayMode {
            case .diff:
                let compare = compareTarget(node)
                CodeDiffView(
                    model: model,
                    topic: node.path,
                    old: compare.message.payload,
                    new: message.payload,
                    compareName: compare.name,
                    historyCount: history.count
                )
            case .raw:
                PayloadView(payload: message.payload)
                if let explicit = model.compareMessage, explicit != message {
                    Text("selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    PayloadView(payload: explicit.payload)
                }
            }
        } else {
            Text("No message")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Statistics

    private func statistics(_ node: UITopicNode) -> some View {
        HStack(spacing: 0) {
            stat("Messages", value: node.messageCount)
            Divider().frame(height: 32)
            stat("Subtopics", value: node.childTopicCount)
            Divider().frame(height: 32)
            stat("Total", value: node.leafMessageCount)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            Color(nsColor: .underPageBackgroundColor),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    private func stat(_ title: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 15, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
    }
}

/// Renders a single payload: highlighted pretty JSON, plain text or a hex
/// dump. Used by the raw display mode and the history drawer.
struct PayloadView: View {
    let payload: Data
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = CodeBlockColors.current(colorScheme)
        ScrollView(.horizontal) {
            content
                .font(.system(size: 12, design: .monospaced))
                .padding(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.background)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var content: some View {
        switch MessageRendering.kind(of: payload) {
        case .json:
            if let highlighted = MessageRendering.highlightedJSON(payload) {
                Text(highlighted)
                    .textSelection(.enabled)
            } else {
                Text(String(data: payload, encoding: .utf8) ?? "")
                    .textSelection(.enabled)
            }
        case .text:
            Text(String(data: payload, encoding: .utf8) ?? "")
                .textSelection(.enabled)
        case .binary:
            Text(MessageRendering.hexDump(payload))
                .textSelection(.enabled)
        }
    }
}
