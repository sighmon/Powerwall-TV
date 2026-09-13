//
//  Powerwall_TVUITests.swift
//  Powerwall-TVUITests
//
//  Created by Simon Loffler on 17/3/2025.
//

import XCTest

final class Powerwall_TVUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testLiveExportAdvisorAnswersAndFollowUp() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["POWERWALL_LIVE_ADVISOR"] == "1", "Opt-in live service test")
        let app = XCUIApplication()
        app.launch()
        let advisor = app.buttons["homeEnergyAdvisorButton"]
        XCTAssertTrue(advisor.waitForExistence(timeout: 20))
        advisor.click()
        let refresh = app.buttons["Refresh advice"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 10))
        let finished = NSPredicate { _, _ in !app.descendants(matching: .any)["advisorBusy"].exists && (app.descendants(matching: .any)["advisorError"].exists || app.staticTexts["advisorMessage1"].exists) }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: finished, evaluatedWith: nil)], timeout: 420), .completed)
        XCTAssertFalse(app.descendants(matching: .any)["advisorError"].exists, app.descendants(matching: .any)["advisorError"].exists ? (app.descendants(matching: .any)["advisorError"].value as? String ?? app.descendants(matching: .any)["advisorError"].label) : "Live estimate failed")
        XCTAssertTrue(app.staticTexts["advisorMessage1"].exists)
        app.buttons["Done"].click()
        advisor.click()
        let question = app.textFields["advisorFollowUp"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        question.click()
        question.typeText("How much battery reserve does this estimate retain?")
        app.buttons["Ask follow-up"].click()
        let followUpFinished = NSPredicate { _, _ in !app.descendants(matching: .any)["advisorBusy"].exists && (app.descendants(matching: .any)["advisorError"].exists || app.staticTexts["advisorMessage3"].exists) }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: followUpFinished, evaluatedWith: nil)], timeout: 180), .completed)
        XCTAssertFalse(app.descendants(matching: .any)["advisorError"].exists, app.descendants(matching: .any)["advisorError"].exists ? (app.descendants(matching: .any)["advisorError"].value as? String ?? app.descendants(matching: .any)["advisorError"].label) : "Live follow-up or voice failed")
        XCTAssertTrue(app.staticTexts["advisorMessage3"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Live export advisor follow-up"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testExportAdvisorSettingsAreAvailable() throws {
        let app = XCUIApplication()
        app.launch()
        openSettingsIfNeeded(app)
        app.radioButtons["Display"].click()
        XCTAssertTrue(app.checkBoxes["Limit data to one decimal place"].waitForExistence(timeout: 3))
        app.radioButtons["About"].click()
        XCTAssertTrue(app.staticTexts["Information"].waitForExistence(timeout: 3))
        app.radioButtons["Connect"].click()
        XCTAssertTrue(app.staticTexts["Login Mode"].waitForExistence(timeout: 3))
        app.radioButtons["Advisor"].click()
        XCTAssertTrue(app.secureTextFields["exportAdvisorAPIKey"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Home Energy Advisor"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["homeEnergyAdvisorPrompt"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["homeEnergyAdvisorVisibility"].exists)
        // Inspect only: do not save Settings or replace installed credentials.
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Export advisor settings"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testHomeEnergyAdvisorButtonVisibility() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-homeEnergyAdvisor_showButton", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["homeEnergyAdvisorButton"].exists)
        app.terminate()
        app.launchArguments = ["-homeEnergyAdvisor_showButton", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["homeEnergyAdvisorButton"].waitForExistence(timeout: 20))
    }

    @MainActor
    func testDemoModeShowsSampleData() throws {
        let app = XCUIApplication()
        app.launch()

        openSettingsIfNeeded(app)
        setGatewayIP(app, to: "demo")
        saveAndDismiss(app)

        XCTAssertTrue(app.staticTexts["Home sweet home"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["OFF-GRID"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testPrecisionTogglePersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launch()

        openSettingsIfNeeded(app)
        app.radioButtons["Display"].click()
        let precisionToggle = app.checkBoxes["Limit data to one decimal place"]
        XCTAssertTrue(precisionToggle.waitForExistence(timeout: 3))

        if precisionToggle.value as? String != "1" {
            precisionToggle.tap()
        }
        saveAndDismiss(app)

        app.terminate()
        app.launch()

        openSettingsIfNeeded(app)
        app.radioButtons["Display"].click()
        XCTAssertEqual(app.checkBoxes["Limit data to one decimal place"].value as? String, "1")
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }

    @MainActor
    private func openSettingsIfNeeded(_ app: XCUIApplication) {
        if app.buttons["Save"].exists {
            return
        }
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func setGatewayIP(_ app: XCUIApplication, to value: String) {
        let ipFields = app.textFields.matching(identifier: "IP Address")
        XCTAssertTrue(ipFields.element(boundBy: 0).waitForExistence(timeout: 3))
        let gatewayField = ipFields.element(boundBy: 0)
        gatewayField.tap()
        gatewayField.typeKey("a", modifierFlags: .command)
        gatewayField.typeText(value)
    }

    @MainActor
    private func saveAndDismiss(_ app: XCUIApplication) {
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        saveButton.tap()
    }
}
