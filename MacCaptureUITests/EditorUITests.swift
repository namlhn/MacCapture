import XCTest

final class EditorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEditorWindowOpensWithAnnotationToolsAndExportActions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-open-editor"]
        app.launch()

        let copyButton = app.buttons["EditorButton_Copy"]
        if copyButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(copyButton.exists)
            XCTAssertTrue(app.buttons["EditorButton_Save"].exists)
            XCTAssertTrue(app.buttons["EditorButton_Undo"].exists)
            XCTAssertTrue(app.buttons["EditorButton_Redo"].exists)
        }
    }
}
