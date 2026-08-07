import Foundation
import Observation

enum ConnectionPhase: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case error(String)

    var label: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .reconnecting: "Reconnecting…"
        case .error(let message): "Error: \(message)"
        }
    }

    var isActive: Bool {
        switch self {
        case .connected, .reconnecting, .connecting: true
        default: false
        }
    }

    /// Connection health: online / connecting / offline.
    var health: String? {
        switch self {
        case .connected: "online"
        case .connecting, .reconnecting: "connecting"
        case .disconnected, .error: "offline"
        }
    }
}

/// State of the Publish tab.
@Observable
@MainActor
final class PublishState {
    var manualTopic: String?
    var payload: String?
    var retain = false
    var editorMode: EditorMode = .json
    var qos = 0
}

enum EditorMode: String, CaseIterable, Sendable {
    case text
    case xml
    case json

    var label: String {
        switch self {
        case .text: "raw"
        case .xml: "xml"
        case .json: "json"
        }
    }
}

struct ConfirmationRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let continuation: CheckedContinuation<Bool, Never>
}

/// One entry in the Publish-tab history (up to 8, deduplicated on
/// topic+payload).
struct PublishedMessage: Identifiable, Equatable {
    let id = UUID()
    let topic: String
    let payload: String
    let sent = Date()
}

@Observable
@MainActor
final class AppModel {
    // MARK: Connection profiles & settings

    var profiles: [ConnectionProfile] = []
    var selectedProfileId: String?
    var settings = AppSettings() {
        didSet {
            tree.order = settings.topicOrder
            tree.autoExpandLimit = settings.autoExpandLimit
            tree.autoExpandDepth = settings.autoExpandDepth
            tree.filter = settings.topicFilter
        }
    }

    // MARK: Runtime state

    private(set) var phase: ConnectionPhase = .disconnected
    var paused = false
    var aboutVisible = false
    /// Chart panel below the tree: closed by default, auto-opens when charts
    /// appear, closes when the last chart is removed.
    var chartPanelVisible = false
    var error: String?
    var notification: String?
    var pendingConfirmation: ConfirmationRequest?

    let tree = UITreeModel()
    let charts = ChartStore()
    let engine = TopicTreeEngine()
    let manager = MqttClientManager()
    let inbox = MessageInbox(capacity: TopicTreeEngine.maxPending)
    let publish = PublishState()

    private var connectionTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var connectedProfileId: String?

    init() {
        let config = SettingsStore.shared.load()
        // Seed the two demo brokers on first launch.
        profiles = config.connections.isEmpty
            ? ConnectionProfile.makeDefaultConnections()
            : config.connections
        selectedProfileId = config.lastSelectedConnection ?? profiles.first?.id
        settings = config.settings
        tree.order = settings.topicOrder
        tree.autoExpandLimit = settings.autoExpandLimit
        tree.autoExpandDepth = settings.autoExpandDepth
        tree.filter = settings.topicFilter
    }

    var selectedProfile: ConnectionProfile? {
        profiles.first { $0.id == selectedProfileId }
    }

    /// The profile the client is actually attached to, which is not
    /// necessarily the one highlighted in the list.
    var connectedProfile: ConnectionProfile? {
        profiles.first { $0.id == connectedProfileId }
    }

    var selectedNode: UITopicNode? {
        tree.selectedPath.flatMap { tree.node(at: $0) }
    }

    /// Explicitly selected history message to compare against (sidebar).
    var compareMessage: StoredMessage?
    /// Recent publishes, newest first, max 8 (session-only, like the app).
    var publishHistory: [PublishedMessage] = []
    /// Live buffer stats polled while paused ("N changes, buffer at X%").
    var bufferChanges = 0
    var bufferFill = 0.0
    /// Tree totals for the status bar.
    var topicCount = 0
    var messageCount = 0
    var droppedCount = 0
    /// Bumped at most every 400 ms so the details pane reloads its history on
    /// a coarse tick rather than on every message.
    private(set) var historyTick = 0
    @ObservationIgnored private var lastHistoryTick = Date.distantPast
    /// True while messages are still landing, so the status bar can show that
    /// a quiet-looking tree is actually still filling.
    private(set) var receiving = false
    @ObservationIgnored private var idleTask: Task<Void, Never>?

    // MARK: Profile management

    func updateProfile(_ profile: ConnectionProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        saveConfig()
    }

    func addProfile() {
        let profile = ConnectionProfile.makeDefault()
        profiles.append(profile)
        selectedProfileId = profile.id
        saveConfig()
    }

