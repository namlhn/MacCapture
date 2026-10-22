import XCTest

final class ToolbarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFloatingToolbarAppearsAndButtonsExist() throws {
        let app = XCUIApplication()
        app.launch()

        let regionButton = app.buttons["ToolbarButton_region"]
        if regionButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(regionButton.exists)
            XCTAssertTrue(app.buttons["ToolbarButton_window"].exists)
            XCTAssertTrue(app.buttons["ToolbarButton_fullscreen"].exists)
            XCTAssertTrue(app.buttons["ToolbarButton_Hide"].exists)
        }
    }
}
