import XCTest

@testable import MojoIOSAppSources

final class MojoIOSAppTests: XCTestCase {
    func testMojoExports() {
        XCTAssertEqual(MojoIOSValues.message(), MojoIOSValues.expectedMessage)
        XCTAssertEqual(MojoIOSValues.sum(), 42)
    }
}
