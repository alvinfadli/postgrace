import XCTest
@testable import Postgrace

final class ZoomManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset zoom to default before each test
        ZoomManager.shared.resetZoom()
    }

    override func tearDown() {
        ZoomManager.shared.resetZoom()
        super.tearDown()
    }

    func testInitialDefaultZoom() {
        let zm = ZoomManager.shared
        zm.resetZoom()
        XCTAssertEqual(zm.zoomLevel, 1.0, accuracy: 0.001)
        XCTAssertEqual(zm.zoomPercentage, 100)
        XCTAssertEqual(zm.zoomPercentageString, "100%")
        XCTAssertTrue(zm.isDefaultZoom)
        XCTAssertEqual(zm.scale, 1.0, accuracy: 0.001)
        XCTAssertEqual(zm.editorFontSize, 13)
        XCTAssertEqual(zm.gridCellFontSize, 12)
        XCTAssertEqual(zm.gridHeaderFontSize, 12)
        XCTAssertEqual(zm.gridRowPaddingVertical, 5)
    }

    func testZoomInIncrementsByStep() {
        let zm = ZoomManager.shared
        zm.resetZoom()
        zm.zoomIn()
        XCTAssertEqual(zm.zoomLevel, 1.10, accuracy: 0.001)
        XCTAssertEqual(zm.zoomPercentage, 110)
        XCTAssertEqual(zm.zoomPercentageString, "110%")
        XCTAssertFalse(zm.isDefaultZoom)

        // Typography should scale up
        XCTAssertGreaterThan(zm.editorFontSize, 13)
        XCTAssertGreaterThanOrEqual(zm.gridCellFontSize, 12)
    }

    func testZoomOutDecrementsByStep() {
        let zm = ZoomManager.shared
        zm.resetZoom()
        zm.zoomOut()
        XCTAssertEqual(zm.zoomLevel, 0.90, accuracy: 0.001)
        XCTAssertEqual(zm.zoomPercentage, 90)
        XCTAssertEqual(zm.zoomPercentageString, "90%")
        XCTAssertFalse(zm.isDefaultZoom)

        // Typography should scale down
        XCTAssertLessThan(zm.editorFontSize, 13)
    }

    func testZoomInClampsAtMax() {
        let zm = ZoomManager.shared
        zm.setZoom(1.95)
        zm.zoomIn()
        XCTAssertEqual(zm.zoomLevel, 2.00, accuracy: 0.001)
        XCTAssertEqual(zm.zoomPercentageString, "200%")

        // Additional zoom in should not exceed 2.0
        zm.zoomIn()
        XCTAssertEqual(zm.zoomLevel, 2.00, accuracy: 0.001)
    }

    func testZoomOutClampsAtMin() {
        let zm = ZoomManager.shared
        zm.setZoom(0.75)
        zm.zoomOut()
        XCTAssertEqual(zm.zoomLevel, 0.70, accuracy: 0.001)
        XCTAssertEqual(zm.zoomPercentageString, "70%")

        // Additional zoom out should not drop below 0.70
        zm.zoomOut()
        XCTAssertEqual(zm.zoomLevel, 0.70, accuracy: 0.001)
    }

    func testResetZoom() {
        let zm = ZoomManager.shared
        zm.setZoom(1.60)
        XCTAssertFalse(zm.isDefaultZoom)
        zm.resetZoom()
        XCTAssertTrue(zm.isDefaultZoom)
        XCTAssertEqual(zm.zoomLevel, 1.0, accuracy: 0.001)
    }

    func testCalculateFittedWidthScalesWithFontSize() {
        let col = ResultColumn(name: "username", dataTypeOID: 25, dataTypeName: "text")
        let cols = [col]
        let rows: [[CellValue]] = [
            [.string("johndoe_regular_user")]
        ]

        let standardWidth = DataGridView.calculateFittedWidth(
            for: col,
            in: rows,
            columns: cols,
            fontSize: 12
        )

        let zoomedWidth = DataGridView.calculateFittedWidth(
            for: col,
            in: rows,
            columns: cols,
            fontSize: 18
        )

        // The zoomed-in font must require a wider column width
        XCTAssertGreaterThan(zoomedWidth, standardWidth)
    }
}
