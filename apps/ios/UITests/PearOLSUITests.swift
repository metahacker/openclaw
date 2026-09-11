import XCTest

@MainActor
final class PearOLSUITests: XCTestCase {
    func testContinuousConversationProjectReturnAndInlineContext() {
        let app = XCUIApplication()
        app.launchArguments = ["--pear-ols-screenshot"]
        app.launch()
        XCTAssertTrue(app.scrollViews["ols.timeline"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["ols.context"].exists)
        XCTAssertTrue(app.staticTexts["ols.commentary.commentary:sample"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        let composer = app.textFields["ols.composer"].exists
            ? app.textFields["ols.composer"] : app.textViews["ols.composer"]
        XCTAssertTrue(composer.exists)
        composer.tap()
        composer.typeText("Keep my place")
        app.buttons["ols.projects"].tap()
        // The whole Projects room has a visible return path; gestures are optional.
        let back = app.buttons["ols.projects.return"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(back.isHittable)
        // Project cards are Buttons; the chat surface keeps an inline card with the same
        // label underneath, so require one that is actually on screen.
        let cards = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Weekend garden'"))
        XCTAssertTrue(cards.allElementsBoundByIndex.contains { $0.isHittable })
        back.tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "Keep my place")
        app.buttons["ols.context"].tap()
        // The timeline card under the sheet shares the label, so target the sheet row.
        let moment = app.buttons["ols.moment.sample-garden"]
        XCTAssertTrue(moment.waitForExistence(timeout: 5))
        moment.tap()
        XCTAssertTrue(app.buttons["ols.anchor.sample-garden"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Talking about'")).firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "One Living Surface conversation"
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }
}
