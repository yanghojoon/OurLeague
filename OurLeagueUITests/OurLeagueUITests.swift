//
//  OurLeagueUITests.swift
//  OurLeagueUITests
//
//  Created by 양호준 on 2023/12/12.
//

import XCTest

final class OurLeagueUITests: XCTestCase {

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
    func testLoginScreenAppearsWithoutSession() throws {
        let app = XCUIApplication()
        app.launch()

        let signInButton = app.buttons["appleSignInButton"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 20))
        XCTAssertTrue(signInButton.isHittable)
        XCTAssertFalse(app.staticTexts["authErrorMessage"].exists)
        XCTAssertFalse(app.buttons["createClubButton"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Signed-out login screen"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.terminate()
        app.launch()
        XCTAssertTrue(signInButton.waitForExistence(timeout: 20))
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
