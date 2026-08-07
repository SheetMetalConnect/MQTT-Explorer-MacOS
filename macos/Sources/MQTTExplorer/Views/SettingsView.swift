import SwiftUI

/// The Settings window (Cmd-,): tree behavior, display options and live
/// broker statistics.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Tree") {
                Picker("Auto Expand", selection: $model.settings.autoExpandLimit) {
                    Text("Collapsed").tag(0)
                    Text("Few, ≤ 2 topics").tag(2)
                    Text("Some, ≤ 5 topics").tag(5)
                    Text("Most, ≤ 15 topics").tag(15)
                    Text("Most, ≤ 30 topics").tag(30)
                    Text("All").tag(1_000_000)
                }

                Picker("Topic Order", selection: $model.settings.topicOrder) {
                    ForEach(TopicOrder.allCases, id: \.self) { order in
                        Text(order.label).tag(order)
                    }
                }
            }

            Section("Display") {
                Picker("Time Locale", selection: $model.settings.timeLocale) {
                    ForEach(Self.localeSamples, id: \.id) { entry in
                        Text("\(entry.id)  (\(entry.sample))").tag(entry.id)
                    }
                }

                Toggle(isOn: $model.settings.highlightTopicUpdates) {
                    Text("Show Activity")
                }
                Text("Topics blink when a new message arrives")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $model.settings.selectTopicWithMouseOver) {
                    Text("Quick Preview")
                }
                Text("Select topics on mouse over")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(isOn: darkModeBinding) {
                    Text("Dark Mode")
                }
                Text("Enable dark theme")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            BrokerStatisticsView(model: model)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: model.settings) {
            model.saveConfig()
        }
    }

    private static let localeSamples: [(id: String, sample: String)] = {
        let now = Date()
        return Locale.availableIdentifiers
            .sorted { (Locale.current.localizedString(forIdentifier: $0) ?? $0) < (Locale.current.localizedString(forIdentifier: $1) ?? $1) }
            .map { id in
                (id: id, sample: DateFormatterFormatting.format(now, locale: id))
            }
    }()

    private var darkModeBinding: Binding<Bool> {
        Binding(
            get: { model.settings.theme == .dark },
            set: { model.settings.theme = $0 ? .dark : .light }
        )
    }
}

/// $SYS broker statistics. Only shown when a $SYS topic exists. Values that
/// parse as numbers get abbreviated (12.3K).
struct BrokerStatisticsView: View {
    @Bindable var model: AppModel

    private static let stats: [(title: String, topic: String)] = [
        ("Broker", "$SYS/broker/version"),
        ("Sent", "$SYS/broker/bytes/sent"),
        ("Received", "$SYS/broker/bytes/received"),
        ("Clients", "$SYS/broker/clients/total"),
        ("Subscriptions", "$SYS/broker/subscriptions/count"),
        ("Sent 5m", "$SYS/broker/load/bytes/sent/5min"),
        ("Received last 5min", "$SYS/broker/load/bytes/received/5min"),
        ("Memory", "$SYS/broker/heap/current"),
        ("Memory (max)", "$SYS/broker/heap/maximum"),
    ]

    var body: some View {
        if model.tree.node(at: "$SYS") != nil {
            Section("Broker Statistics") {
                ForEach(Self.stats, id: \.topic) { stat in
                    LabeledContent(stat.title) {
                        Text(value(for: stat.topic))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func value(for topic: String) -> String {
        guard let node = model.tree.node(at: topic),
              let payload = node.message?.payload,
              let text = String(data: payload, encoding: .utf8) else {
            return "-"
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Double(trimmed) {
            return NumberAbbreviation.abbreviate(number)
        }
        return trimmed
    }
}
