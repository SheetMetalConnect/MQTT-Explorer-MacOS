import SwiftUI
import Charts

/// What a payload can be visualized as, decided from its shape.
enum ValueShape {
    case scalar(Double)
    case fields([(name: String, value: Double)])
    case series([Double])
    case none

    static func of(_ payload: Data) -> ValueShape {
        guard !payload.isEmpty else { return .none }

        if let text = String(data: payload, encoding: .utf8),
           let scalar = Plottable.parseString(text) {
            return .scalar(scalar)
        }

        guard let object = try? JSONSerialization.jsonObject(with: payload) else { return .none }

        if let array = object as? [Any] {
            let values = array.compactMap { Plottable.value($0) }
            return values.count == array.count && values.count > 1 ? .series(values) : .none
        }

        guard let dict = object as? [String: Any] else { return .none }
        let fields = dict.keys.sorted().compactMap { key -> (String, Double)? in
            guard let value = Plottable.value(dict[key]) else { return nil }
            return (key, value)
        }
        return fields.isEmpty ? .none : .fields(fields)
    }

    var isVisualizable: Bool {
        if case .none = self { return false }
        return true
    }
}

/// Auto-visualization of a structured payload: a live line chart for scalars,
/// per-field values with sparklines and a share ring for JSON objects, and a
/// bar chart for numeric arrays.
struct ValueView: View {
    @Bindable var model: AppModel
    let node: UITopicNode
    let history: [StoredMessage]

    var body: some View {
        switch ValueShape.of(node.message?.payload ?? Data()) {
        case .scalar(let value):
            scalarView(value)
        case .fields(let fields):
            FieldsValueView(model: model, node: node, history: history, fields: fields)
        case .series(let values):
            seriesView(values)
        case .none:
            unsupported
        }
    }

    // MARK: Scalar

    private func scalarView(_ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(NumberAbbreviation.abbreviate(value))
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                trendLabel(samples: scalarSamples)
                addToPanelButton(dotPath: nil)
            }
            .animation(.easeOut(duration: 0.2), value: value)

            if scalarSamples.count > 1 {
                trendChart(scalarSamples)
                    .frame(height: 120)
            } else {
                Text("Waiting for more messages to plot a trend.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var scalarSamples: [ChartSample] {
        history.reversed().compactMap { message in
            guard let value = ChartStore.value(in: message.payload, field: nil) else { return nil }
            return ChartSample(date: message.received, value: value)
        }
    }

    // MARK: Numeric array

    private func seriesView(_ values: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(values.count) values")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("min \(NumberAbbreviation.abbreviate(values.min() ?? 0)) · max \(NumberAbbreviation.abbreviate(values.max() ?? 0))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Chart(Array(values.enumerated()), id: \.offset) { index, value in
                BarMark(
                    x: .value("Index", index),
                    y: .value("Value", value)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6))
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(NumberAbbreviation.abbreviate(number))
                        }
                    }
                }
            }
            .frame(height: 150)
        }
    }

    private var unsupported: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("Nothing numeric to visualize")
                .foregroundStyle(.secondary)
            Text("Switch to Raw to inspect the payload.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: Shared pieces

    @ViewBuilder
    private func trendLabel(samples: [ChartSample]) -> some View {
        if let delta = trend(samples) {
            let rising = delta >= 0
            Label(
                NumberAbbreviation.abbreviate(abs(delta)),
                systemImage: rising ? "arrow.up.right" : "arrow.down.right"
            )
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(rising ? Color.green : Color.red)
        }
    }

    private func trend(_ samples: [ChartSample]) -> Double? {
        guard samples.count > 1, let last = samples.last, let previous = samples.dropLast().last else {
            return nil
        }
        let delta = last.value - previous.value
        return delta == 0 ? nil : delta
    }

    private func trendChart(_ samples: [ChartSample]) -> some View {
        Chart(samples, id: \.date) { sample in
            AreaMark(
                x: .value("Time", sample.date),
                y: .value("Value", sample.value)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Time", sample.date),
                y: .value("Value", sample.value)
            )
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.monotone)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: .dateTime.hour().minute().second())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(NumberAbbreviation.abbreviate(number))
                    }
                }
            }
        }
    }

    private func addToPanelButton(dotPath: String?) -> some View {
        Button {
            model.registerChart(topic: node.path, dotPath: dotPath)
        } label: {
            Image(systemName: "chart.xyaxis.line")
        }
        .buttonStyle(.borderless)
        .help("Add to the chart panel")
    }
}

/// JSON object payloads: every numeric field with its own value, sparkline and
/// share of the total.
private struct FieldsValueView: View {
    @Bindable var model: AppModel
    let node: UITopicNode
    let history: [StoredMessage]
    let fields: [(name: String, value: Double)]

    /// A ring only means something when the parts are non-negative and add up
    /// to a whole worth comparing.
    private var showsShare: Bool {
        fields.count > 1 && fields.count <= 8 && fields.allSatisfy { $0.value >= 0 }
            && fields.reduce(0) { $0 + $1.value } > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsShare {
                HStack(alignment: .center, spacing: 20) {
                    shareRing
                    fieldList
                }
            } else {
                fieldList
            }
        }
    }

    private var fieldList: some View {
        VStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.element.name) { index, field in
                if index > 0 { Divider() }
                fieldRow(field)
            }
        }
    }

    private func fieldRow(_ field: (name: String, value: Double)) -> some View {
        let samples = self.samples(for: field.name)
        return HStack(spacing: 10) {
            Circle()
                .fill(color(for: field.name))
                .frame(width: 8, height: 8)
            Text(field.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            if samples.count > 1 {
                sparkline(samples, tint: color(for: field.name))
                    .frame(width: 70, height: 22)
            }
            Text(NumberAbbreviation.abbreviate(field.value))
                .monospacedDigit()
                .contentTransition(.numericText())
            Button {
                model.registerChart(topic: node.path, dotPath: field.name)
            } label: {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .help("Add \(field.name) to the chart panel")
        }
        .padding(.vertical, 5)
        .animation(.easeOut(duration: 0.2), value: field.value)
    }

    private var shareRing: some View {
        let total = fields.reduce(0) { $0 + $1.value }
        return Chart(fields, id: \.name) { field in
            SectorMark(
                angle: .value(field.name, field.value),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(color(for: field.name))
        }
        .chartLegend(.hidden)
        .frame(width: 116, height: 116)
        .overlay {
            VStack(spacing: 0) {
                Text(NumberAbbreviation.abbreviate(total))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text("total")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sparkline(_ samples: [ChartSample], tint: Color) -> some View {
        Chart(samples, id: \.date) { sample in
            LineMark(
                x: .value("Time", sample.date),
                y: .value("Value", sample.value)
            )
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { $0.background(.clear) }
    }

    private func samples(for field: String) -> [ChartSample] {
        history.prefix(40).reversed().compactMap { message in
            guard let value = ChartStore.value(in: message.payload, field: field) else { return nil }
            return ChartSample(date: message.received, value: value)
        }
    }

    /// Stable per-field color so a field keeps its color across updates.
    private func color(for field: String) -> Color {
        let palette = ChartColors.sorted
        var hash: UInt64 = 5381
        for byte in field.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return Color(hex: palette[Int(hash % UInt64(palette.count))].hex)
    }
}
