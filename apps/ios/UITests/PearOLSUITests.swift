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
        let contextHashtag = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "#japan-family-trip"),
            object: context)
        XCTAssertEqual(XCTWaiter.wait(for: [contextHashtag], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["ols.object"].exists)
        XCTAssertTrue(app.buttons["ols.anchor.sample-japan-1"].exists)
        // One stream across surfaces: a Slack run and an unplaced text sit inline, named quietly.
        let slackAnchor = app.buttons["ols.anchor.sample-ny-slack"]
        XCTAssertTrue(slackAnchor.exists)
        XCTAssertTrue(slackAnchor.label.contains("From Slack"), slackAnchor.label)
        XCTAssertTrue(app.buttons["ols.anchor.sample-texts"].exists)
        XCTAssertTrue(app.staticTexts["ols.commentary.commentary:sample"].exists)
        // A queued turn reads as pending, not failed.
        XCTAssertTrue(app.staticTexts["ols.pending.10"].exists)
        XCTAssertTrue(app.buttons["ols.context-check.keep"].exists)
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

        // Horizontal swipes step between adjacent anchors: left is newer, right is older.
        app.buttons["ols.context"].tap()
        let mvpMoment = app.buttons["ols.moment.sample-mvp"]
        XCTAssertTrue(mvpMoment.waitForExistence(timeout: 5))
        mvpMoment.tap()
        self.waitForContext("#pear-mvp", in: app)
        app.scrollViews["ols.timeline"].swipeLeft()
        self.waitForContext("Here with you", in: app)
        app.scrollViews["ols.timeline"].swipeRight()
        self.waitForContext("#pear-mvp", in: app)

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

    /// The header echoes the hashtag of the moment being read; it is the observable anchor position.
    private func waitForContext(_ value: String, in app: XCUIApplication) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: app.buttons["ols.context"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, "context \(value)")
    }
}
