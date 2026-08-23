import XCTest

final class MojoIOSAppUITests: XCTestCase {
    func testVisibleMojoValues() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["mojo-greeting"].waitForExistence(timeout: 10))
        XCTAssertEqual(
            app.staticTexts["mojo-greeting"].label,
            "Hello from Mojo on iOS."
        )
        XCTAssertTrue(app.staticTexts["mojo-sum"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["mojo-sum"].label, "20 + 22 = 42")
    }
}
