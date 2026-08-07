import Foundation

/// One entry in a TreeDelta describing the new state of a topic node.
struct NodeUpdate: Sendable {
    let path: String
    let messageCount: Int
    let lastUpdate: Date
    let message: StoredMessage?
    let childCount: Int
    let leafMessageCount: Int
    let childTopicCount: Int
}

/// Changes produced by merging a batch of MQTT messages into the tree.
struct TreeDelta: Sendable {
    var added: [NodeUpdate] = []
    var updated: [NodeUpdate] = []
    var removed: [String] = []
    var droppedMessages: Int = 0
}

/// Ring buffer with a fixed capacity, oldest entries evicted first.
struct RingBuffer<Element> {
    private var storage: [Element?]
    private var head = 0
    private(set) var count = 0

    init(capacity: Int) {
        storage = Array(repeating: nil, count: Swift.max(1, capacity))
    }

    mutating func add(_ element: Element) {
        let index = (head + count) % storage.count
        if count == storage.count {
            // Full: overwrite oldest
            storage[head] = element
            head = (head + 1) % storage.count
        } else {
            storage[index] = element
            count += 1
        }
    }

    /// Newest first.
    func newestFirst() -> [Element] {
        var result: [Element] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            let index = (head + count - 1 - i) % storage.count
            if let element = storage[index] {
                result.append(element)
            }
        }
        return result
    }
}

