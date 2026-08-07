import SwiftUI
import AppKit

/// Details tab: breadcrumb, metadata, current value (diff/raw), message
/// history and topic statistics.
struct DetailsView: View {
    @Bindable var model: AppModel
    @State private var history: [StoredMessage] = []
    @State private var rawAsText = false

    /// Reloads on selection change and at most a few times a second while
    /// messages keep arriving.
    private func historyKey(_ node: UITopicNode) -> String {
        "\(node.path)#\(model.historyTick)"
    }

    var body: some View {
        if let node = model.selectedNode {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    breadcrumb(node)
                    statusLine(node)
                    if node.message != nil {
                        currentValueToolbar(node)
                        currentValue(node)
                    }
                    if node.childCount > 0 {
                        if node.message != nil { Divider() }
                        ActivityTableView(model: model, node: node)
                    }
                    Divider()
                    HistoryView(model: model, topic: node.path, history: history)
                    Divider()
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
                model.chartEverything(at: node.path)
            } label: {
                Image(systemName: "chart.xyaxis.line")
            }
            .buttonStyle(.borderless)
            .help("Chart every value on this topic and its direct children")

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

    // MARK: Status bar (last message, QoS, retained)

    /// One bar grouping the message facts: when the last message arrived
    /// (for retained messages that is the moment it was retained), its QoS,
    /// and the retained state with the control to clear it.
    private func statusLine(_ node: UITopicNode) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("Last message")
                    .foregroundStyle(.secondary)
                Text(DateFormatterFormatting.format(
                    node.lastUpdate,
                    locale: model.settings.timeLocale
                ))
                .monospacedDigit()
            }
            if let message = node.message {
                HStack(spacing: 6) {
                    Text("QoS")
                        .foregroundStyle(.secondary)
                    Text("\(message.qos)")
                        .monospacedDigit()
                }
            }
            Spacer()
            if node.everRetained {
                HStack(spacing: 6) {
                    Image(systemName: "pin.fill")
                    Text("Retained")
                        .fontWeight(.semibold)
                    Button {
                        Task { await model.clearTopic(path: node.path, recursive: false) }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Publish an empty payload to remove the retained message")
                }
                .foregroundStyle(.orange)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
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
                Text("Value").tag(ValueRendererDisplayMode.value)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
            .help("Diff: change against the previous message. Raw: the payload as sent. Value: chart the numbers.")
            .onChange(of: model.settings.valueRendererDisplayMode) {
                model.saveConfig()
            }

            Button {
                guard let payload = node.message?.payload else { return }
                Clipboard.copy(Self.textRepresentation(of: payload))
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy value")

            Button {
                guard let payload = node.message?.payload else { return }
                if String(data: payload, encoding: .utf8) != nil {
                    FileDialogs.saveText(Self.textRepresentation(of: payload), suggestedName: node.name + ".txt")
                } else {
                    FileDialogs.saveData(payload, suggestedName: node.name + ".bin")
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .help("Save value to file")
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

    /// JSON in Raw mode defaults to the field table; the text toggle shows the
    /// payload exactly as it arrived.
    private var rawToggle: some View {
        Picker("", selection: $rawAsText) {
            Text("Fields").tag(false)
            Text("Text").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 130)
    }

    /// Binary payloads copy and save as the hex dump the UI is showing.
    static func textRepresentation(of payload: Data) -> String {
        String(data: payload, encoding: .utf8) ?? MessageRendering.hexDump(payload)
    }

    private func visualizable(_ node: UITopicNode) -> Bool {
        ValueShape.of(node.message?.payload ?? Data()).isVisualizable
    }

    @ViewBuilder
    private func currentValue(_ node: UITopicNode) -> some View {
        if let message = node.message {
            switch model.settings.valueRendererDisplayMode {
            case .value:
                if visualizable(node) {
                    ValueView(model: model, node: node, history: history)
                } else {
                    PayloadView(payload: message.payload)
                }
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
                if let fields = PayloadFlattener.fields(in: message.payload) {
                    rawToggle
                    if rawAsText {
                        PayloadView(payload: message.payload)
                    } else {
                        PayloadTableView(fields: fields, model: model, topic: node.path)
                    }
                } else {
                    PayloadView(payload: message.payload)
                }
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
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
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
