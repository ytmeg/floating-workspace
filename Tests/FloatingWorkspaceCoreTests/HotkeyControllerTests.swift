import Carbon
import XCTest
@testable import FloatingWorkspaceCore

@MainActor
final class HotkeyControllerTests: XCTestCase {
    func testHotkeyEventDispatchesActionOnMainActor() throws {
        let invoked = expectation(description: "hotkey action")
        let controller = HotkeyController {
            XCTAssertTrue(Thread.isMainThread)
            invoked.fulfill()
        }
        try controller.start()
        defer { controller.stop() }

        XCTAssertEqual(postHotkeyEvent(), noErr)
        wait(for: [invoked], timeout: 1)
    }

    func testConflictingRegistrationReportsNumericError() throws {
        let first = HotkeyController {}
        try first.start()
        defer { first.stop() }
        let second = HotkeyController {}
        defer { second.stop() }

        XCTAssertThrowsError(try second.start()) { error in
            guard case HotkeyError.registrationFailed(let status) = error else {
                return XCTFail("Expected registrationFailed, got \(error)")
            }
            XCTAssertNotEqual(status, noErr)
            XCTAssertTrue(error.localizedDescription.contains(String(status)))
        }
    }

    func testStopUnregistersHotkeyAndHandler() throws {
        var invocationCount = 0
        let first = HotkeyController { invocationCount += 1 }
        try first.start()
        first.stop()

        _ = postHotkeyEvent()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(invocationCount, 0)

        let second = HotkeyController {}
        try second.start()
        second.stop()
    }
}

@MainActor
private func postHotkeyEvent() -> OSStatus {
    var event: EventRef?
    let createStatus = CreateEvent(
        nil,
        OSType(kEventClassKeyboard),
        OSType(kEventHotKeyPressed),
        0,
        0,
        &event
    )
    guard createStatus == noErr, let event else { return createStatus }
    defer { ReleaseEvent(event) }

    var hotkeyID = EventHotKeyID(signature: 0x46575031, id: 1)
    let parameterStatus = SetEventParameter(
        event,
        OSType(kEventParamDirectObject),
        OSType(typeEventHotKeyID),
        MemoryLayout<EventHotKeyID>.size,
        &hotkeyID
    )
    guard parameterStatus == noErr else { return parameterStatus }
    return SendEventToEventTarget(event, GetApplicationEventTarget())
}