    func deleteProfile(_ id: String) {
        KeychainStore.deletePassword(for: id)
        profiles.removeAll { $0.id == id }
        if selectedProfileId == id {
            selectedProfileId = profiles.first?.id
        }
        saveConfig()
    }

    func savePassword(_ password: String, for profileId: String) {
        KeychainStore.setPassword(password, for: profileId)
    }

    func saveConfig() {
        persistChartState()
        SettingsStore.shared.save(
            PersistedConfig(
                connections: profiles,
                lastSelectedConnection: selectedProfileId,
                settings: settings,
                chartViewStates: chartViewStates
            )
        )
    }

    // MARK: Export / import

    func exportSettings() {
        let payload = PersistedConfig(
            connections: profiles,
            lastSelectedConnection: selectedProfileId,
            settings: settings,
            chartViewStates: chartViewStates
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let text = String(data: data, encoding: .utf8) else {
            showError("Could not encode the settings.")
            return
        }
        FileDialogs.saveText(text, suggestedName: "mqtt-explorer-settings.json")
        AppLog.shared.info("Exported \(profiles.count) profiles")
    }

    func importSettings() {
        guard let file = FileDialogs.openFileData() else { return }
        guard let imported = try? JSONDecoder().decode(PersistedConfig.self, from: file.data) else {
            showError("\(file.name) is not a MQTT Explorer settings file.")
            AppLog.shared.error("Import failed: \(file.name)")
            return
        }

        var merged = profiles
        var added = 0
        for profile in imported.connections where !merged.contains(where: { $0.id == profile.id }) {
            merged.append(profile)
            added += 1
        }
        profiles = merged
        settings = imported.settings
        saveConfig()

        showNotification("Imported \(added) connection\(added == 1 ? "" : "s"). Passwords need re-entering.")
        AppLog.shared.info("Imported \(added) profiles from \(file.name)")
    }

    // MARK: Chart persistence (per connection)

    private(set) var chartViewStates: [String: [ChartParameters]] = [:]

    private func persistChartState() {
        guard let connectionId = connectedProfileId else { return }
        chartViewStates[connectionId] = charts.persistedParameters
    }

    func chartsChanged() {
        persistChartState()
        saveConfig()
    }

    // MARK: Connect / disconnect

    func connect() {
        guard let profile = selectedProfile, !profile.host.isEmpty else { return }
        let password = KeychainStore.password(for: profile.id)

        tree.clear()
        charts.clear()
        paused = false
        phase = .connecting
        connectedProfileId = profile.id
        compareMessage = nil
        topicCount = 0
        messageCount = 0
        droppedCount = 0
        saveConfig()

        // Restore the chart panel for this connection.
        let config = SettingsStore.shared.load()
        chartViewStates = config.chartViewStates
        charts.restore(config.chartViewStates[profile.id] ?? [])
        chartPanelVisible = !charts.series.isEmpty

        connectionTask?.cancel()
        connectionTask = Task {
            // The reset must complete before any message is ingested,
            // otherwise it wipes counts that already landed.
            await engine.reset()
            _ = inbox.drain()
            let stream = await manager.connect(profile: profile, password: password, inbox: inbox)
            startFlushLoop()
            for await event in stream {
                handle(event)
            }
            if case .connected = phase {
                phase = .disconnected
            }
        }
    }

    func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        flushTask?.cancel()
        flushTask = nil
        phase = .disconnected
        connectedProfileId = nil
        settings.topicFilter = ""
        topicCount = 0
        messageCount = 0
        droppedCount = 0
        saveConfig()
        Task {
            await manager.disconnect()
        }
    }

    func shutdown() {
        connectionTask?.cancel()
        flushTask?.cancel()
        saveConfig()
        Task {
            await manager.shutdown()
        }
    }

    private func handle(_ event: MqttClientEvent) {
        switch event {
        case .connecting:
            if phase != .connected { phase = .connecting }
            AppLog.shared.info("Connecting to \(connectedProfile?.host ?? "broker")")
        case .connected:
            phase = .connected
            AppLog.shared.info("Connected")
        case .reconnecting:
            // Unexpected drop after a successful connect.
            showError("Disconnected from server")
            phase = .reconnecting
            AppLog.shared.warning("Connection dropped, reconnecting")
        case .disconnected(let reason):
            phase = .disconnected
            AppLog.shared.info("Disconnected\(reason.map { ": \($0)" } ?? "")")
        case .error(let message):
            phase = .error(message)
            AppLog.shared.error(message)
        }
    }

