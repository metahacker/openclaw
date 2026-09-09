import XCTest

@MainActor
final class PearOLSUITests: XCTestCase {
    func testContinuousConversationAndProjectReturnPreserveDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["--pear-ols-screenshot"]
        app.launch()
        XCTAssertTrue(app.scrollViews["ols.timeline"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["ols.context"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        let composer = app.textFields["ols.composer"].exists
            ? app.textFields["ols.composer"] : app.textViews["ols.composer"]
        XCTAssertTrue(composer.exists)
        composer.tap()
        composer.typeText("Keep my place")
        app.buttons["ols.projects"].tap()
        XCTAssertTrue(app.staticTexts["Weekend garden"].waitForExistence(timeout: 5))
        // The whole Projects room has a visible return path; gestures are optional.
        let back = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'chat'")).firstMatch
        XCTAssertTrue(back.exists)
        back.tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "Keep my place")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "One Living Surface conversation"
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }

    func testContextIsInlineAndNavigationDoesNotSelectSendContext() {
        let app = XCUIApplication()
        app.launchArguments = ["--pear-ols-screenshot"]
        app.launch()
        XCTAssertTrue(app.buttons["ols.context"].waitForExistence(timeout: 15))
        app.buttons["ols.context"].tap()
        let anchor = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Weekend garden'")).firstMatch
        XCTAssertTrue(anchor.waitForExistence(timeout: 5))
        anchor.tap()
        XCTAssertTrue(app.buttons["ols.anchor.sample-garden"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Talking about'")).firstMatch.exists)
    }
}
