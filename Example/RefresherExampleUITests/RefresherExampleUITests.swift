// Created by weixi on 2026/09/20.

import XCTest

@MainActor
final class RefresherExampleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
    }

    func testPullRefreshOnListAndGrid() {
        pull(app.tables["list"])
        expectSummary("Refreshes 1")
        app.segmentedControls["mode"].buttons["Grid"].tap()
        pull(app.collectionViews["grid"])
        expectSummary("Refreshes 2")
        expectIdle()
    }

    func testScrollingLoadsPagesAndStopsAtEnd() {
        let list = app.tables["list"]
        for _ in 0 ..< 14 {
            if app.staticTexts["summary"].label.contains("Items 60") { break }
            list.swipeUp()
        }
        expectSummary("Items 60")
        expectLabel(app.staticTexts["state"], contains: "Page: done")
        list.swipeUp()
        expectSummary("Pages 3")
    }

    func testFailureRecoveryAndCancellation() {
        app.buttons["failNext"].tap()
        app.buttons["loadMore"].tap()
        expectLabel(app.staticTexts["notice"], contains: "Page failed")
        expectSummary("Items 24")
        app.buttons["loadMore"].tap()
        expectSummary("Items 36")
        app.buttons["slowNext"].tap()
        app.navigationBars.buttons["refresh"].tap()
        expectLabel(app.staticTexts["state"], contains: "Refresh: loading")
        app.navigationBars.buttons["cancel"].tap()
        expectIdle()
        app.navigationBars.buttons["refresh"].tap()
        expectSummary("Refreshes 1")
        expectSummary("Items 24")
    }

    func testDetachDuringRefreshThenRemountAndRotate() {
        app.buttons["slowNext"].tap()
        app.navigationBars.buttons["refresh"].tap()
        expectLabel(app.staticTexts["state"], contains: "Refresh: loading")
        app.buttons["attachment"].tap()
        expectLabel(app.staticTexts["state"], contains: "Detached")
        app.buttons["attachment"].tap()
        app.segmentedControls["mode"].buttons["Grid"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.collectionViews["grid"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
        pull(app.collectionViews["grid"])
        expectSummary("Refreshes 1")
        expectIdle()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Grid after detach, rotation and refresh"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testShortContentAutomaticallyFillsViewport() {
        app.buttons["short"].tap()
        let predicate = NSPredicate(format: "label CONTAINS %@", "Pages 1")
        let loaded = XCTNSPredicateExpectation(predicate: predicate, object: app.staticTexts["summary"])
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 6), .completed)
        XCTAssertFalse(app.staticTexts["summary"].label.contains("Items 2 ·"))
        expectIdle()
    }

    private func pull(_ scrollView: XCUIElement) {
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func expectSummary(_ text: String) {
        expectLabel(app.staticTexts["summary"], contains: text)
    }

    private func expectIdle() {
        expectLabel(app.staticTexts["state"], contains: "Refresh: idle")
    }

    private func expectLabel(
        _ element: XCUIElement,
        contains text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 8),
            .completed,
            "Expected \(text), got \(element.label)",
            file: file,
            line: line
        )
    }
}
