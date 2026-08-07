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

/// Ring buffer with a fixed capacity, oldest entries evicted first. Storage
/// grows on demand so an untouched buffer costs nothing.
struct RingBuffer<Element> {
    private var storage: [Element] = []
    private var head = 0
    private let capacity: Int

    var count: Int { storage.count }

    init(capacity: Int) {
        self.capacity = Swift.max(1, capacity)
    }

    mutating func add(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    /// Newest first.
    func newestFirst(limit: Int? = nil) -> [Element] {
        let wanted = Swift.min(limit ?? storage.count, storage.count)
        var result: [Element] = []
        result.reserveCapacity(wanted)
        for i in 0..<wanted {
            result.append(storage[(head + storage.count - 1 - i) % storage.count])
        }
        return result
    }

    mutating func removeAll() {
        storage.removeAll(keepingCapacity: false)
        head = 0
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
        let path: String
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
            if let parent, parent.parent != nil {
                self.path = parent.path + "/" + name
            } else {
                self.path = parent == nil ? "" : name
            }
        }

        var hasMessageData: Bool {
            guard let message else { return false }
            return !message.payload.isEmpty
        }

        var isLeaf: Bool { children.isEmpty }

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
    /// Beyond this many topics new ones are refused; existing topics keep updating.
    static let maxTopics = 100_000

    private let root = Node(name: "", parent: nil)
    private var pending: [(topic: String, message: StoredMessage)] = []
    private var sequence = 0
    private var droppedMessages = 0
    private var touched: [ObjectIdentifier: Node] = [:]
    private var topicCount = 0
    private var messageTotal = 0

    func ingest(topic: String, payload: Data, qos: Int, retain: Bool, received: Date = Date()) {
        let truncated = payload.count > Self.maxPayload ? payload.prefix(Self.maxPayload) : payload
        let message = StoredMessage(
            payload: Data(truncated),
            qos: qos,
            retain: retain,
            received: received,
            sequence: sequence
        )
        sequence += 1
        if pending.count >= Self.maxPending {
            let drop = pending.count / 10
            pending.removeFirst(drop)
            droppedMessages += drop
        }
        pending.append((topic, message))
    }

    /// Drain a batch from the inbox in wire order, in one actor hop.
    func ingest(batch: [IncomingMessage], dropped: Int) {
        droppedMessages += dropped
        for message in batch {
            ingest(
                topic: message.topic,
                payload: message.payload,
                qos: message.qos,
                retain: message.retain,
                received: message.received
            )
        }
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
            guard let node = nodeFor(topic: topic) else {
                droppedMessages += 1
                continue
            }
            applyMessage(message, to: node)

            if !node.hasMessageData && node.isLeaf, node.parent != nil {
                remove(node: node, removedPaths: &removedPaths)
            }
        }

        // A topic deleted and re-created in the same batch is live again.
        removedPaths = removedPaths.filter { find(path: $0) == nil }

        for node in touched.values {
            defer {
                node.markedAdded = false
                node.markedUpdated = false
            }
            guard node.parent != nil, !removedPaths.contains(node.path) else { continue }
            if node.markedAdded {
                delta.added.append(update(for: node))
            } else if node.markedUpdated {
                delta.updated.append(update(for: node))
            }
        }
        touched.removeAll(keepingCapacity: true)

        delta.added.sort { $0.path.count < $1.path.count }
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
        (topicCount, messageTotal)
    }

    func reset() {
        root.children.removeAll()
        root.childOrder.removeAll()
        root.message = nil
        root.messageCount = 0
        root.history = RingBuffer(capacity: Node.historyCapacity)
        pending.removeAll()
        touched.removeAll()
        topicCount = 0
        messageTotal = 0
        sequence = 0
        droppedMessages = 0
    }

    func history(path: String, limit: Int? = nil) -> [StoredMessage] {
        guard let node = find(path: path) else { return [] }
        return node.history.newestFirst(limit: limit)
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

    private func nodeFor(topic: String) -> Node? {
        var current = root
        for segment in topic.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            if let child = current.children[segment] {
                current = child
            } else {
                guard topicCount < Self.maxTopics else { return nil }
                let child = Node(name: segment, parent: current)
                child.markedAdded = true
                current.children[segment] = child
                current.childOrder.append(segment)
                child.invalidateCountsUpwards()
                topicCount += 1
                touched[ObjectIdentifier(child)] = child
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
        messageTotal += 1
        touched[ObjectIdentifier(node)] = node
        markAncestorsUpdated(from: node)
    }

    private func markAncestorsUpdated(from node: Node) {
        var current = node.parent
        while let ancestor = current, ancestor.parent != nil {
            if touched[ObjectIdentifier(ancestor)] != nil, ancestor.markedUpdated || ancestor.markedAdded {
                break
            }
            ancestor.markedUpdated = true
            touched[ObjectIdentifier(ancestor)] = ancestor
            current = ancestor.parent
        }
    }

    private func remove(node: Node, removedPaths: inout Set<String>) {
        var current: Node? = node
        while let node = current, let parent = node.parent {
            parent.children.removeValue(forKey: node.name)
            parent.childOrder.removeAll { $0 == node.name }
            parent.markedUpdated = true
            parent.invalidateCountsUpwards()
            touched[ObjectIdentifier(parent)] = parent
            removedPaths.insert(node.path)
            topicCount -= 1
            messageTotal -= node.messageCount
            if parent.parent != nil, !parent.hasMessageData, parent.isLeaf {
                current = parent
            } else {
                current = nil
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
