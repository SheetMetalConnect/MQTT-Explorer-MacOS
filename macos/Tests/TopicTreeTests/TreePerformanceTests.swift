import XCTest
@testable import MQTTExplorer

/// Performance is the reason this port exists, so the hot path has hard
/// budgets. These run on the main actor because that is where the cost lands.
@MainActor
final class TreePerformanceTests: XCTestCase {
    private func delta(topics: Int, offset: Int = 0) -> TreeDelta {
        var delta = TreeDelta()
        for index in offset..<(offset + topics) {
            let path = "plant/line\(index % 50)/machine\(index)/telemetry"
            var built: [String] = []
            for segment in path.split(separator: "/").map(String.init) {
                built.append(segment)
                delta.added.append(
                    NodeUpdate(
                        path: built.joined(separator: "/"),
                        messageCount: 1,
                        lastUpdate: Date(),
                        message: StoredMessage(
                            payload: Data("42".utf8),
                            qos: 0,
                            retain: false,
                            received: Date(),
                            sequence: index
                        ),
                        childCount: 0,
                        leafMessageCount: 1,
                        childTopicCount: 1
                    )
                )
            }
        }
        return delta
    }

    /// Building a 10k-topic tree must not take seconds.
    func testTenThousandTopicsApplyQuickly() {
        let tree = UITreeModel()
        let batch = delta(topics: 10_000)

        let start = Date()
        tree.apply(batch)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertNotNil(tree.node(at: "plant/line0/machine0/telemetry"))
        XCTAssertLessThan(elapsed, 2.0, "10k topics took \(elapsed)s to apply")
    }

    /// Updates under collapsed parents change nothing on screen, so they must
    /// not trigger a row rebuild. This is what keeps a firehose cheap.
    func testCollapsedUpdatesDoNotRebuildRows() {
        let tree = UITreeModel()
        tree.apply(delta(topics: 2_000))

        let versionAfterBuild = tree.structureVersion
        let rowsAfterBuild = tree.rows.count

        var updates = TreeDelta()
        for index in 0..<2_000 {
            updates.updated.append(
                NodeUpdate(
                    path: "plant/line\(index % 50)/machine\(index)/telemetry",
                    messageCount: 2,
                    lastUpdate: Date(),
                    message: StoredMessage(
                        payload: Data("43".utf8),
                        qos: 0,
                        retain: false,
                        received: Date(),
                        sequence: index
                    ),
                    childCount: 0,
                    leafMessageCount: 2,
                    childTopicCount: 1
                )
            )
        }

        let start = Date()
        tree.apply(updates)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(tree.structureVersion, versionAfterBuild, "payload updates bumped the structure version")
        XCTAssertEqual(tree.rows.count, rowsAfterBuild)
        XCTAssertLessThan(elapsed, 0.5, "2k payload updates took \(elapsed)s")
    }

    /// The visible row set is what the List renders, so it must stay small
    /// while the tree behind it is large.
    func testCollapsedTreeKeepsRowCountSmall() {
        let tree = UITreeModel()
        tree.apply(delta(topics: 10_000))

        XCTAssertLessThan(
            tree.rows.count,
            200,
            "a collapsed 10k-topic tree exposed \(tree.rows.count) rows"
        )
    }
}

/// The date formatter runs per visible row per redraw. Building a
/// DateFormatter each time made it the hottest frame in a sample.
final class FormattingPerformanceTests: XCTestCase {
    func testFormattingManyRowsIsCheap() {
        let dates = (0..<5_000).map { Date().addingTimeInterval(Double($0)) }

        let start = Date()
        for date in dates {
            _ = DateFormatterFormatting.timeOnly(date, locale: "nl")
        }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.5, "5k timestamps took \(elapsed)s")
    }

    func testFormatterCacheReturnsConsistentOutput() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = DateFormatterFormatting.format(date, locale: "nl")
        let second = DateFormatterFormatting.format(date, locale: "nl")
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(
            DateFormatterFormatting.format(date, locale: "en_US"),
            DateFormatterFormatting.format(date, locale: "nl"),
            "locales must not share a cached formatter"
        )
    }
}
