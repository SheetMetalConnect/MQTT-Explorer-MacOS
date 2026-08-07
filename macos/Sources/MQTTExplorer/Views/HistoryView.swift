import SwiftUI
import Charts

/// The message history drawer inside the details tab. Newest first; clicking
/// a message selects it as the compare message, plottable payloads get a
/// chart icon.
struct HistoryView: View {
    @Bindable var model: AppModel
    let topic: String
    let history: [StoredMessage]

    @State private var open = false
    @State private var expanded: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                open.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                    Text("History")
                        .font(.headline)
                    Text("\(history.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(history.enumerated()), id: \.element.sequence) { index, message in
                            historyRow(index: index, message: message)
                        }
                    }
                }
                .frame(maxHeight: 230)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .underPageBackgroundColor),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    private func historyRow(index: Int, message: StoredMessage) -> some View {
        let isSelected = model.compareMessage == message
        let isExpanded = expanded.contains(message.sequence)
        let plottable = ChartStore.value(in: message.payload, field: nil) != nil

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(title(for: index))
                    .font(.caption)
                    .lineLimit(1)
                Text("#\(message.sequence)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                Button {
                    if let text = String(data: message.payload, encoding: .utf8) {
                        Clipboard.copy(text)
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("Copy message")

                if plottable {
                    Button {
                        model.registerChart(topic: topic, dotPath: nil)
                    } label: {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("Add to chart panel")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelected {
                    model.compareMessage = nil
                    expanded.remove(message.sequence)
                } else {
                    model.compareMessage = message
                    expanded.insert(message.sequence)
                }
            }

            if isExpanded {
                PayloadView(payload: message.payload)
                if plottable {
                    sparkline(upTo: index)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// "date time (-interval to the next newer message)".
    private func title(for index: Int) -> String {
        let message = history[index]
        var text = DateFormatterFormatting.format(message.received, locale: model.settings.timeLocale)
        if index > 0 {
            let newer = history[index - 1]
            text += " (-\(DateFormatterFormatting.interval(from: message.received, to: newer.received)))"
        }
        return text
    }

    /// Small preview plot of the plottable values around this message.
    private func sparkline(upTo index: Int) -> some View {
        let window = history[index..<min(index + 20, history.count)]
        let samples = window.reversed().compactMap { message -> ChartSample? in
            guard let value = ChartStore.value(in: message.payload, field: nil) else { return nil }
            return ChartSample(date: message.received, value: value)
        }
        return Chart(samples, id: \.date) { sample in
            LineMark(x: .value("Time", sample.date), y: .value("Value", sample.value))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 40)
        .padding(.vertical, 2)
    }
}
