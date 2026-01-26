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
        let precisionToggle = app.checkBoxes["Limit data to one decimal place"]
        XCTAssertTrue(precisionToggle.waitForExistence(timeout: 3))

        if precisionToggle.value as? String != "1" {
            precisionToggle.tap()
        }
        saveAndDismiss(app)

        app.terminate()
        app.launch()

        openSettingsIfNeeded(app)
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
