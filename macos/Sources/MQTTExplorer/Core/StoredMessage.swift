import Foundation

/// A received (or to-be-published) MQTT message, value type so it crosses
/// actor boundaries freely.
struct StoredMessage: Sendable, Hashable {
    let payload: Data
    let qos: Int
    let retain: Bool
    let received: Date
    let sequence: Int

    var isEmpty: Bool { payload.isEmpty }
}
