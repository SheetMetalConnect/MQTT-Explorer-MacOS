import SwiftUI

/// One row of a flattened JSON payload.
struct PayloadField: Identifiable, Hashable {
    let path: String
    let value: String
    let kind: Kind

    var id: String { path }

    enum Kind: Hashable {
        case number
        case bool
        case string
        case null
    }

    var depth: Int {
        path.reduce(0) { $1 == "." || $1 == "[" ? $0 + 1 : $0 }
    }

    var leaf: String {
        path.split(whereSeparator: { $0 == "." }).last.map(String.init) ?? path
    }
}

enum PayloadFlattener {
    /// Flatten a JSON payload into dot-path rows. Returns nil when the payload
    /// is not a JSON object or array.
    static func fields(in payload: Data) -> [PayloadField]? {
        guard let object = try? JSONSerialization.jsonObject(with: payload),
              object is [String: Any] || object is [Any] else { return nil }
        var rows: [PayloadField] = []
        walk(object, path: "", into: &rows)
        return rows.isEmpty ? nil : rows
    }

    private static func walk(_ value: Any, path: String, into rows: inout [PayloadField]) {
        switch value {
        case let dict as [String: Any]:
            for key in dict.keys.sorted() {
                walk(dict[key]!, path: path.isEmpty ? key : "\(path).\(key)", into: &rows)
            }
        case let array as [Any]:
            for (index, element) in array.enumerated() {
                walk(element, path: "\(path)[\(index)]", into: &rows)
            }
        case let number as NSNumber:
            if number === kCFBooleanTrue || number === kCFBooleanFalse {
                rows.append(PayloadField(path: path, value: number.boolValue ? "true" : "false", kind: .bool))
            } else {
                rows.append(PayloadField(path: path, value: format(number), kind: .number))
            }
        case let string as String:
            rows.append(PayloadField(path: path, value: string, kind: .string))
        case is NSNull:
            rows.append(PayloadField(path: path, value: "null", kind: .null))
        default:
            rows.append(PayloadField(path: path, value: String(describing: value), kind: .string))
        }
    }

    private static func format(_ number: NSNumber) -> String {
        let double = number.doubleValue
        if double == double.rounded(), abs(double) < 1e15 {
            return String(Int64(double))
        }
        return String(double)
    }
}

/// JSON payloads as a field table: one row per leaf, sorted by path, with the
/// values aligned so they can be scanned in a column.
struct PayloadTableView: View {
    let fields: [PayloadField]
    @Bindable var model: AppModel
    let topic: String

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                if index > 0 { Divider() }
                row(field)
            }
        }
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
    }

    private func row(_ field: PayloadField) -> some View {
        HStack(spacing: 10) {
            Text(field.leaf)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, CGFloat(field.depth) * 12)

            Spacer(minLength: 12)

            Text(field.value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(color(for: field.kind))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            if field.kind == .number || field.kind == .bool {
                Button {
                    model.registerChart(topic: topic, dotPath: field.path)
                } label: {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("Chart \(field.path)")
            } else {
                Color.clear.frame(width: 14, height: 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy value") { Clipboard.copy(field.value) }
            Button("Copy path") { Clipboard.copy(field.path) }
        }
    }

    private func color(for kind: PayloadField.Kind) -> Color {
        switch kind {
        case .number: .blue
        case .bool: .purple
        case .string: .primary
        case .null: .secondary
        }
    }
}
