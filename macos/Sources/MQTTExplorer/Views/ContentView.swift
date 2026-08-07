import SwiftUI

/// Main window: toolbar, workspace (tree + charts + sidebar) or the
/// connection setup view, a status footer, notifications and confirmations.
struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if showsWorkspace {
                workspace
            } else {
                ConnectionSetupView(model: model)
            }
        }
        .toolbar { titleBar }
        .navigationTitle("MQTT Explorer")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                notificationBanner
                statusBar
            }
        }
        .alert(
            model.pendingConfirmation?.title ?? "",
            isPresented: Binding(
                get: { model.pendingConfirmation != nil },
                set: { if !$0 { model.resolveConfirmation(false) } }
            )
        ) {
            Button("Yes") { model.resolveConfirmation(true) }
            Button("No", role: .cancel) { model.resolveConfirmation(false) }
        } message: {
            Text(model.pendingConfirmation?.message ?? "")
        }
        .sheet(isPresented: $model.aboutVisible) {
            AboutView()
        }
        .preferredColorScheme(colorScheme)
    }

    /// The connection setup replaces the workspace while not connected.
    private var showsWorkspace: Bool {
        switch model.phase {
        case .connected, .reconnecting: true
        default: false
        }
    }

    private var colorScheme: ColorScheme? {
        switch model.settings.theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var workspace: some View {
        HSplitView {
            VSplitView {
                TopicTreeView(model: model)
                    .frame(minHeight: 120)
                if model.chartPanelVisible {
                    ChartPanelView(model: model)
                        .frame(minHeight: 170)
                }
            }
            SidebarView(model: model)
                .frame(minWidth: 250, idealWidth: 420)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var titleBar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                openSettings()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Settings")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            pauseButton
            if showsWorkspace {
                Button {
                    model.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "network.slash")
                }
                .help("Disconnect from the broker")
            }
            healthIndicator
        }
    }

    private var pauseButton: some View {
        Button {
            model.togglePause()
        } label: {
            if model.paused {
                Label(
                    "\(model.bufferChanges) changes / buffer at \(Int((model.bufferFill * 100).rounded()))%",
                    systemImage: "play.fill"
                )
            } else {
                Image(systemName: "pause.fill")
            }
        }
        .disabled(!model.phase.isActive)
        .help(
            model.paused
                ? "Resumes updating the tree, after applying all recorded changes"
                : "Stops all updates, records changes until the buffer is full."
        )
        .task(id: model.paused) {
            guard model.paused else { return }
            while model.paused && !Task.isCancelled {
                let stats = await model.bufferStats()
                model.bufferChanges = stats.changes
                model.bufferFill = stats.fillState
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Connection health: green online, orange connecting, red offline.
    private var healthColor: Color {
        switch model.phase.health {
        case "online": .green
        case "connecting": .orange
        default: .red
        }
    }

    private var healthIndicator: some View {
        Circle()
            .fill(model.phase.isActive ? healthColor : Color.gray.opacity(0.5))
            .frame(width: 10, height: 10)
            .help(model.phase.label)
    }

    // MARK: Status footer

    private var statusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.phase.isActive ? healthColor : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(model.phase.label)
            if model.phase.isActive, let profile = model.selectedProfile {
                Text("\(profile.host):\(profile.port)")
            }
            Spacer()
            if model.phase.isActive {
                if model.droppedCount > 0 {
                    Label("\(model.droppedCount) dropped", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                        .help("Messages arrived faster than they could be merged. Pause or filter to keep up.")
                }
                Text("\(model.topicCount) topics · \(model.messageCount) messages")
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: Notifications

    @ViewBuilder
    private var notificationBanner: some View {
        if let error = model.error {
            banner(text: error, icon: "exclamationmark.triangle.fill", tint: .red)
        } else if let notification = model.notification {
            banner(text: notification, icon: "checkmark.circle.fill", tint: .green)
        }
    }

    private func banner(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassSurface(cornerRadius: 8)
        .padding(12)
        .transition(.opacity)
    }
}
