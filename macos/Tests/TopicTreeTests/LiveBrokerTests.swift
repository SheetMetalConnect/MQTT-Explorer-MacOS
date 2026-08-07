import XCTest
@testable import MQTTExplorer

/// End-to-end smoke test against a real broker on localhost:1883. Skips
/// itself when no broker is reachable, so `swift test` works anywhere.
final class LiveBrokerTests: XCTestCase {
    private let manager = MqttClientManager()
    private let engine = TopicTreeEngine()
    private let inbox = MessageInbox(capacity: TopicTreeEngine.maxPending)

    override func tearDown() async throws {
        await manager.shutdown()
        try await super.tearDown()
    }

    func testConnectPublishAndRetainedDelete() async throws {
        var profile = ConnectionProfile()
        profile.host = "127.0.0.1"
        profile.port = 1883
        profile.clientId = "mqtt-explorer-smoke-\(UUID().uuidString.prefix(8))"
        profile.subscriptions = [SubscriptionConfig(topic: "#", qos: 0)]

        let stream = await manager.connect(profile: profile, password: nil, inbox: inbox)

        var connected = false
        for await event in stream {
            switch event {
            case .connected:
                connected = true
            case .error(let message):
                throw XCTSkip("No broker on localhost:1883 (\(message))")
            default:
                continue
            }
            if connected { break }
        }
        XCTAssertTrue(connected)

        // 1. A plain publish lands in the tree.
        let topic = "smoke/\(UUID().uuidString.prefix(8))/value"
        try await manager.publish(topic: topic, payload: Data("42".utf8), qos: 0, retain: false)
        let received = try await waitForMessage(at: topic)
        XCTAssertEqual(String(data: received.payload, encoding: .utf8), "42")

        // 2. A retained publish, then an empty retained publish deletes it.
        let retainedTopic = "smoke/\(UUID().uuidString.prefix(8))/retained"
        try await manager.publish(topic: retainedTopic, payload: Data("1".utf8), qos: 0, retain: true)
        _ = try await waitForMessage(at: retainedTopic)

        try await manager.publish(topic: retainedTopic, payload: Data(), qos: 0, retain: true)
        let removed = try await waitForRemoval(of: retainedTopic)
        XCTAssertTrue(removed.contains(retainedTopic))
    }

    /// The saved profiles default to MQTT 5.0, so that path needs its own
    /// coverage: a v5 subscribe returns a different SUBACK type.
    func testConnectsWithMqtt5() async throws {
        let manager = MqttClientManager()
        let inbox = MessageInbox(capacity: 1_000)
        defer { Task { await manager.shutdown() } }

        var profile = ConnectionProfile()
        profile.host = "127.0.0.1"
        profile.port = 1883
        profile.mqttVersion = .v5_0
        profile.clientId = "mqtt-explorer-v5-\(UUID().uuidString.prefix(8))"
        profile.subscriptions = [SubscriptionConfig(topic: "#", qos: 0)]

        let stream = await manager.connect(profile: profile, password: nil, inbox: inbox)
        for await event in stream {
            switch event {
            case .connected:
                return
            case .error(let message):
                throw XCTSkip("No broker on localhost:1883 (\(message))")
            default:
                continue
            }
        }
        XCTFail("MQTT 5.0 connection never reported connected")
    }

    private struct Timeout: Error, CustomStringConvertible {
        let description: String
    }

    private func waitForMessage(at path: String, timeout: TimeInterval = 10) async throws -> StoredMessage {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let batch = inbox.drain()
            await engine.ingest(batch: batch.messages, dropped: batch.dropped)
            let delta = await engine.flush()
            for update in delta.added + delta.updated where update.path == path {
                if let message = update.message, !message.payload.isEmpty {
                    return message
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Timeout(description: "Message on \(path) never arrived within \(timeout)s")
    }

    private func waitForRemoval(of path: String, timeout: TimeInterval = 10) async throws -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let batch = inbox.drain()
            await engine.ingest(batch: batch.messages, dropped: batch.dropped)
            let delta = await engine.flush()
            if delta.removed.contains(path) {
                return delta.removed
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Timeout(description: "Removal of \(path) never arrived within \(timeout)s")
    }
}
