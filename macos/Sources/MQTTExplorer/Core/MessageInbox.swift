import Foundation
import Synchronization

struct IncomingMessage: Sendable {
    let topic: String
    let payload: Data
    let qos: Int
    let retain: Bool
    let received: Date
}

/// Hand-off between the NIO event loop and the tree actor. The listener
/// appends synchronously so wire order is preserved; the flush loop drains
/// the whole batch in a single actor hop.
final class MessageInbox: Sendable {
    private struct State {
        var messages: [IncomingMessage] = []
        var dropped = 0
    }

    private let state = Mutex(State())
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
    }

    func append(_ message: IncomingMessage) {
        state.withLock { state in
            if state.messages.count >= capacity {
                let drop = max(1, capacity / 10)
                state.messages.removeFirst(drop)
                state.dropped += drop
            }
            state.messages.append(message)
        }
    }

    func drain() -> (messages: [IncomingMessage], dropped: Int) {
        state.withLock { state in
            defer {
                state.messages = []
                state.dropped = 0
            }
            return (state.messages, state.dropped)
        }
    }

    var pendingCount: Int {
        state.withLock { $0.messages.count }
    }
}
