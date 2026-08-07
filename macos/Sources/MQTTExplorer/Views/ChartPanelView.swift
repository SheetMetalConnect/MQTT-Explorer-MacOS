import SwiftUI
import Charts

/// Chart color palette, ordered so successive colors differ as much as
/// possible.
enum ChartColors {
    private static let raw: [(name: String, hex: String)] = [
        ("brown", "BCAAA4"), ("brown", "795548"), ("brown", "5D4037"),
        ("blueGrey", "B0BEC5"), ("blueGrey", "607D8B"), ("blueGrey", "455A64"),
        ("amber", "FFE082"), ("amber", "FFC107"), ("amber", "FFA000"),
        ("orange", "FFCC80"), ("orange", "FF9800"), ("orange", "F57C00"),
        ("pink", "F48FB1"), ("pink", "E91E63"), ("pink", "C2185B"),
        ("purple", "CE93D8"), ("purple", "9C27B0"), ("purple", "7B1FA2"),
        ("deepPurple", "B39DDB"), ("deepPurple", "673AB7"), ("deepPurple", "512DA8"),
        ("teal", "80CBC4"), ("teal", "009688"), ("teal", "00796B"),
        ("red", "EF9A9A"), ("red", "F44336"), ("red", "D32F2F"),
        ("green", "A5D6A7"), ("green", "4CAF50"), ("green", "388E3C"),
        ("lime", "E6EE9C"), ("lime", "CDDC39"), ("lime", "AFB42B"),
        ("indigo", "9FA8DA"), ("indigo", "3F51B5"), ("indigo", "303F9F"),
        ("yellow", "FFF59D"), ("yellow", "FFEB3B"), ("yellow", "FBC02D"),
    ]

    static let sorted: [(name: String, hex: String)] = {
        var remaining = raw
        var result: [(String, String)] = []
        var previous: (Double, Double, Double)?
        while !remaining.isEmpty {
            let pick: (String, String)
            if let previous {
                pick = remaining.max { lhs, rhs in
                    distance(lhs.1, previous) < distance(rhs.1, previous)
                }!
            } else {
                pick = remaining[0]
            }
            result.append(pick)
            previous = rgb(pick.1)
            remaining.removeAll { $0.1 == pick.1 }
        }
        return result.map { (name: $0.0, hex: $0.1) }
    }()

    /// Default line color (indigo).
    static let defaultHex = "3F51B5"

    private static func rgb(_ hex: String) -> (Double, Double, Double) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        return (
            Double((value & 0xFF0000) >> 16),
            Double((value & 0x00FF00) >> 8),
            Double(value & 0x0000FF)
        )
    }

    private static func distance(_ hex: String, _ other: (Double, Double, Double)) -> Double {
        let (r, g, b) = rgb(hex)
        return (r - other.0) * (r - other.0) + (g - other.1) * (g - other.1) + (b - other.2) * (b - other.2)
    }
}

/// The chart panel below the tree. Charts are laid out on a 12 column grid,
/// each chart choosing 4/6/12 columns.
struct ChartPanelView: View {
    @Bindable var model: AppModel

    private var spacingUnits: Int {
        let count = model.charts.series.count
        if count >= 5 { return 4 }
        if count >= 2 { return 6 }
        return 12
    }

    /// Grid units (out of 12) a chart occupies.
    private func columnWidth(_ chart: ChartSeries) -> Int {
        switch chart.parameters.width {
        case .big: return 12
        case .medium: return 6
        case .small: return 4
        case nil: return spacingUnits
        }
    }

