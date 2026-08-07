import SwiftUI
import AppKit

@main
struct MQTTExplorerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("MQTT Explorer") {
            ContentView(model: model)
                .frame(minWidth: 940, minHeight: 560)
                .onDisappear {
                    model.shutdown()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(replacing: .appInfo) {
                Button("About MQTT Explorer") {
                    model.aboutVisible = true
                }
            }

            // Find Topic: Cmd-F focuses the tree filter field.
            CommandGroup(after: .toolbar) {
                Button("Find Topic") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            CommandMenu("MQTT") {
                Button(model.paused ? "Resume Updates" : "Pause Updates") {
                    model.togglePause()
                }
                .keyboardShortcut("p", modifiers: [])
                .disabled(!model.phase.isActive)

                Button("Disconnect") {
                    model.disconnect()
                }
                .disabled(!model.phase.isActive)
            }
        }

        // Native Settings window (Cmd-,).
        Settings {
            SettingsView(model: model)
        }
    }
}
