import Foundation

enum MqttProtocolVersion: String, Codable, CaseIterable, Sendable {
    case v3_1_1 = "3.1.1"
    case v5_0 = "5.0"

    var label: String {
        switch self {
        case .v3_1_1: "MQTT 3.1.1"
        case .v5_0: "MQTT 5.0"
        }
    }
}

enum TransportProtocol: String, Codable, CaseIterable, Sendable {
    case mqtt
    case ws

    var label: String {
        switch self {
        case .mqtt: "mqtt"
        case .ws: "ws (WebSocket)"
        }
    }
}

struct SubscriptionConfig: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var topic: String = "#"
    var qos: Int = 0
}

/// A certificate travels with the profile as embedded data (base64 in JSON),
/// not as a file path.
struct CertificateData: Codable, Hashable, Sendable {
    var name: String
    var data: Data

    var isPEM: Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains("-----BEGIN")
    }
}

struct ConnectionProfile: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String = "new connection"
    var host: String = ""
    var port: Int = 1883
    var transport: TransportProtocol = .mqtt
    /// WebSocket URL path, defaults to "/mqtt" when empty
    var basePath: String = ""
    var encryption: Bool = false
    var certValidation: Bool = true
    var username: String = ""
    // The password lives in the Keychain, keyed by profile id.
    var clientId: String = ConnectionProfile.generateClientId()
    var mqttVersion: MqttProtocolVersion = .v5_0
    var subscriptions: [SubscriptionConfig] = [
        SubscriptionConfig(topic: "#", qos: 0),
        SubscriptionConfig(topic: "$SYS/#", qos: 0),
    ]
    var selfSignedCertificate: CertificateData?
    var clientCertificate: CertificateData?
    var clientKey: CertificateData?

    static func generateClientId() -> String {
        let bytes = (0..<4).map { _ in String(format: "%02x", Int.random(in: 0...255)) }
        return "mqtt-explorer-\(bytes.joined())"
    }

    static func makeDefault() -> ConnectionProfile {
        ConnectionProfile()
    }

    /// Public demo brokers, seeded on first launch.
    static func makeDefaultConnections() -> [ConnectionProfile] {
        var eclipse = ConnectionProfile()
        eclipse.id = "mqtt.eclipseprojects.io"
        eclipse.name = "mqtt.eclipseprojects.io"
        eclipse.host = "mqtt.eclipseprojects.io"

        var mosquitto = ConnectionProfile()
        mosquitto.id = "test.mosquitto.org"
        mosquitto.name = "test.mosquitto.org"
        mosquitto.host = "test.mosquitto.org"

        return [eclipse, mosquitto]
    }
}
