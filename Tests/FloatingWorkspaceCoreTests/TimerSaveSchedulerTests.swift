import Foundation
import XCTest
@testable import FloatingWorkspaceCore

@MainActor
final class TimerSaveSchedulerTests: XCTestCase {
    func testScheduledSaveFiresWhileMainRunLoopIsInEventTrackingMode() {
        let scheduler = TimerSaveScheduler()
        var fired = false

        scheduler.schedule(after: 0.01) { fired = true }
        let deadline = Date().addingTimeInterval(1)
        while !fired && Date() < deadline {
            RunLoop.main.run(mode: .eventTracking, before: Date().addingTimeInterval(0.05))
        }

        XCTAssertTrue(fired)
        scheduler.cancel()
    }
}
