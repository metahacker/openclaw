import XCTest

@MainActor
final class PearOLSUITests: XCTestCase {
    func testThreadProjectsReturnAndInlineAnchors() {
        let app = XCUIApplication()
        app.launchArguments = ["--pear-ols-screenshot"]
        app.launch()
        XCTAssertTrue(app.scrollViews["ols.timeline"].waitForExistence(timeout: 15))
        // The thread: presence button, quiet context echo, scrolling rules/bubbles, composer, and edge.
        XCTAssertTrue(app.buttons["ols.voice"].exists)
        let context = app.buttons["ols.context"]
        XCTAssertTrue(context.waitForExistence(timeout: 5))
        XCTAssertEqual(context.value as? String, "#japan-family-trip")
        XCTAssertFalse(app.buttons["ols.object"].exists)
        XCTAssertTrue(app.buttons["ols.anchor.sample-japan-1"].exists)
        XCTAssertTrue(app.staticTexts["ols.commentary.commentary:sample"].exists)
        XCTAssertTrue(app.buttons["ols.projects"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        let composer = app.textFields["ols.composer"].exists
            ? app.textFields["ols.composer"] : app.textViews["ols.composer"]
        XCTAssertTrue(composer.exists)
        // The proof image is the untouched first viewport; interactions follow.
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "One Living Surface thread"
        attachment.lifetime = .keepAlways
        self.add(attachment)

        composer.tap()
        composer.typeText("Keep my place")
        // Projects is the explicit bottom edge; the spine on top of the workspace returns.
        app.buttons["ols.projects"].tap()
        let spine = app.buttons["ols.projects.return"]
        XCTAssertTrue(spine.waitForExistence(timeout: 5))
        XCTAssertTrue(spine.isHittable)
        XCTAssertTrue(app.buttons["ols.project.1"].waitForExistence(timeout: 5))
        spine.tap()
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
