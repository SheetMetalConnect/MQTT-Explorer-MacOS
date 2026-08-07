import SwiftUI

struct DiagnosticsView: View {
    @Bindable var model: AppModel
    @Bindable var log = AppLog.shared

    var body: some View {
        Form {
            Section("Connections and settings") {
                LabeledContent("Profiles") {
                    Text("\(model.profiles.count)")
                        .monospacedDigit()
                }
                HStack {
                    Button("Export…") { model.exportSettings() }
                    Button("Import…") { model.importSettings() }
                }
                Text("Profiles and preferences as JSON. Passwords stay in the Keychain and are never written to the file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Log") {
                if log.entries.isEmpty {
                    Text("Nothing logged yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(log.entries.reversed()) { entry in
                                row(entry)
                            }
                        }
                    }
                    .frame(height: 180)
                }

                HStack {
                    Button("Copy") { Clipboard.copy(log.text) }
                        .disabled(log.entries.isEmpty)
                    Button("Save…") {
                        FileDialogs.saveText(log.text, suggestedName: "mqtt-explorer-log.txt")
                    }
                    .disabled(log.entries.isEmpty)
                    Spacer()
                    Button("Clear") { log.clear() }
                        .disabled(log.entries.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 380)
    }

    private func row(_ entry: AppLog.Entry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(DateFormatterFormatting.timeOnly(entry.at, locale: model.settings.timeLocale))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Text(entry.message)
                .foregroundStyle(color(for: entry.level))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
    }

    private func color(for level: AppLog.Entry.Level) -> Color {
        switch level {
        case .info: .primary
        case .warning: .orange
        case .error: .red
        }
    }
}
