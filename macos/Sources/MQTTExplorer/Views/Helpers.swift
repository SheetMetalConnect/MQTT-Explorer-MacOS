import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted by the Find menu command (Cmd-F) so the tree filter field can
    /// take focus.
    static let focusSearch = Notification.Name("MQTTExplorerFocusSearch")
}

extension View {
    /// Liquid Glass on macOS 26+, regular material on earlier systems.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// Save some payload text/binary to a user-chosen file (the Save button in the
/// details sidebar and the "Open file" counterpart in Publish).
@MainActor
enum FileDialogs {
    static func saveText(_ text: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func openFileData() -> (name: String, data: Data)? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return nil }
        return (url.lastPathComponent, data)
    }
}

/// Monospace code editor colors: a light dawn-style palette and a dark
/// monokai-style palette for JSON syntax highlighting.
struct CodeBlockColors {
    let text: Color
    let background: Color
    let numeric: Color
    let string: Color
    let variable: Color
    let gutters: Color

    static func current(_ scheme: ColorScheme) -> CodeBlockColors {
        if scheme == .dark {
            CodeBlockColors(
                text: Color(hex: "F8F8F2"),
                background: Color(hex: "272822"),
                numeric: Color(hex: "AE81FF"),
                string: Color(hex: "E6DB74"),
                variable: Color(hex: "A6E22E"),
                gutters: Color(hex: "2F3129")
            )
        } else {
            CodeBlockColors(
                text: Color(hex: "080808"),
                background: Color(hex: "F9F9F9"),
                numeric: Color(hex: "811F24"),
                string: Color(hex: "0B6125"),
                variable: Color(hex: "234A97"),
                gutters: Color(hex: "EBEBEB")
            )
        }
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255
        )
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
