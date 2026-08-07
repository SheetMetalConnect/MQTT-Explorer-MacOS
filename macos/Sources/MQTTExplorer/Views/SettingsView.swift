import SwiftUI

/// The Settings window (Cmd-,): behavior on one tab, live broker numbers on
/// another, so neither becomes a wall of controls.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            statistics
                .tabItem { Label("Broker", systemImage: "chart.bar") }
            DiagnosticsView(model: model)
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .frame(width: 460)
        .onChange(of: model.settings) {
            model.saveConfig()
        }
    }

    private var statistics: some View {
        Form {
            BrokerStatisticsView(model: model)
        }
        .formStyle(.grouped)
        .frame(height: 420)
    }

    private var general: some View {
        Form {
            Section("Tree") {
                Picker("Auto expand", selection: $model.settings.autoExpandLimit) {
                    Text("Nothing").tag(0)
                    Text("Narrow branches, up to 2 children").tag(2)
                    Text("Up to 5 children").tag(5)
                    Text("Up to 15 children").tag(15)
                    Text("Up to 30 children").tag(30)
                    Text("Everything").tag(1_000_000)
                }
                .help("Branches wider than this stay closed, so a busy namespace does not unfold on its own.")

                Picker("Expand no deeper than", selection: $model.settings.autoExpandDepth) {
                    Text("1 level").tag(1)
                    Text("2 levels").tag(2)
                    Text("3 levels").tag(3)
                    Text("5 levels").tag(5)
                    Text("Any depth").tag(64)
                }
                .disabled(model.settings.autoExpandLimit == 0)
                .help("A depth cap keeps deep namespaces readable even when every branch is narrow.")

                Picker("Topic Order", selection: $model.settings.topicOrder) {
                    ForEach(TopicOrder.allCases, id: \.self) { order in
                        Text(order.label).tag(order)
                    }
                }
            }

            Section("Payloads") {
                Toggle("Show value types", isOn: $model.settings.showValueTypes)
                    .help("Marks what each payload holds: {} object, [] array, # number, Aa text, hex binary")

                Toggle("Highlight data contracts", isOn: $model.settings.highlightDataContracts)
                    .help("Tints topic segments starting with an underscore, the UNS convention for _historian and similar")
            }

            Section("Display") {
                Picker("Time locale", selection: $model.settings.timeLocale) {
                    ForEach(Self.localeSamples, id: \.id) { entry in
                        Text("\(entry.id)  (\(entry.sample))").tag(entry.id)
                    }
                }

                Toggle("Blink on new messages", isOn: $model.settings.highlightTopicUpdates)

                Toggle("Select topics on hover", isOn: $model.settings.selectTopicWithMouseOver)

                Picker("Appearance", selection: $model.settings.theme) {
                    Text("Auto").tag(ThemeChoice.system)
                    Text("Light").tag(ThemeChoice.light)
                    Text("Dark").tag(ThemeChoice.dark)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .frame(height: 420)
    }

    /// Only the locales anyone picks here, rather than every identifier on the
    /// machine, each of which would need its own formatter built.
    private static let localeSamples: [(id: String, sample: String)] = {
        let now = Date()
        let common = [
            "nl_NL", "nl_BE", "de_DE", "de_AT", "en_GB", "en_US",
            "fr_FR", "es_ES", "it_IT", "pt_PT", "sv_SE", "da_DK",
            "nb_NO", "fi_FI", "pl_PL", "cs_CZ", "ja_JP", "zh_Hans",
        ]
        var ids = common
        let current = Locale.current.identifier
        if !ids.contains(current) { ids.insert(current, at: 0) }
        return ids.map { (id: $0, sample: DateFormatterFormatting.format(now, locale: $0)) }
    }()

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
