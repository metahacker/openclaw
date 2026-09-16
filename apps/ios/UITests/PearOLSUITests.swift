import XCTest

@MainActor
final class PearOLSUITests: XCTestCase {
    func testFirstViewportDetailsReturnAndInlineAnchors() {
        let app = XCUIApplication()
        app.launchArguments = ["--pear-ols-screenshot"]
        app.launch()
        XCTAssertTrue(app.scrollViews["ols.timeline"].waitForExistence(timeout: 15))
        // Mark's first viewport: date kicker, greeting, the first anchor, and the composer.
        XCTAssertTrue(app.staticTexts["ols.greeting"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ols.anchor.sample-japan-1"].exists)
        XCTAssertTrue(app.staticTexts["ols.commentary.commentary:sample"].exists)
        XCTAssertTrue(app.buttons["ols.context"].exists)
        XCTAssertTrue(app.buttons["ols.voice"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        let composer = app.textFields["ols.composer"].exists
            ? app.textFields["ols.composer"] : app.textViews["ols.composer"]
        XCTAssertTrue(composer.exists)
        // The proof image is the untouched first viewport; interactions follow.
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "One Living Surface first viewport"
        attachment.lifetime = .keepAlways
        self.add(attachment)

        composer.tap()
        composer.typeText("Keep my place")
        // Details is an explicit affordance below the timeline; the header pear mark also opens it.
        app.buttons["ols.details"].tap()
        let details = app.otherElements["ols.details.surface"].exists
            ? app.otherElements["ols.details.surface"] : app.scrollViews["ols.details.surface"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["ols.projects"].exists || app.staticTexts["Pick up where we left off"].exists)
        let back = app.buttons["ols.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "Keep my place")
        // Anchors have tap equivalents: the context picker returns to any moment.
        app.buttons["ols.context"].tap()
        let moment = app.buttons["ols.moment.sample-mvp"]
        XCTAssertTrue(moment.waitForExistence(timeout: 5))
        moment.tap()
        XCTAssertTrue(app.buttons["ols.anchor.sample-mvp"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ols.anchor.sample-japan-2"].exists)
        // Browsing a moment never changes where the next message goes.
        XCTAssertFalse(app.buttons["ols.talking-about"].exists)
    }
}
