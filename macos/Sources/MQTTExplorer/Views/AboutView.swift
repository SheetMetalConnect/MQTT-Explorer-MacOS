import SwiftUI
import AppKit

/// About dialog.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 20)

            Text("MQTT Explorer")
                .font(.title2.bold())

            Text("Explore your message queues")
                .foregroundStyle(.secondary)

            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 2) {
                Text("Original by Thomas Nordquist")
                Text("macOS version by Luke van Enkhuizen")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 16)
        }
        .frame(width: 300)
        .multilineTextAlignment(.center)
    }
}