    /// Pack the charts into rows of 12 columns.
    private var packedRows: [[ChartSeries]] {
        var rows: [[ChartSeries]] = []
        var current: [ChartSeries] = []
        var used = 0
        for chart in model.charts.series {
            let width = columnWidth(chart)
            if used + width > 12, !current.isEmpty {
                rows.append(current)
                current = []
                used = 0
            }
            current.append(chart)
            used += width
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.charts.series.isEmpty {
                noCharts
            } else {
                chartGrid
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("Charts")
                .font(.headline)
            Spacer()
            Button {
                model.chartPanelVisible = false
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Close the chart panel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var chartGrid: some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                VStack(spacing: CGFloat(spacingUnits) * 2) {
                    ForEach(Array(packedRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: CGFloat(spacingUnits) * 2) {
                            ForEach(row) { chart in
                                TopicChartView(model: model, chart: chart)
                                    .frame(
                                        width: (geo.size.width - CGFloat(spacingUnits) * 2 * CGFloat(row.count + 1))
                                            * CGFloat(columnWidth(chart)) / 12
                                    )
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, CGFloat(spacingUnits))
                    }
                }
                .padding(.vertical, CGFloat(spacingUnits))
            }
        }
    }

    private var noCharts: some View {
        VStack(spacing: 6) {
            Text("No charts selected")
                .font(.headline)
            Text("Select a numeric values from the value preview.")
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text("Click on")
                Image(systemName: "chart.xyaxis.line")
                Text("to add a topic / value to this panel.")
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One chart card: title, pause/settings/remove actions and the Swift Charts
/// plot (150px high, 5 y ticks, 4 x ticks).
struct TopicChartView: View {
    @Bindable var model: AppModel
    let chart: ChartSeries

    @State private var hoveredSample: ChartSample?
    @State private var settingsPopover: SettingsPopover?

    enum SettingsPopover: Identifiable {
        case yAxis
        case xAxis

        var id: String {
            switch self {
            case .yAxis: "yAxis"
            case .xAxis: "xAxis"
            }
        }
    }

    private static let chartHeight: CGFloat = 150

    private var lineColor: Color {
        Color(hex: chart.parameters.color ?? ChartColors.defaultHex)
    }

    private var interpolationMethod: InterpolationMethod {
        switch chart.parameters.interpolation ?? .curve {
        case .curve: .monotone
        case .linear: .linear
        case .cubicBasisSpline: .cardinal
        case .stepAfter: .stepEnd
        case .stepBefore: .stepStart
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            chartBody
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                if let dotPath = chart.parameters.dotPath {
                    Text(dotPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(chart.key.path)
                        .font(.caption)
                        .lineLimit(1)
                } else {
                    Text(chart.key.path)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                model.charts.togglePause(chart)
            } label: {
                Image(systemName: chart.paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .help(chart.paused ? "Resume chart" : "Pause chart")

            Menu {
                settingsMenu
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 10))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Chart settings")
            .popover(item: $settingsPopover) { popover in
                switch popover {
                case .yAxis: yAxisSettings
                case .xAxis: xAxisSettings
                }
            }

            Button {
                model.removeChart(chart)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .help("Remove chart")
        }
    }

    @ViewBuilder
    private var chartBody: some View {
        let samples = chart.displaySamples
        if samples.isEmpty {
            Text("No Data")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: Self.chartHeight)
        } else {
            plot(samples)
                .frame(height: Self.chartHeight)
        }
    }

    private func plot(_ samples: [ChartSample]) -> some View {
        Chart(samples, id: \.date) { sample in
            LineMark(
                x: .value("Time", sample.date),
                y: .value("Value", sample.value)
            )
            .interpolationMethod(interpolationMethod)
            .foregroundStyle(lineColor)
            .lineStyle(StrokeStyle(lineWidth: 2))

            PointMark(
                x: .value("Time", sample.date),
                y: .value("Value", sample.value)
            )
            .foregroundStyle(lineColor)
            .symbolSize(28)
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(NumberAbbreviation.abbreviate(number))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.hour().minute().second())
            }
        }
        .chartYScale(domain: yDomain(for: samples))
        .chartXScale(domain: xDomain(for: samples))
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoveredSample = nearestSample(at: location, proxy: proxy, geo: geo, samples: samples)
                        case .ended:
                            hoveredSample = nil
                        }
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            if let sample = hoveredSample {
                tooltip(for: sample)
            }
        }
    }

    private func yDomain(for samples: [ChartSample]) -> ClosedRange<Double> {
        let values = samples.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let from = chart.parameters.rangeFrom
        let to = chart.parameters.rangeTo
        if from == nil && to == nil {
            return minValue == maxValue ? (minValue - 1)...(maxValue + 1) : minValue...maxValue
        }
        return (from ?? minValue)...(to ?? maxValue)
    }

    private func xDomain(for samples: [ChartSample]) -> ClosedRange<Date> {
        let dates = samples.map(\.date)
        let minDate = dates.min() ?? Date()
        let maxDate = dates.max() ?? Date()
        if let until = chart.parameters.timeRangeUntil,
           let seconds = DurationParser.seconds(until) {
            let now = Date()
            return now.addingTimeInterval(-seconds)...now
        }
        return minDate == maxDate ? minDate.addingTimeInterval(-1)...maxDate.addingTimeInterval(1) : minDate...maxDate
    }

    private func nearestSample(
        at location: CGPoint,
        proxy: ChartProxy,
        geo: GeometryProxy,
        samples: [ChartSample]
    ) -> ChartSample? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let origin = geo[plotFrame].origin
        let x = location.x - origin.x
        guard let date: Date = proxy.value(atX: x) else { return nil }
        return samples.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }

    private func tooltip(for sample: ChartSample) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Time: \(DateFormatterFormatting.format(sample.date, locale: model.settings.timeLocale))")
            Text("Value: \(NumberAbbreviation.abbreviate(sample.value))")
            Text("Raw: \(sample.value)")
        }
        .font(.caption2)
        .padding(6)
        .glassSurface(cornerRadius: 4)
        .padding(4)
    }

