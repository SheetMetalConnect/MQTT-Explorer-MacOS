import XCTest
@testable import MQTTExplorer

/// Drives the same path the Connect button does, which the manager-level
/// tests bypass.
@MainActor
final class AppModelConnectTests: XCTestCase {
    private var savedConfig: Data?

    /// AppModel persists to the real settings file, so the user's own
    /// connections have to be put back afterwards.
    override func setUp() async throws {
        savedConfig = try? Data(contentsOf: Self.configURL)
    }

    override func tearDown() async throws {
        if let savedConfig {
            try? savedConfig.write(to: Self.configURL)
        }
    }

    private static var configURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MQTT Explorer/settings.json")
    }

    func testConnectReachesConnectedAndReceivesMessages() async throws {
        let model = AppModel()

        var profile = ConnectionProfile()
        profile.id = "test-local"
        profile.name = "local"
        profile.host = "127.0.0.1"
        profile.port = 1883
        profile.clientId = "appmodel-\(UUID().uuidString.prefix(8))"
        profile.subscriptions = [SubscriptionConfig(topic: "#", qos: 0)]

        model.profiles = [profile]
        model.selectedProfileId = profile.id
        model.connect()

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if case .connected = model.phase { break }
            if case .error(let message) = model.phase {
                throw XCTSkip("No broker on localhost:1883 (\(message))")
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        guard case .connected = model.phase else {
            return XCTFail("never connected, phase is \(model.phase.label)")
        }

        model.publish(topic: "appmodel/probe", payload: Data("7".utf8), qos: 0, retain: false)

        let messageDeadline = Date().addingTimeInterval(10)
        while Date() < messageDeadline, model.tree.node(at: "appmodel/probe") == nil {
            try await Task.sleep(for: .milliseconds(100))
        }

        XCTAssertNotNil(model.tree.node(at: "appmodel/probe"), "message never reached the tree")

        // Counts land on the drain after the tree does, so wait for that tick.
        let countDeadline = Date().addingTimeInterval(5)
        while Date() < countDeadline, model.topicCount == 0 {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertGreaterThan(model.topicCount, 0, "status bar counts never updated")
        model.disconnect()
    }
}
