import SwiftUI
import AppKit

/// Publish tab: topic input, payload editor (raw/xml/json), retain + QoS,
/// publish history.
struct PublishView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var historyOpen = false

    private var topicBinding: Binding<String> {
        Binding(
            get: { model.publish.manualTopic ?? "" },
            set: { model.publish.manualTopic = $0.isEmpty ? nil : $0 }
        )
    }

    private var payloadBinding: Binding<String> {
        Binding(
            get: { model.publish.payload ?? "" },
            set: { model.publish.payload = $0 }
        )
    }

    var body: some View {
        @Bindable var publish = model.publish
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                topicField
                Picker("", selection: $publish.editorMode) {
                    ForEach(EditorMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                editorToolbar
                editor
                options
                publishButton
                publishHistory
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }

    private var topicField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Topic")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("", text: topicBinding, prompt: Text(model.tree.selectedPath ?? "example/topic"))
                .textFieldStyle(.roundedBorder)
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 8) {
            if model.publish.editorMode == .json {
                Button("Format JSON") {
                    formatJSON()
                }
            }
            Button("Open file") {
                if let file = FileDialogs.openFileData() {
                    model.publish.payload = String(data: file.data, encoding: .utf8)
                }
            }
            Spacer()
        }
    }

    private var editor: some View {
        let colors = CodeBlockColors.current(colorScheme)
        return TextEditor(text: payloadBinding)
            .font(.system(size: 12, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(4)
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .background(colors.background)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.gray.opacity(0.3))
            )
    }

    @ViewBuilder
    private var options: some View {
        @Bindable var publish = model.publish
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $publish.retain) {
                Text("Retain")
                    .help("Retained messages only appear to be retained, when client subscribes after the initial publish.")
            }
            .toggleStyle(.checkbox)

            HStack {
                Text("QoS")
                Picker("", selection: $publish.qos) {
                    Text("0 (At most once)").tag(0)
                    Text("1 (At least once)").tag(1)
                    Text("2 (Exactly once)").tag(2)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 180)
            }
        }
    }

    private var publishButton: some View {
        Button {
            publish()
        } label: {
            Label("Publish", systemImage: "paperplane")
                .frame(maxWidth: .infinity)
        }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!model.phase.isActive)
    }

    private func publish() {
        model.publishCurrent()
        historyOpen = true
    }

    private func formatJSON() {
        let text = model.publish.payload ?? ""
        guard let data = text.data(using: .utf8) else { return }
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let pretty = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            model.publish.payload = String(data: pretty, encoding: .utf8)
        } catch {
            model.showError("Format error: \(error.localizedDescription)")
        }
    }

    // MARK: Publish history (session-only, max 8)

    private var publishHistory: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                historyOpen.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: historyOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                    Text("History")
                        .font(.headline)
                    Text("\(model.publishHistory.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.publishHistory.isEmpty)

            if historyOpen {
                ForEach(model.publishHistory) { item in
                    Button {
                        model.publish.manualTopic = item.topic
                        model.publish.payload = item.payload
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.topic)
                                .font(.caption.bold())
                                .lineLimit(1)
                            Text(item.payload)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
