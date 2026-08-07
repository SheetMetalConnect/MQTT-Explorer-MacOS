import XCTest
@testable import MQTTExplorer

final class TopicTreeEngineTests: XCTestCase {
    func testIngestProducesAddedNodes() async {
        let engine = TopicTreeEngine()
        await engine.ingest(topic: "a/b/c", payload: Data("1".utf8), qos: 0, retain: false)
        let delta = await engine.flush()

        XCTAssertEqual(Set(delta.added.map(\.path)), ["a", "a/b", "a/b/c"])
        XCTAssertTrue(delta.updated.isEmpty)
        XCTAssertTrue(delta.removed.isEmpty)

        let leaf = delta.added.first { $0.path == "a/b/c" }
        XCTAssertEqual(leaf?.messageCount, 1)
        XCTAssertEqual(leaf?.childCount, 0)

        let branch = delta.added.first { $0.path == "a/b" }
        XCTAssertEqual(branch?.childCount, 1)
        XCTAssertEqual(branch?.leafMessageCount, 1)
        XCTAssertEqual(branch?.childTopicCount, 1)
    }

    func testSecondMessageIsUpdate() async {
        let engine = TopicTreeEngine()
        await engine.ingest(topic: "a/b", payload: Data("1".utf8), qos: 0, retain: false)
        _ = await engine.flush()

        await engine.ingest(topic: "a/b", payload: Data("2".utf8), qos: 0, retain: false)
        let delta = await engine.flush()

        XCTAssertTrue(delta.added.isEmpty)

        let leaf = delta.updated.first { $0.path == "a/b" }
        XCTAssertEqual(leaf?.messageCount, 2)
        XCTAssertEqual(String(data: leaf?.message?.payload ?? Data(), encoding: .utf8), "2")

        // Ancestors are re-emitted so collapsed rows keep accurate counts.
        let branch = delta.updated.first { $0.path == "a" }
        XCTAssertEqual(branch?.leafMessageCount, 2)
    }

    func testEmptyPayloadRemovesLeafAndCascades() async {
        let engine = TopicTreeEngine()
        await engine.ingest(topic: "a/b/c", payload: Data("1".utf8), qos: 0, retain: false)
        _ = await engine.flush()

        // Empty retained payload on the leaf: node disappears, and the empty
        // parents cascade away (same as the Electron backend).
        await engine.ingest(topic: "a/b/c", payload: Data(), qos: 0, retain: true)
        let delta = await engine.flush()

        XCTAssertEqual(delta.removed, ["a", "a/b", "a/b/c"])
        let history = await engine.history(path: "a/b/c")
        XCTAssertTrue(history.isEmpty)
    }

    func testEmptyPayloadKeepsBranchWithOtherChildren() async {
        let engine = TopicTreeEngine()
        await engine.ingest(topic: "a/b/c", payload: Data("1".utf8), qos: 0, retain: false)
        await engine.ingest(topic: "a/b/d", payload: Data("2".utf8), qos: 0, retain: false)
        _ = await engine.flush()

        await engine.ingest(topic: "a/b/c", payload: Data(), qos: 0, retain: true)
        let delta = await engine.flush()

        XCTAssertEqual(delta.removed, ["a/b/c"])
        let sibling = await engine.lastMessage(path: "a/b/d")
        XCTAssertNotNil(sibling)
    }

    func testHistoryIsNewestFirst() async {
        let engine = TopicTreeEngine()
        for i in 0..<5 {
            await engine.ingest(topic: "x", payload: Data("\(i)".utf8), qos: 0, retain: false)
        }
        _ = await engine.flush()

        let history = await engine.history(path: "x")
        XCTAssertEqual(history.count, 5)
        XCTAssertEqual(
            history.compactMap { String(data: $0.payload, encoding: .utf8) },
            ["4", "3", "2", "1", "0"]
        )
    }

