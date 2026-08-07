import SwiftUI

/// Main window: toolbar, workspace (tree + charts + sidebar) or the
/// connection setup view, plus notifications and confirmations.
struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @FocusState private var searchFocused: Bool

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
        .overlay(alignment: .bottomLeading) {
            notificationBanner
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
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            searchFocused = true
        }
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

        ToolbarItem(placement: .principal) {
            searchBar
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

    private var searchBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search…", text: $model.settings.topicFilter)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .disabled(!model.phase.isActive)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
        .frame(minWidth: 160, maxWidth: 320)
        .onChange(of: model.phase.isActive) { _, active in
            searchFocused = active
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
    private var healthIndicator: some View {
        let color: Color = switch model.phase.health {
        case "online": .green
        case "connecting": .orange
        default: .red
        }
        return Circle()
            .fill(model.phase.isActive ? color : Color.gray.opacity(0.5))
            .frame(width: 10, height: 10)
            .help(model.phase.label)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.gray.opacity(0.2))
        )
        .padding(12)
        .transition(.opacity)
    }
}