    // MARK: Settings menu

    @ViewBuilder
    private var settingsMenu: some View {
        Button("Y-Axis range (Values)") { settingsPopover = .yAxis }
        Button("X-Axis range (Time)") { settingsPopover = .xAxis }

        Menu("Curve interpolation") {
            Picker("Curve interpolation", selection: interpolationBinding) {
                Text("curve").tag(ChartInterpolation.curve)
                Text("linear").tag(ChartInterpolation.linear)
                Text("step after").tag(ChartInterpolation.stepAfter)
                Text("step before").tag(ChartInterpolation.stepBefore)
                Text("cubic basis spline").tag(ChartInterpolation.cubicBasisSpline)
            }
        }

        Menu("Size") {
            Picker("Size", selection: widthBinding) {
                Text("auto").tag(ChartWidth?.none)
                Text("100% width").tag(ChartWidth?.some(.big))
                Text("50% width").tag(ChartWidth?.some(.medium))
                Text("33% width").tag(ChartWidth?.some(.small))
            }
        }

        Menu("Color") {
            Button {
                mutate { $0.color = nil }
            } label: {
                if chart.parameters.color == nil {
                    Label("default", systemImage: "checkmark")
                } else {
                    Text("default")
                }
            }
            Divider()
            ForEach(ChartColors.sorted, id: \.hex) { entry in
                Button {
                    mutate { $0.color = entry.hex }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: entry.hex))
                            .frame(width: 10, height: 10)
                        Text(entry.name)
                        if chart.parameters.color == entry.hex {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Divider()
        Button("Clear data") {
            model.charts.clearData(chart)
            model.chartsChanged()
        }
        Button("Move up") {
            model.charts.moveUp(topic: chart.key.path, dotPath: chart.key.field)
            model.chartsChanged()
        }
    }

    private var interpolationBinding: Binding<ChartInterpolation> {
        Binding(
            get: { chart.parameters.interpolation ?? .curve },
            set: { value in mutate { $0.interpolation = value } }
        )
    }

    private var widthBinding: Binding<ChartWidth?> {
        Binding(
            get: { chart.parameters.width },
            set: { value in mutate { $0.width = value } }
        )
    }

    private func mutate(_ change: @escaping (inout ChartParameters) -> Void) {
        model.charts.updateChart(topic: chart.key.path, dotPath: chart.key.field, mutate: change)
        model.chartsChanged()
    }

    // MARK: Axis range popovers

    private var yAxisSettings: some View {
        YAxisSettingsView(model: model, chart: chart)
    }

    private var xAxisSettings: some View {
        XAxisSettingsView(model: model, chart: chart)
    }
}

private struct YAxisSettingsView: View {
    @Bindable var model: AppModel
    let chart: ChartSeries
    @State private var from: String = ""
    @State private var to: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Define custom ranges for the Y-Axis")
                .font(.headline)
            HStack {
                Text("from")
                TextField("from", text: $from)
                    .frame(width: 100)
            }
            HStack {
                Text("to")
                TextField("to", text: $to)
                    .frame(width: 100)
            }
            Button("Apply") {
                model.charts.updateChart(topic: chart.key.path, dotPath: chart.key.field) { parameters in
                    parameters.rangeFrom = Double(from)
                    parameters.rangeTo = Double(to)
                }
                model.chartsChanged()
            }
        }
        .padding(12)
        .frame(width: 240)
        .onAppear {
            from = chart.parameters.rangeFrom.map { String($0) } ?? ""
            to = chart.parameters.rangeTo.map { String($0) } ?? ""
        }
    }
}

private struct XAxisSettingsView: View {
    @Bindable var model: AppModel
    let chart: ChartSeries
    @State private var custom: String = ""

    private let presets = ["10s", "30s", "1m", "5m", "15m", "1h", "6h", "1d"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chart data within a time interval")
                .font(.headline)
            HStack(spacing: 4) {
                presetButton("all", value: nil)
                ForEach(presets, id: \.self) { preset in
                    presetButton(preset, value: preset)
                }
            }
            HStack {
                Text("interval")
                TextField("e.g. 1h30m", text: $custom)
                    .frame(width: 100)
                Button("Apply") {
                    apply(custom.isEmpty ? nil : custom)
                }
            }
            Text("Limited to 500 data points")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 340)
        .onAppear {
            custom = chart.parameters.timeRangeUntil ?? ""
        }
    }

    private func presetButton(_ label: String, value: String?) -> some View {
        Button(label) {
            custom = value ?? ""
            apply(value)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func apply(_ value: String?) {
        model.charts.updateChart(topic: chart.key.path, dotPath: chart.key.field) { parameters in
            parameters.timeRangeUntil = value
        }
        model.chartsChanged()
    }
}