    func testPayloadsAboveMaxAreTruncated() async {
        let engine = TopicTreeEngine()
        let big = Data(repeating: 0x61, count: TopicTreeEngine.maxPayload + 100)
        await engine.ingest(topic: "big", payload: big, qos: 0, retain: false)
        _ = await engine.flush()

        let message = await engine.lastMessage(path: "big")
        XCTAssertEqual(message?.payload.count, TopicTreeEngine.maxPayload)
    }

    func testMessageTopicsForRecursiveDeletion() async {
        let engine = TopicTreeEngine()
        await engine.ingest(topic: "a/b", payload: Data("1".utf8), qos: 0, retain: false)
        await engine.ingest(topic: "a/c/d", payload: Data("2".utf8), qos: 0, retain: false)
        await engine.ingest(topic: "a/e", payload: Data(), qos: 0, retain: false)
        _ = await engine.flush()

        let topics = await engine.messageTopics(in: "a")
        XCTAssertEqual(Set(topics), ["a/b", "a/c/d"])
    }

    func testBufferStats() async {
        let engine = TopicTreeEngine()
        await engine.ingest(topic: "a", payload: Data("1".utf8), qos: 0, retain: false)
        let stats = await engine.bufferStats()
        XCTAssertEqual(stats.changes, 1)
        XCTAssertEqual(stats.fillState, 1.0 / 200_000, accuracy: 1e-9)
    }

    func testCountsTrackAddsAndRemoves() async {
        let engine = TopicTreeEngine()
        await engine.ingest(topic: "a/b/c", payload: Data("1".utf8), qos: 0, retain: false)
        await engine.ingest(topic: "a/b/d", payload: Data("2".utf8), qos: 0, retain: false)
        _ = await engine.flush()

        var counts = await engine.counts()
        XCTAssertEqual(counts.topics, 4)
        XCTAssertEqual(counts.messages, 2)

        await engine.ingest(topic: "a/b/c", payload: Data(), qos: 0, retain: true)
        _ = await engine.flush()

        counts = await engine.counts()
        XCTAssertEqual(counts.topics, 3)
        XCTAssertEqual(counts.messages, 1)
    }

    /// A flood must stay bounded and must not emit a delta entry per message.
    func testFloodStaysBounded() async {
        let engine = TopicTreeEngine()
        for i in 0..<5_000 {
            await engine.ingest(
                topic: "flood/\(i % 500)/value",
                payload: Data("\(i)".utf8),
                qos: 0,
                retain: false
            )
        }
        let delta = await engine.flush()

        let counts = await engine.counts()
        XCTAssertEqual(counts.topics, 1 + 500 + 500)
        XCTAssertEqual(counts.messages, 5_000)
        XCTAssertEqual(delta.added.count + delta.updated.count, counts.topics)
    }

    /// Parents must precede children so the mirror tree can attach every node.
    func testAddedOrderingIsParentFirst() async {
        let engine = TopicTreeEngine()
        await engine.ingest(topic: "x/y/z", payload: Data("1".utf8), qos: 0, retain: false)
        let delta = await engine.flush()

        var seen = Set<String>()
        for update in delta.added {
            let parent = update.path.split(separator: "/").dropLast().joined(separator: "/")
            if !parent.isEmpty {
                XCTAssertTrue(seen.contains(parent), "\(update.path) arrived before \(parent)")
            }
            seen.insert(update.path)
        }
    }
}

final class RingBufferTests: XCTestCase {
    func testEvictsOldestWhenFull() {
        var buffer = RingBuffer<Int>(capacity: 3)
        for i in 1...5 { buffer.add(i) }
        XCTAssertEqual(buffer.newestFirst(), [5, 4, 3])
    }

    func testNewestFirstOrder() {
        var buffer = RingBuffer<Int>(capacity: 10)
        for i in 1...4 { buffer.add(i) }
        XCTAssertEqual(buffer.newestFirst(), [4, 3, 2, 1])
    }
}
