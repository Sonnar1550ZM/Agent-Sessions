import XCTest
@testable import AgentSessionsCore

final class StatePersistenceTests: XCTestCase {
    func testDefaultStateURLUsesAgentSessionsSupportDirectory() {
        let path = StatePersistence.defaultStateURL().path

        XCTAssertTrue(path.hasSuffix("/Library/Application Support/Agent Sessions/state.json"))
    }
}
