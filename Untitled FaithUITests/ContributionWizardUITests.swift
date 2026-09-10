import XCTest

@MainActor
final class ContributionWizardUITests: XCTestCase {
    func testContributionAndOptionalThanksKeepTheSameTotal() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-chat"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        let addUsage = app.buttons["Add usage"].firstMatch
        // Keep the action reachable on smaller displays and larger text sizes.
        for _ in 0..<4 where !addUsage.waitForExistence(timeout: 2) || !addUsage.isHittable { app.swipeUp() }
        XCTAssertTrue(addUsage.waitForExistence(timeout: 5))
        capture("settings-profile-and-usage", app: app)
        addUsage.tap()

        let next = app.buttons["contribution-continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled)
        app.buttons["contribution-key-1"].tap()
        app.buttons["contribution-key-0"].tap()
        XCTAssertTrue(next.isEnabled)
        capture("01-contribution-amount", app: app)
        next.tap()

        let slider = app.sliders["developer-share-slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        let developerAmount = app.staticTexts["developer-share-amount"]
        XCTAssertEqual(developerAmount.label, "$0.00")
        let noteToggle = app.buttons["developer-note-toggle"]
        let note = app.staticTexts["developer-note-body"]
        XCTAssertEqual(noteToggle.label, "Read developer’s note")
        XCTAssertFalse(note.exists)
        noteToggle.tap()
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertTrue(note.label.contains("I am not here for the money."))
        XCTAssertTrue(note.label.contains("This is all for the glory of God."))
        XCTAssertTrue(note.label.contains("Luke Fournier (developer)"))
        XCTAssertEqual(next.label, "Continue with $10.00")
        capture("05-developer-note-expanded", app: app)
        XCTAssertEqual(noteToggle.label, "Hide developer’s note")
        noteToggle.tap()
        XCTAssertFalse(note.exists)
        XCTAssertEqual(developerAmount.label, "$0.00")
        slider.adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(developerAmount.label, "$0.30")
        XCTAssertEqual(next.label, "Continue with $10.00")
        capture("02-developer-thanks", app: app)

        app.buttons["Back to contribution amount"].tap()
        XCTAssertTrue(app.buttons["contribution-key-0"].waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        XCTAssertEqual(developerAmount.label, "$0.30")
        XCTAssertEqual(next.label, "Continue with $10.00")
        slider.adjust(toNormalizedSliderPosition: 0)
        XCTAssertEqual(developerAmount.label, "$0.00")

        // Checkout is intentionally unavailable; the wizard must not simulate a successful payment.
        next.tap()
        XCTAssertTrue(app.alerts["Contributions"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.alerts.staticTexts["Contributions aren’t available just yet. You haven’t been charged."].exists)
        app.alerts.buttons["OK"].tap()
        app.buttons["Close contribution"].tap()
        XCTAssertTrue(app.buttons["Add usage"].waitForExistence(timeout: 3))
    }

    func testDeveloperThanksInDarkAppearance() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-chat", "--contribution-preview-dark"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        let addUsage = app.buttons["Add usage"].firstMatch
        // Keep the action reachable on smaller displays and larger text sizes.
        for _ in 0..<4 where !addUsage.waitForExistence(timeout: 2) || !addUsage.isHittable { app.swipeUp() }
        XCTAssertTrue(addUsage.waitForExistence(timeout: 5))
        addUsage.tap()
        XCTAssertTrue(app.buttons["contribution-key-2"].waitForExistence(timeout: 5))
        app.buttons["contribution-key-2"].tap()
        app.buttons["contribution-key-5"].tap()
        capture("03-contribution-amount-dark", app: app)
        app.buttons["contribution-continue"].tap()
        let slider = app.sliders["developer-share-slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(app.staticTexts["developer-share-amount"].label, "$0.75")
        XCTAssertEqual(app.buttons["contribution-continue"].label, "Continue with $25.00")
        capture("04-developer-thanks-dark", app: app)
        app.buttons["Close contribution"].tap()
    }

    private func capture(_ name: String, app: XCUIApplication) {
        // Capture the settled digits, rather than a blurred frame midway through numericText's transition.
        Thread.sleep(forTimeInterval: 0.6)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