/// Off-main-thread topic tree:
/// - topics split on "/" into edges
/// - per-node message count, last update, message history
/// - an empty payload on an empty leaf removes the node (retained-topic
///   deletion), cascading upwards through parents that become empty leaves
/// - payloads above maxPayload are truncated
actor TopicTreeEngine {
    final class Node {
        let name: String
        unowned var parent: Node?
        var children: [String: Node] = [:]
        var childOrder: [String] = []
        var message: StoredMessage?
        var messageCount = 0
        var lastUpdate = Date()
        var history = RingBuffer<StoredMessage>(capacity: Node.historyCapacity)
        var markedAdded = false
        var markedUpdated = false
        var cachedLeafMessageCount = 0
        var cachedChildTopicCount = 0
        var countsDirty = true

        static let historyCapacity = 2000

        init(name: String, parent: Node?) {
            self.name = name
            self.parent = parent
        }

        var hasMessageData: Bool {
            guard let message else { return false }
            return !message.payload.isEmpty
        }

        var isLeaf: Bool { children.isEmpty }

        var path: String {
            var parts: [String] = []
            var node: Node? = self
            while let current = node, current.parent != nil {
                parts.append(current.name)
                node = current.parent
            }
            return parts.reversed().joined(separator: "/")
        }

        func invalidateCountsUpwards() {
            var node: Node? = self
            while let current = node {
                if current.countsDirty { break }
                current.countsDirty = true
                node = current.parent
            }
        }

        /// Message count of this node and all descendants (cached).
        func leafMessageCount() -> Int {
            recomputeCountsIfNeeded()
            return cachedLeafMessageCount
        }

        /// Number of topics (nodes with a message) in this subtree (cached).
        func childTopicCount() -> Int {
            recomputeCountsIfNeeded()
            return cachedChildTopicCount
        }

        private func recomputeCountsIfNeeded() {
            guard countsDirty else { return }
            var leaf = messageCount
            var topics = hasMessageData ? 1 : 0
            for name in childOrder {
                if let child = children[name] {
                    leaf += child.leafMessageCount()
                    topics += child.childTopicCount()
                }
            }
            cachedLeafMessageCount = leaf
            cachedChildTopicCount = topics
            countsDirty = false
        }

        /// All descendant topics (and self) that currently hold message data.
        func topicsWithMessages() -> [String] {
            var result: [String] = []
            if hasMessageData, !path.isEmpty {
                result.append(path)
            }
            for name in childOrder {
                if let child = children[name] {
                    result.append(contentsOf: child.topicsWithMessages())
                }
            }
            return result
        }
    }

    /// Payloads above this size are truncated.
    static let maxPayload = 20_000
    /// Cap for the pending buffer while the UI is paused; oldest dropped first.
    static let maxPending = 200_000

    private let root = Node(name: "", parent: nil)
    private var pending: [(topic: String, message: StoredMessage)] = []
    private var sequence = 0
    private var droppedMessages = 0

    /// Called from the MQTT event loop (via a Task per message).
    func ingest(topic: String, payload: Data, qos: Int, retain: Bool) {
        let truncated = payload.count > Self.maxPayload ? payload.prefix(Self.maxPayload) : payload
        let message = StoredMessage(
            payload: Data(truncated),
            qos: qos,
            retain: retain,
            received: Date(),
            sequence: sequence
        )
        sequence += 1
        if pending.count >= Self.maxPending {
            pending.removeFirst(pending.count / 10)
            droppedMessages += pending.count / 10
        }
        pending.append((topic, message))
    }

    /// Merge everything ingested since the last flush into the tree.
    func flush() -> TreeDelta {
        var delta = TreeDelta()
        delta.droppedMessages = droppedMessages
        droppedMessages = 0

        let batch = pending
        pending.removeAll(keepingCapacity: true)

        var removedPaths = Set<String>()

        for (topic, message) in batch {
            let node = nodeFor(topic: topic, created: &delta)
            applyMessage(message, to: node)

            if !node.hasMessageData && node.isLeaf, node.parent != nil {
                remove(node: node, removedPaths: &removedPaths)
            }
        }

        // Resolve marks into the delta. Nodes added and removed within the
        // same batch cancel out.
        collectMarks(from: root, delta: &delta, removedPaths: removedPaths)
        clearMarks(from: root)

        delta.removed = removedPaths.sorted()
        return delta
    }

    /// Fill state of the pending-message buffer, for the pause button label
    /// ("N changes, buffer at X%").
    func bufferStats() -> (changes: Int, fillState: Double) {
        (pending.count, Double(pending.count) / Double(Self.maxPending))
    }

    /// Total topics and messages in the tree, for the status bar.
    func counts() -> (topics: Int, messages: Int) {
        var topics = 0
        var messages = 0
        var stack = [root]
        while let node = stack.popLast() {
            for name in node.childOrder {
                guard let child = node.children[name] else { continue }
                topics += 1
                messages += child.messageCount
                stack.append(child)
            }
        }
        return (topics, messages)
    }

    func reset() {
        root.children.removeAll()
        root.childOrder.removeAll()
        root.message = nil
        root.messageCount = 0
        root.history = RingBuffer(capacity: Node.historyCapacity)
        pending.removeAll()
        sequence = 0
        droppedMessages = 0
    }

    func history(path: String) -> [StoredMessage] {
        guard let node = find(path: path) else { return [] }
        return node.history.newestFirst()
    }

    func lastMessage(path: String) -> StoredMessage? {
        find(path: path)?.message
    }

    /// Topics with message data in the subtree at `path` (inclusive).
    /// Used for recursive topic deletion.
    func messageTopics(in path: String) -> [String] {
        guard let node = find(path: path) else { return [] }
        return node.topicsWithMessages()
    }

    // MARK: - Merge internals

    private func nodeFor(topic: String, created: inout TreeDelta) -> Node {
        var current = root
        for segment in topic.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            if let child = current.children[segment] {
                current = child
            } else {
                let child = Node(name: segment, parent: current)
                child.markedAdded = true
                current.children[segment] = child
                current.childOrder.append(segment)
                child.invalidateCountsUpwards()
                current = child
            }
        }
        return current
    }

    private func applyMessage(_ message: StoredMessage, to node: Node) {
        node.history.add(message)
        node.message = message
        node.messageCount += 1
        node.lastUpdate = message.received
        node.markedUpdated = true
        node.invalidateCountsUpwards()
    }

    private func remove(node: Node, removedPaths: inout Set<String>) {
        var current: Node? = node
        while let node = current, let parent = node.parent {
            let path = node.path
            parent.children.removeValue(forKey: node.name)
            parent.childOrder.removeAll { $0 == node.name }
            parent.markedUpdated = true
            parent.invalidateCountsUpwards()
            removedPaths.insert(path)
            // Cascade: parent that became an empty leaf goes too.
            if parent.parent != nil, !parent.hasMessageData, parent.isLeaf {
                current = parent
            } else {
                current = nil
            }
        }
    }

    private func collectMarks(from node: Node, delta: inout TreeDelta, removedPaths: Set<String>) {
        for name in node.childOrder {
            guard let child = node.children[name] else { continue }
            let path = child.path
            if removedPaths.contains(path) {
                continue
            }
            if child.markedAdded {
                delta.added.append(update(for: child))
            } else if child.markedUpdated {
                delta.updated.append(update(for: child))
            }
            collectMarks(from: child, delta: &delta, removedPaths: removedPaths)
        }
    }

    private func clearMarks(from node: Node) {
        node.markedAdded = false
        node.markedUpdated = false
        for name in node.childOrder {
            if let child = node.children[name] {
                clearMarks(from: child)
            }
        }
    }

    private func update(for node: Node) -> NodeUpdate {
        NodeUpdate(
            path: node.path,
            messageCount: node.messageCount,
            lastUpdate: node.lastUpdate,
            message: node.message,
            childCount: node.childOrder.count,
            leafMessageCount: node.leafMessageCount(),
            childTopicCount: node.childTopicCount()
        )
    }

    private func find(path: String) -> Node? {
        var current = root
        if path.isEmpty { return root }
        for segment in path.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            guard let child = current.children[segment] else { return nil }
            current = child
        }
        return current
    }
}