    /// Every 250 ms, drain the engine into the mirror tree. The merge work
    /// already happened off the main thread.
    private func startFlushLoop() {
        flushTask?.cancel()
        flushTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard phase.isActive else { continue }
                let batch = inbox.drain()
                if !batch.messages.isEmpty || batch.dropped > 0 {
                    await engine.ingest(batch: batch.messages, dropped: batch.dropped)
                }
                guard !paused else { continue }
                _ = await drainEngine()
            }
        }
    }

    @discardableResult
    private func drainEngine() async -> Int {
        let delta = await engine.flush()
        let count = delta.added.count + delta.updated.count + delta.removed.count
        guard count > 0 || delta.droppedMessages > 0 else { return 0 }

        tree.apply(delta)
        for update in delta.added {
            charts.ingest(update: update)
        }
        for update in delta.updated {
            charts.ingest(update: update)
        }
        for path in delta.removed where charts.hasChart(for: path) {
            charts.removeCharts(for: path)
            chartsChanged()
        }
        let counts = await engine.counts()
        topicCount = counts.topics
        messageCount = counts.messages
        droppedCount += delta.droppedMessages

        let now = Date()
        if now.timeIntervalSince(lastHistoryTick) >= 0.4 {
            lastHistoryTick = now
            historyTick += 1
        }
        if !receiving { receiving = true }
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.receiving = false
        }
        return count
    }

    /// Buffer statistics for the pause button ("N changes, buffer at X%").
    func bufferStats() async -> (changes: Int, fillState: Double) {
        let engineStats = await engine.bufferStats()
        let changes = engineStats.changes + inbox.pendingCount
        return (changes, Double(changes) / Double(TopicTreeEngine.maxPending))
    }

    /// Pause/resume the tree updates, with the "Applying recorded changes." /
    /// "Successfully applied N changes." notifications.
    func togglePause() {
        paused.toggle()
        if !paused {
            showNotification("Applying recorded changes.")
            Task {
                let batch = inbox.drain()
                if !batch.messages.isEmpty || batch.dropped > 0 {
                    await engine.ingest(batch: batch.messages, dropped: batch.dropped)
                }
                let count = await drainEngine()
                showNotification("Successfully applied \(count) changes.")
            }
        }
    }

    // MARK: Topic selection

    /// Select a topic. The publish topic follows the selection while the
    /// user hasn't typed anything else.
    func selectTopic(_ path: String) {
        let previous = tree.selectedPath
        guard previous != path else { return }
        if publish.manualTopic == nil || (previous != nil && publish.manualTopic == previous) {
            publish.manualTopic = path
        }
        tree.selectedPath = path
        compareMessage = nil
    }

    func amendPublishHistory(topic: String, payload: String) {
        publishHistory.removeAll { $0.topic == topic && $0.payload == payload }
        publishHistory.insert(PublishedMessage(topic: topic, payload: payload), at: 0)
        if publishHistory.count > 8 {
            publishHistory.removeLast(publishHistory.count - 8)
        }
    }

    // MARK: Errors, notifications, confirmations

    private var notificationTask: Task<Void, Never>?

    /// Errors show 10 seconds, notifications 2 seconds.
    func showError(_ message: String) {
        error = message
        notification = nil
        scheduleDismiss(after: .seconds(10))
    }

    func showNotification(_ message: String) {
        notification = message
        error = nil
        scheduleDismiss(after: .seconds(2))
    }

    private func scheduleDismiss(after duration: Duration) {
        notificationTask?.cancel()
        notificationTask = Task {
            try? await Task.sleep(for: duration)
            if !Task.isCancelled {
                error = nil
                notification = nil
            }
        }
    }

    /// Async confirmation dialog, the native version of
    /// globalActions.requestConfirmation.
    func requestConfirmation(title: String, message: String) async -> Bool {
        await withCheckedContinuation { continuation in
            pendingConfirmation = ConfirmationRequest(
                title: title,
                message: message,
                continuation: continuation
            )
        }
    }

    func resolveConfirmation(_ confirmed: Bool) {
        pendingConfirmation?.continuation.resume(returning: confirmed)
        pendingConfirmation = nil
    }

    // MARK: Publish

    /// Publish the current Publish-tab state. Topic falls back to the
    /// selected topic, exactly like actions/Publish.ts.
    func publishCurrent() {
        let topic = (publish.manualTopic?.isEmpty == false ? publish.manualTopic : nil) ?? tree.selectedPath
        guard let topic, !topic.isEmpty else { return }
        let payloadString = publish.payload ?? ""
        let payload = Data(payloadString.utf8)
        amendPublishHistory(topic: topic, payload: payloadString)
        Task {
            do {
                try await manager.publish(topic: topic, payload: payload, qos: publish.qos, retain: publish.retain)
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    func publish(topic: String, payload: Data, qos: Int, retain: Bool) {
        Task {
            do {
                try await manager.publish(topic: topic, payload: payload, qos: qos, retain: retain)
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    // MARK: Topic deletion (clearTopic.ts)

    /// Delete one topic or a whole subtree by publishing empty retained
    /// payloads. Recursive deletion asks for confirmation first.
    func clearTopic(path: String, recursive: Bool) async {
        let topics = await topicsForDeletion(path: path, recursive: recursive)
        guard !topics.isEmpty else { return }

        if recursive {
            let node = tree.node(at: path)
            let ownMessage = (node?.message?.payload.isEmpty == false) ? 1 : 0
            let childTopics = (node?.childTopicCount ?? 0) - ownMessage
            let childTopicsMessage = childTopics > 0
                ? " and \(childTopics) child \(childTopics == 1 ? "topic" : "topics")"
                : ""
            let confirmed = await requestConfirmation(
                title: "Confirm delete",
                message: """
                Do you want to clear "\(path)"\(childTopicsMessage)?

                This function will send an empty payload (QoS 0, retain) to this and every subtopic, \
                clearing retained topics in the process. Only use this function if you know what you are doing.
                """
            )
            if !confirmed { return }
        }

        // Move the selection away before the node disappears.
        tree.selectNextVisible()

        for (index, topic) in topics.enumerated() {
            if index > 0 {
                try? await Task.sleep(for: .milliseconds(20))
            }
            try? await manager.publish(topic: topic, payload: Data(), qos: 0, retain: true)
        }
    }

    /// Topics that hold messages in the subtree at `path` (inclusive).
    private func topicsForDeletion(path: String, recursive: Bool) async -> [String] {
        if recursive {
            return await engine.messageTopics(in: path)
        }
        let message = await engine.lastMessage(path: path)
        guard let message, !message.payload.isEmpty else { return [] }
        return [path]
    }

    // MARK: History

    /// Newest messages for the details pane. The drawer never shows more than
    /// this, and the diff only needs the previous one.
    static let historyPreviewLimit = 200

    func history(for path: String) async -> [StoredMessage] {
        await engine.history(path: path, limit: Self.historyPreviewLimit)
    }

    /// Seed a freshly added chart with the existing message history of its
    /// topic, then persist the chart panel layout. Adding a chart opens the
    /// chart panel.
    func registerChart(topic: String, dotPath: String?) {
        charts.addChart(path: topic, field: dotPath)
        chartPanelVisible = true
        Task {
            let history = await engine.history(path: topic)
            charts.seed(path: topic, field: dotPath, from: history)
            chartsChanged()
        }
    }

    func removeChart(_ chart: ChartSeries) {
        charts.removeChart(chart)
        if charts.series.isEmpty {
            chartPanelVisible = false
        }
        chartsChanged()
    }

    /// Chart everything measurable at this topic, whether the values arrive as
    /// fields of one JSON payload or as separate child topics. Capped so a
    /// wide branch cannot fill the panel with hundreds of plots.
    static let bulkChartLimit = 12

    @discardableResult
    func chartEverything(at path: String) -> Int {
        guard let node = tree.node(at: path) else { return 0 }
        var added = 0

        if let payload = node.message?.payload {
            for field in ChartStore.plottableFields(in: payload) where added < Self.bulkChartLimit {
                registerChart(topic: path, dotPath: field)
                added += 1
            }
            if added == 0, ChartStore.value(in: payload, field: nil) != nil {
                registerChart(topic: path, dotPath: nil)
                added += 1
            }
        }

        for name in node.childOrder {
            guard added < Self.bulkChartLimit, let child = node.children[name] else { continue }
            guard let payload = child.message?.payload, !payload.isEmpty else { continue }
            if ChartStore.value(in: payload, field: nil) != nil {
                registerChart(topic: child.path, dotPath: nil)
                added += 1
            }
        }

        if added == 0 {
            showNotification("Nothing numeric to chart on this topic.")
        } else if added == Self.bulkChartLimit {
            showNotification("Charted the first \(added) values. Add more one by one.")
        }
        return added
    }
}
