import XCTest
@testable import MQTTExplorer

@MainActor
final class ChartStoreTests: XCTestCase {
    func testAddAndRemoveCharts() {
        let store = ChartStore()
        store.addChart(path: "a/b", field: nil)
        store.addChart(path: "a/b", field: "temp")
        store.addChart(path: "a/b", field: nil) // duplicate, ignored

        XCTAssertEqual(store.series.count, 2)
        XCTAssertTrue(store.hasChart(for: "a/b"))

        store.removeCharts(for: "a/b")
        XCTAssertTrue(store.series.isEmpty)
        XCTAssertFalse(store.hasChart(for: "a/b"))
    }

    func testIngestFeedsMatchingCharts() {
        let store = ChartStore()
        store.addChart(path: "sensor", field: nil)
        store.addChart(path: "sensor", field: "temp")

        let whole = NodeUpdate(
            path: "sensor", messageCount: 1, lastUpdate: Date(),
            message: StoredMessage(payload: Data("42".utf8), qos: 0, retain: false, received: Date(), sequence: 0),
            childCount: 0, leafMessageCount: 1, childTopicCount: 1
        )
        store.ingest(update: whole)

        let jsonPayload = Data(#"{"temp": 21.5, "label": "x"}"#.utf8)
        let json = NodeUpdate(
            path: "sensor", messageCount: 2, lastUpdate: Date(),
            message: StoredMessage(payload: jsonPayload, qos: 0, retain: false, received: Date(), sequence: 1),
            childCount: 0, leafMessageCount: 2, childTopicCount: 1
        )
        store.ingest(update: json)

        let wholeChart = store.series.first { $0.key.field == nil }
        let tempChart = store.series.first { $0.key.field == "temp" }
        XCTAssertEqual(wholeChart?.samples.map(\.value), [42])
        XCTAssertEqual(tempChart?.samples.map(\.value), [21.5])
    }

    func testSamplesCappedAt500() {
        let store = ChartStore()
        store.addChart(path: "t", field: nil)
        let base = Date()
        for i in 0..<600 {
            let update = NodeUpdate(
                path: "t", messageCount: i + 1, lastUpdate: base,
                message: StoredMessage(
                    payload: Data("\(i)".utf8), qos: 0, retain: false,
                    received: base.addingTimeInterval(TimeInterval(i)), sequence: i
                ),
                childCount: 0, leafMessageCount: i + 1, childTopicCount: 1
            )
            store.ingest(update: update)
        }
        XCTAssertEqual(store.series.first?.samples.count, 500)
    }

    func testPauseFreezesSamples() {
        let store = ChartStore()
        store.addChart(path: "t", field: nil)
        let update = NodeUpdate(
            path: "t", messageCount: 1, lastUpdate: Date(),
            message: StoredMessage(payload: Data("1".utf8), qos: 0, retain: false, received: Date(), sequence: 0),
            childCount: 0, leafMessageCount: 1, childTopicCount: 1
        )
        store.ingest(update: update)

        let chart = store.series[0]
        store.togglePause(chart)
        XCTAssertTrue(chart.paused)
        XCTAssertEqual(chart.displaySamples.count, 1)

        store.ingest(update: update) // live samples grow, display stays frozen
        XCTAssertEqual(chart.samples.count, 2)
        XCTAssertEqual(chart.displaySamples.count, 1)

        store.togglePause(chart)
        XCTAssertFalse(chart.paused)
    }

    func testMoveUpSwapsWithPrevious() {
        let store = ChartStore()
        store.addChart(path: "first", field: nil)
        store.addChart(path: "second", field: nil)
        store.moveUp(topic: "second", dotPath: nil)
        XCTAssertEqual(store.series.map(\.key.path), ["second", "first"])
    }
}

final class PlottableTests: XCTestCase {
    func testPlottableValues() {
        XCTAssertEqual(Plottable.value(42), 42)
        XCTAssertEqual(Plottable.value(21.5), 21.5)
        XCTAssertEqual(Plottable.value(true), 1)
        XCTAssertEqual(Plottable.value(false), 0)
        XCTAssertEqual(Plottable.value("42"), 42)
        XCTAssertEqual(Plottable.value("on"), 1)
        XCTAssertEqual(Plottable.value("OFF"), 0)
        XCTAssertEqual(Plottable.value("123,45"), 123.45)
        XCTAssertNil(Plottable.value("hello"))
        XCTAssertNil(Plottable.value(nil))
    }
}

final class DurationParserTests: XCTestCase {
    func testUnits() {
        XCTAssertEqual(DurationParser.seconds("10s"), 10)
        XCTAssertEqual(DurationParser.seconds("5m"), 300)
        XCTAssertEqual(DurationParser.seconds("1h30m"), 5400)
        XCTAssertEqual(DurationParser.seconds("1d"), 86400)
        XCTAssertEqual(DurationParser.seconds("500ms"), 0.5)
        XCTAssertNil(DurationParser.seconds("nonsense"))
        XCTAssertNil(DurationParser.seconds(""))
    }
}

final class JsonLiteralScannerTests: XCTestCase {
    func testLiteralPathsAndLines() {
        let text = """
        {
          "temp": 21.5,
          "on": true,
          "nested": {
            "a": [10, "x"]
          }
        }
        """
        let literals = JsonLiteralScanner.literalsByLine(text)

        XCTAssertEqual(literals[1]?.path, "temp")
        XCTAssertEqual(literals[1]?.value as? Double, 21.5)
        XCTAssertEqual(literals[2]?.path, "on")
        XCTAssertEqual(literals[2]?.value as? Bool, true)
        XCTAssertEqual(literals[4]?.path, "nested.a.0")
        XCTAssertEqual(literals[4]?.value as? Double, 10)
    }
}

final class ValueShapeTests: XCTestCase {
    func testScalarPayloads() {
        guard case .scalar(let value) = ValueShape.of(Data("42.5".utf8)) else {
            return XCTFail("expected scalar")
        }
        XCTAssertEqual(value, 42.5)

        guard case .scalar(let on) = ValueShape.of(Data("on".utf8)) else {
            return XCTFail("expected scalar from on/off")
        }
        XCTAssertEqual(on, 1)
    }

    func testJSONObjectBecomesFields() {
        let payload = Data(#"{"temp": 21.5, "humidity": 60, "name": "sensor"}"#.utf8)
        guard case .fields(let fields) = ValueShape.of(payload) else {
            return XCTFail("expected fields")
        }
        XCTAssertEqual(fields.map(\.name), ["humidity", "temp"])
        XCTAssertEqual(fields.first { $0.name == "temp" }?.value, 21.5)
    }

    func testNumericArrayBecomesSeries() {
        guard case .series(let values) = ValueShape.of(Data("[1, 2, 3.5]".utf8)) else {
            return XCTFail("expected series")
        }
        XCTAssertEqual(values, [1, 2, 3.5])
    }

    func testNonNumericPayloadsHaveNoShape() {
        XCTAssertFalse(ValueShape.of(Data("hello".utf8)).isVisualizable)
        XCTAssertFalse(ValueShape.of(Data()).isVisualizable)
        XCTAssertFalse(ValueShape.of(Data(#"{"name": "only text"}"#.utf8)).isVisualizable)
        XCTAssertFalse(ValueShape.of(Data(#"["a", "b"]"#.utf8)).isVisualizable)
    }
}
