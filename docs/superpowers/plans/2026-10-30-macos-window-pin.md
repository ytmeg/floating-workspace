# macOS Window Pin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu-bar app that pins any ordinary third-party app window above normal windows after focus moves elsewhere, with reliable unpin and restore behavior.

**Architecture:** A small Objective-C system bridge isolates Accessibility and private SkyLight symbols. A Swift `WindowPinCore` library owns the testable pin/unpin state machine; a SwiftPM AppKit executable adds global hotkey, menu-bar UI, permissions, lifecycle restoration, and local `.app` packaging.

**Tech Stack:** Swift 6.3.3, SwiftPM 5.9 manifest, Objective-C/C bridge, AppKit, ApplicationServices, Carbon HIToolbox, CoreGraphics, private SkyLight, XCTest.

## Global Constraints

- Approved spec: `docs/superpowers/specs/2026-10-30-macos-window-pin-design.md`; all tasks implement that spec only.
- Current verification machine: macOS 26.6.2, arm64, Command Line Tools SDK 26.5, Swift 6.3.3; full Xcode and `xcodebuild` are not installed.
- Use SwiftPM commands through `xcrun swift`; do not make Xcode a build dependency.
- On this machine `_AXUIElementGetWindow`, `SLSMainConnectionID`, `SLSSetWindowLevel`, and `SLSGetWindowLevel` resolve. `SLSWindowSetLevel` and `SLSWindowGetLevel` are missing and must not be referenced.
- Private symbols are resolved with `dlopen`/`dlsym`; do not bundle Apple frameworks, private headers, or copied third-party implementations.
- Global shortcut is exactly `⌃⌥⌘P`; pinned level is `CGWindowLevelForKey(.floatingWindow)` and original level is captured before every first pin.
- No screen recording, window-content capture, networking, telemetry, third-party runtime dependency, injection, SIP change, or App Store target.
- No screenshot-overlay fallback. If Task 1 cannot really pin and restore another app's window, stop execution and report the failed gate.
- Runtime state is memory-only. Normal quit restores every live window pinned by this process; crash recovery is explicitly out of scope.
- Use an independent repository. Do not push or publish to GitHub without a fresh, explicit user confirmation.
- Local logs and acceptance output go under `.artifacts/`; reusable probe code and manual test instructions may be committed.
- Execute on a feature branch/worktree, not directly on `main`.

---

## File Map

- `Package.swift`: SwiftPM products, targets, macOS deployment floor.
- `Sources/SystemWindowBridge/include/SystemWindowBridge.h`: narrow C ABI for native window operations.
- `Sources/SystemWindowBridge/SystemWindowBridge.m`: Accessibility lookup, private symbol resolution, get/set level.
- `Sources/WindowPinProbe/main.swift`: reusable real-system feasibility probe.
- `Sources/WindowPinCore/WindowPinModels.swift`: public models, errors, gateway protocol.
- `Sources/WindowPinCore/WindowPinService.swift`: pin/unpin state machine.
- `Sources/WindowPinCore/LiveSystemWindowGateway.swift`: production gateway and native-status mapping.
- `Sources/WindowPinCore/PermissionController.swift`: Accessibility permission flow.
- `Sources/WindowPinCore/HotkeyController.swift`: Carbon global hotkey lifecycle.
- `Sources/WindowPin/main.swift`: `NSApplication` startup.
- `Sources/WindowPin/AppDelegate.swift`: dependency wiring, hotkey actions, quit restoration.
- `Sources/WindowPin/MenuBarController.swift`: status item, popover, state refresh.
- `Sources/WindowPin/MenuViewController.swift`: approved idle/pinned/permission views and callbacks.
- `Tests/WindowPinCoreTests/WindowPinServiceTests.swift`: fake-gateway state tests.
- `Tests/WindowPinCoreTests/LiveSystemWindowGatewayTests.swift`: native-status mapping tests.
- `Resources/Info.plist`: bundled app metadata and accessory-app policy.
- `Scripts/build-app.sh`: release build, `.app` assembly, ad-hoc signing.
- `docs/testing/manual-acceptance.md`: reusable real-window acceptance procedure.
- `.gitignore`, `README.md`, `LICENSE`: local artifacts exclusion, build/use/limits, MIT grant.

### Task 1: Prove Real Cross-App Pin and Restore

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/SystemWindowBridge/include/SystemWindowBridge.h`
- Create: `Sources/SystemWindowBridge/SystemWindowBridge.m`
- Create: `Sources/WindowPinProbe/main.swift`

**Interfaces:**
- Consumes: macOS Accessibility, CoreGraphics, SkyLight, and the resolved symbols listed in Global Constraints.
- Produces: `SWPGetFocusedWindow`, `SWPGetWindowLevel`, `SWPSetWindowLevel`, `SWPStatus`, and `SWPNativeWindow`, used by the live gateway in Task 3.

- [ ] **Step 1: Add the SwiftPM probe skeleton and run it before the bridge exists**

Create `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WindowPin",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WindowPinProbe", targets: ["WindowPinProbe"])
    ],
    targets: [
        .target(
            name: "SystemWindowBridge",
            path: "Sources/SystemWindowBridge",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "WindowPinProbe",
            dependencies: ["SystemWindowBridge"],
            path: "Sources/WindowPinProbe"
        )
    ]
)
```

Create `.gitignore`:

```gitignore
.build/
.swiftpm/
.artifacts/
dist/
.DS_Store
```

Create `Sources/WindowPinProbe/main.swift` with a CLI that supports `info` and `verify`. `info` prints the focused native window and level. `verify` records the original level, sets floating level, pauses for eight seconds so the tester can focus Notes and an IDE, reads the level again, and restores the original level.

```swift
import CoreGraphics
import Foundation
import SystemWindowBridge

enum ProbeError: LocalizedError {
    case operation(String, SWPStatus)

    var errorDescription: String? {
        switch self {
        case let .operation(name, status):
            return "\(name) failed: bridge=\(status.code), system=\(status.systemCode)"
        }
    }
}

func require(_ status: SWPStatus, _ operation: String) throws {
    guard status.code == SWPErrorNone else {
        throw ProbeError.operation(operation, status)
    }
}

func focusedWindow() throws -> SWPNativeWindow {
    var window = SWPNativeWindow(windowID: 0, processID: 0)
    try require(SWPGetFocusedWindow(&window), "SWPGetFocusedWindow")
    return window
}

func level(of windowID: CGWindowID) throws -> CGWindowLevel {
    var level: CGWindowLevel = 0
    try require(SWPGetWindowLevel(windowID, &level), "SWPGetWindowLevel")
    return level
}

do {
    guard CommandLine.arguments.count == 2,
          ["info", "verify"].contains(CommandLine.arguments[1]) else {
        print("Usage: WindowPinProbe info|verify")
        exit(2)
    }

    let window = try focusedWindow()
    let original = try level(of: window.windowID)
    print("WINDOW id=\(window.windowID) pid=\(window.processID) level=\(original)")

    if CommandLine.arguments[1] == "verify" {
        let floating = CGWindowLevelForKey(.floatingWindow)
        try require(SWPSetWindowLevel(window.windowID, floating), "SWPSetWindowLevel")
        print("PINNED id=\(window.windowID) level=\(floating); focus Notes and IDE for 8 seconds")
        fflush(stdout)
        Thread.sleep(forTimeInterval: 8)
        print("LEVEL_AFTER_FOCUS=\(try level(of: window.windowID))")
        try require(SWPSetWindowLevel(window.windowID, original), "SWPSetWindowLevel restore")
        print("RESTORED id=\(window.windowID) level=\(try level(of: window.windowID))")
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
```

Run:

```bash
cd /Users/mi/AIWorkSpace/macos-window-pin
xcrun swift run WindowPinProbe info
```

Expected: FAIL during compilation because `SystemWindowBridge.h` and its implementation do not exist. This is the red step, not a successful probe.

- [ ] **Step 2: Define the narrow C ABI**

Create `Sources/SystemWindowBridge/include/SystemWindowBridge.h`:

```objc
#ifndef SystemWindowBridge_h
#define SystemWindowBridge_h

#include <CoreGraphics/CoreGraphics.h>
#include <stdint.h>

typedef int32_t SWPErrorCode;
enum {
    SWPErrorNone = 0,
    SWPErrorPermissionDenied = 1,
    SWPErrorNoFocusedWindow = 2,
    SWPErrorUnsupported = 3,
    SWPErrorSystemCallFailed = 4
};

typedef struct {
    SWPErrorCode code;
    int32_t systemCode;
} SWPStatus;

typedef struct {
    CGWindowID windowID;
    int32_t processID;
} SWPNativeWindow;

SWPStatus SWPGetFocusedWindow(SWPNativeWindow *outWindow);
SWPStatus SWPGetWindowLevel(CGWindowID windowID, CGWindowLevel *outLevel);
SWPStatus SWPSetWindowLevel(CGWindowID windowID, CGWindowLevel level);

#endif
```

- [ ] **Step 3: Implement Accessibility lookup and private symbol calls**

Create `Sources/SystemWindowBridge/SystemWindowBridge.m`. Use these exact private signatures:

```objc
@import ApplicationServices;
@import CoreGraphics;
@import Foundation;
#import "SystemWindowBridge.h"
#include <dlfcn.h>

typedef int32_t (*SWPMainConnectionIDFunction)(void);
typedef AXError (*SWPAXWindowFunction)(AXUIElementRef, CGWindowID *);
typedef CGError (*SWPGetLevelFunction)(int32_t, CGWindowID, CGWindowLevel *);
typedef CGError (*SWPSetLevelFunction)(int32_t, CGWindowID, CGWindowLevel);

static SWPStatus SWPMakeStatus(SWPErrorCode code, int32_t systemCode) {
    SWPStatus status = { code, systemCode };
    return status;
}

static void *SWPSymbol(void *library, const char *name) {
    if (library == NULL) {
        return NULL;
    }
    return dlsym(library, name);
}
```

Implement `SWPGetWindowLevel` and `SWPSetWindowLevel` by loading `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight`, resolving `SLSMainConnectionID` plus `SLSGetWindowLevel` or `SLSSetWindowLevel`, and returning `SWPErrorUnsupported` if any symbol is absent:

```objc
SWPStatus SWPGetWindowLevel(CGWindowID windowID, CGWindowLevel *outLevel) {
    void *skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    SWPMainConnectionIDFunction mainConnection = (SWPMainConnectionIDFunction)SWPSymbol(skyLight, "SLSMainConnectionID");
    SWPGetLevelFunction getLevel = (SWPGetLevelFunction)SWPSymbol(skyLight, "SLSGetWindowLevel");
    if (mainConnection == NULL || getLevel == NULL || outLevel == NULL) {
        return SWPMakeStatus(SWPErrorUnsupported, 0);
    }
    CGError result = getLevel(mainConnection(), windowID, outLevel);
    return result == kCGErrorSuccess
        ? SWPMakeStatus(SWPErrorNone, 0)
        : SWPMakeStatus(SWPErrorSystemCallFailed, result);
}

SWPStatus SWPSetWindowLevel(CGWindowID windowID, CGWindowLevel level) {
    void *skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    SWPMainConnectionIDFunction mainConnection = (SWPMainConnectionIDFunction)SWPSymbol(skyLight, "SLSMainConnectionID");
    SWPSetLevelFunction setLevel = (SWPSetLevelFunction)SWPSymbol(skyLight, "SLSSetWindowLevel");
    if (mainConnection == NULL || setLevel == NULL) {
        return SWPMakeStatus(SWPErrorUnsupported, 0);
    }
    CGError result = setLevel(mainConnection(), windowID, level);
    return result == kCGErrorSuccess
        ? SWPMakeStatus(SWPErrorNone, 0)
        : SWPMakeStatus(SWPErrorSystemCallFailed, result);
}
```

Implement `SWPGetFocusedWindow` with this exact sequence: check `AXIsProcessTrusted`; copy `kAXFocusedApplicationAttribute` from `AXUIElementCreateSystemWide`; copy `kAXFocusedWindowAttribute`; require `kAXSubroleAttribute` equal to `kAXStandardWindowSubrole`; call `AXUIElementGetPid`; resolve and call `_AXUIElementGetWindow` from ApplicationServices; release every retained CF object. Return distinct status codes rather than a boolean.

The terminal operation must use this mapping:

```objc
AXError axResult = _AXUIElementGetWindowFunction(focusedWindow, &windowID);
if (axResult != kAXErrorSuccess) {
    result = SWPMakeStatus(SWPErrorSystemCallFailed, axResult);
} else {
    outWindow->windowID = windowID;
    outWindow->processID = processID;
    result = SWPMakeStatus(SWPErrorNone, 0);
}
```

- [ ] **Step 4: Build and run focused-window identification**

Run:

```bash
cd /Users/mi/AIWorkSpace/macos-window-pin
xcrun swift build --product WindowPinProbe
open -a Safari
.build/debug/WindowPinProbe info
```

Expected: PASS with a nonzero Safari `windowID`, Safari's PID, and a numeric level. If macOS requests Accessibility permission, grant it to the responsible terminal process, rerun, and record that fact in `.artifacts/probe/permissions.md`. Do not grant screen recording.

- [ ] **Step 5: Run the real pin/focus/restore gate**

Run:

```bash
cd /Users/mi/AIWorkSpace/macos-window-pin
mkdir -p .artifacts/probe
open -a Safari
script -q .artifacts/probe/macOS-26.6.2.log .build/debug/WindowPinProbe verify
```

During the eight-second pause, click a Notes window and then an IDE window. Expected: Safari stays above both normal windows, `LEVEL_AFTER_FOCUS` equals floating level, and `RESTORED` reports the original level. If any part fails, stop the plan, preserve the log, and report the exact bridge/system codes.

- [ ] **Step 6: Commit the verified probe**

```bash
git add Package.swift .gitignore Sources/SystemWindowBridge Sources/WindowPinProbe
git diff --cached --check
git commit -m "feat: verify native window pin and restore" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

### Task 2: Build the Pin State Machine with TDD

**Files:**
- Modify: `Package.swift`
- Create: `Sources/WindowPinCore/WindowPinModels.swift`
- Create: `Sources/WindowPinCore/WindowPinService.swift`
- Create: `Tests/WindowPinCoreTests/WindowPinServiceTests.swift`

**Interfaces:**
- Consumes: `CGWindowID`, `CGWindowLevel`, and `CGWindowLevelForKey(.floatingWindow)`.
- Produces: `WindowDescriptor`, `PinnedWindow`, `WindowPinError`, `WindowPinFailure`, `SystemWindowGateway`, and `WindowPinService` for Tasks 3–5.

- [ ] **Step 1: Add core and test targets**

Add a library product named `WindowPinCore`, a target at `Sources/WindowPinCore` depending on `SystemWindowBridge`, and a test target at `Tests/WindowPinCoreTests` depending on `WindowPinCore`. Keep the existing probe target unchanged. Add these entries to the respective `products` and `targets` arrays:

```swift
.library(name: "WindowPinCore", targets: ["WindowPinCore"]),
.target(
    name: "WindowPinCore",
    dependencies: ["SystemWindowBridge"],
    path: "Sources/WindowPinCore"
),
.testTarget(
    name: "WindowPinCoreTests",
    dependencies: ["WindowPinCore"],
    path: "Tests/WindowPinCoreTests"
)
```

- [ ] **Step 2: Write failing fake-gateway tests**

Create `WindowPinServiceTests.swift`. The fake stores levels and per-window errors, allowing tests to prove that failures do not mutate pin state.

```swift
import CoreGraphics
import XCTest
@testable import WindowPinCore

@MainActor
final class FakeSystemWindowGateway: SystemWindowGateway {
    var current: WindowDescriptor
    var levels: [CGWindowID: CGWindowLevel]
    var existing: Set<CGWindowID>
    var setErrors: [CGWindowID: WindowPinError] = [:]
    var setCalls: [(CGWindowID, CGWindowLevel)] = []

    init(current: WindowDescriptor, levels: [CGWindowID: CGWindowLevel], existing: Set<CGWindowID>) {
        self.current = current
        self.levels = levels
        self.existing = existing
    }

    func focusedWindow() throws -> WindowDescriptor { current }
    func level(for windowID: CGWindowID) throws -> CGWindowLevel { levels[windowID, default: 0] }
    func setLevel(_ level: CGWindowLevel, for windowID: CGWindowID) throws {
        if let error = setErrors[windowID] { throw error }
        levels[windowID] = level
        setCalls.append((windowID, level))
    }
    func windowExists(_ windowID: CGWindowID, processID: pid_t) -> Bool {
        existing.contains(windowID)
    }
}

@MainActor
final class WindowPinServiceTests: XCTestCase {
    private let first = WindowDescriptor(id: 11, processID: 101, appName: "Safari", title: "Design")
    private let second = WindowDescriptor(id: 22, processID: 202, appName: "Notes", title: "Today")

    func testPinIsIdempotentAndUnpinRestoresOriginalLevel() throws {
        let gateway = FakeSystemWindowGateway(current: first, levels: [11: 7], existing: [11])
        let service = WindowPinService(gateway: gateway)
        try service.pinFocusedWindow()
        try service.pinFocusedWindow()
        XCTAssertEqual(service.pinnedWindows.count, 1)
        XCTAssertEqual(gateway.levels[11], CGWindowLevelForKey(.floatingWindow))
        try service.unpin(windowID: 11)
        XCTAssertEqual(gateway.levels[11], 7)
        XCTAssertTrue(service.pinnedWindows.isEmpty)
    }

    func testFailedPinDoesNotChangeState() throws {
        let gateway = FakeSystemWindowGateway(current: first, levels: [11: 0], existing: [11])
        gateway.setErrors[11] = .systemCallFailed(operation: "setLevel", code: -1000)
        let service = WindowPinService(gateway: gateway)
        XCTAssertThrowsError(try service.pinFocusedWindow())
        XCTAssertTrue(service.pinnedWindows.isEmpty)
    }

    func testUnpinAllAttemptsEveryWindowAndKeepsFailures() throws {
        let gateway = FakeSystemWindowGateway(current: first, levels: [11: 0, 22: 0], existing: [11, 22])
        let service = WindowPinService(gateway: gateway)
        try service.pinFocusedWindow()
        gateway.current = second
        try service.pinFocusedWindow()
        gateway.setErrors[22] = .systemCallFailed(operation: "restore", code: -1001)
        let failures = service.unpinAll()
        XCTAssertEqual(failures.map(\.windowID), [22])
        XCTAssertEqual(service.pinnedWindows.map(\.window.id), [22])
        XCTAssertEqual(gateway.levels[11], 0)
    }

    func testCleanupRemovesClosedWindowWithoutAnotherSetCall() throws {
        let gateway = FakeSystemWindowGateway(current: first, levels: [11: 0], existing: [11])
        let service = WindowPinService(gateway: gateway)
        try service.pinFocusedWindow()
        gateway.existing.remove(11)
        gateway.setCalls.removeAll()
        service.cleanupClosedWindows()
        XCTAssertTrue(service.pinnedWindows.isEmpty)
        XCTAssertTrue(gateway.setCalls.isEmpty)
    }

    func testTogglePinsThenUnpinsFocusedWindow() throws {
        let gateway = FakeSystemWindowGateway(current: first, levels: [11: 4], existing: [11])
        let service = WindowPinService(gateway: gateway)
        try service.toggleFocusedWindow()
        XCTAssertEqual(service.pinnedWindows.map(\.window.id), [11])
        try service.toggleFocusedWindow()
        XCTAssertTrue(service.pinnedWindows.isEmpty)
        XCTAssertEqual(gateway.levels[11], 4)
    }
}
```

Run:

```bash
xcrun swift test --filter WindowPinServiceTests
```

Expected: FAIL because the core models and service are not defined.

- [ ] **Step 3: Define the public models and gateway contract**

Create `WindowPinModels.swift`:

```swift
import CoreGraphics
import Foundation

public struct WindowDescriptor: Equatable {
    public let id: CGWindowID
    public let processID: pid_t
    public let appName: String
    public let title: String

    public init(id: CGWindowID, processID: pid_t, appName: String, title: String) {
        self.id = id
        self.processID = processID
        self.appName = appName
        self.title = title
    }
}

public struct PinnedWindow: Equatable {
    public let window: WindowDescriptor
    public let originalLevel: CGWindowLevel
}

public enum WindowPinError: Error, Equatable {
    case accessibilityDenied
    case noFocusedWindow
    case unsupported
    case systemCallFailed(operation: String, code: Int32)
    case hotkeyRegistrationFailed(code: Int32)
}

public struct WindowPinFailure: Equatable {
    public let windowID: CGWindowID
    public let error: WindowPinError
}

@MainActor
public protocol SystemWindowGateway {
    func focusedWindow() throws -> WindowDescriptor
    func level(for windowID: CGWindowID) throws -> CGWindowLevel
    func setLevel(_ level: CGWindowLevel, for windowID: CGWindowID) throws
    func windowExists(_ windowID: CGWindowID, processID: pid_t) -> Bool
}
```

Add user-visible `LocalizedError` descriptions for every case; `systemCallFailed` must include both operation and numeric code.

- [ ] **Step 4: Implement the minimal service**

Create `WindowPinService.swift` with a dictionary keyed by window ID. `pinFocusedWindow` reads the original level, sets floating level, and only then inserts. `unpin` removes closed windows directly, restores live windows before removal, and leaves failed restores in the dictionary. `unpinAll` continues after individual failures. Sort exposed rows by app name then window ID.

```swift
import CoreGraphics
import Foundation

@MainActor
public final class WindowPinService {
    private let gateway: any SystemWindowGateway
    private var pinned: [CGWindowID: PinnedWindow] = [:]

    public init(gateway: any SystemWindowGateway) {
        self.gateway = gateway
    }

    public var pinnedWindows: [PinnedWindow] {
        pinned.values.sorted {
            ($0.window.appName, $0.window.id) < ($1.window.appName, $1.window.id)
        }
    }

    public func pinFocusedWindow() throws {
        let window = try gateway.focusedWindow()
        try pin(window)
    }

    public func toggleFocusedWindow() throws {
        let window = try gateway.focusedWindow()
        if pinned[window.id] != nil {
            try unpin(windowID: window.id)
        } else {
            try pin(window)
        }
    }

    public func unpin(windowID: CGWindowID) throws {
        guard let item = pinned[windowID] else { return }
        if gateway.windowExists(windowID, processID: item.window.processID) {
            try gateway.setLevel(item.originalLevel, for: windowID)
        }
        pinned.removeValue(forKey: windowID)
    }

    @discardableResult
    public func unpinAll() -> [WindowPinFailure] {
        var failures: [WindowPinFailure] = []
        for windowID in pinned.keys.sorted() {
            do {
                try unpin(windowID: windowID)
            } catch let error as WindowPinError {
                failures.append(WindowPinFailure(windowID: windowID, error: error))
            } catch {
                failures.append(WindowPinFailure(windowID: windowID, error: .systemCallFailed(operation: "unpin", code: -1)))
            }
        }
        return failures
    }

    public func cleanupClosedWindows() {
        let closedWindowIDs = pinned.values
            .filter { !gateway.windowExists($0.window.id, processID: $0.window.processID) }
            .map(\.window.id)
        for windowID in closedWindowIDs {
            pinned.removeValue(forKey: windowID)
        }
    }

    private func pin(_ window: WindowDescriptor) throws {
        guard pinned[window.id] == nil else { return }
        let originalLevel = try gateway.level(for: window.id)
        try gateway.setLevel(CGWindowLevelForKey(.floatingWindow), for: window.id)
        pinned[window.id] = PinnedWindow(window: window, originalLevel: originalLevel)
    }
}
```

- [ ] **Step 5: Run all state tests and commit**

```bash
xcrun swift test --filter WindowPinServiceTests
git add Package.swift Sources/WindowPinCore Tests/WindowPinCoreTests
git diff --cached --check
git commit -m "feat: add tested window pin state machine" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

Expected: five tests PASS; no real windows are needed for this test run.

### Task 3: Add the Production Gateway and Permission Flow

**Files:**
- Create: `Sources/WindowPinCore/LiveSystemWindowGateway.swift`
- Create: `Sources/WindowPinCore/PermissionController.swift`
- Create: `Tests/WindowPinCoreTests/LiveSystemWindowGatewayTests.swift`

**Interfaces:**
- Consumes: the C ABI from Task 1 and protocols/models from Task 2.
- Produces: `LiveSystemWindowGateway` and `PermissionController` used by the AppKit executable.

- [ ] **Step 1: Write failing native-status mapping tests**

Create `LiveSystemWindowGatewayTests.swift`:

```swift
import XCTest
@testable import WindowPinCore
import SystemWindowBridge

@MainActor
final class LiveSystemWindowGatewayTests: XCTestCase {
    func testNativeStatusMapping() {
        let gateway = LiveSystemWindowGateway()
        XCTAssertNoThrow(try gateway.validate(SWPStatus(code: SWPErrorNone, systemCode: 0)))
        XCTAssertThrowsError(try gateway.validate(SWPStatus(code: SWPErrorPermissionDenied, systemCode: 0))) {
            XCTAssertEqual($0 as? WindowPinError, .accessibilityDenied)
        }
        XCTAssertThrowsError(try gateway.validate(SWPStatus(code: SWPErrorNoFocusedWindow, systemCode: 0))) {
            XCTAssertEqual($0 as? WindowPinError, .noFocusedWindow)
        }
        XCTAssertThrowsError(try gateway.validate(SWPStatus(code: SWPErrorUnsupported, systemCode: 0))) {
            XCTAssertEqual($0 as? WindowPinError, .unsupported)
        }
        XCTAssertThrowsError(try gateway.validate(SWPStatus(code: SWPErrorSystemCallFailed, systemCode: -1000))) {
            XCTAssertEqual($0 as? WindowPinError, .systemCallFailed(operation: "SkyLight", code: -1000))
        }
    }
}
```

Run `xcrun swift test --filter LiveSystemWindowGatewayTests`. Expected: FAIL because `LiveSystemWindowGateway` and `validate` do not exist.

- [ ] **Step 2: Implement the live gateway**

Create `LiveSystemWindowGateway.swift` as `@MainActor public final class LiveSystemWindowGateway: SystemWindowGateway` with `public init()` and public protocol methods; keep `validate` internal for `@testable` tests. It must use `SWPGetFocusedWindow`, `SWPGetWindowLevel`, and `SWPSetWindowLevel`; derive the app name from `NSRunningApplication`; derive title and existence from `CGWindowListCopyWindowInfo(.optionAll)`; match both `kCGWindowNumber` and `kCGWindowOwnerPID`. Pass `operation: "Accessibility"` when validating `SWPGetFocusedWindow`; use the default `SkyLight` operation for get/set level.

The native status mapper is exactly:

```swift
func validate(_ status: SWPStatus, operation: String = "SkyLight") throws {
    switch status.code {
    case SWPErrorNone:
        return
    case SWPErrorPermissionDenied:
        throw WindowPinError.accessibilityDenied
    case SWPErrorNoFocusedWindow:
        throw WindowPinError.noFocusedWindow
    case SWPErrorUnsupported:
        throw WindowPinError.unsupported
    case SWPErrorSystemCallFailed:
        throw WindowPinError.systemCallFailed(operation: operation, code: status.systemCode)
    default:
        throw WindowPinError.systemCallFailed(operation: "bridge", code: status.code)
    }
}
```

Implement `windowExists` by checking both identifiers, not title, because titles change and can be empty. Use app name `NSRunningApplication(processIdentifier:)?.localizedName` and fallback `Process <pid>`; use the CoreGraphics window title with fallback to app name.

- [ ] **Step 3: Implement public-API permission handling**

Create `PermissionController.swift`:

```swift
import AppKit
import ApplicationServices
import Foundation

@MainActor
public final class PermissionController {
    public init() {}

    public var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    public func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 4: Run unit tests and repeat the native probe**

```bash
xcrun swift test
open -a Safari
.build/debug/WindowPinProbe info
```

Expected: all six XCTest cases PASS and the real probe still identifies Safari. If the probe now fails, stop and fix the shared bridge before UI work.

- [ ] **Step 5: Commit**

```bash
git add Sources/WindowPinCore Tests/WindowPinCoreTests
git diff --cached --check
git commit -m "feat: add live window gateway and permissions" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

### Task 4: Wire Global Hotkey and App Lifecycle

**Files:**
- Create: `Sources/WindowPinCore/HotkeyController.swift`
- Create: `Sources/WindowPin/main.swift`
- Create: `Sources/WindowPin/AppDelegate.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `WindowPinService`, `LiveSystemWindowGateway`, and `PermissionController`.
- Produces: a runnable accessory app where `⌃⌥⌘P` toggles the focused window and normal quit restores live pins.

- [ ] **Step 1: Add the executable target**

Add an executable product `WindowPin` and executable target at `Sources/WindowPin`, depending only on `WindowPinCore`. Keep `WindowPinProbe` available for diagnostics. Add these entries to the respective arrays:

```swift
.executable(name: "WindowPin", targets: ["WindowPin"]),
.executableTarget(
    name: "WindowPin",
    dependencies: ["WindowPinCore"],
    path: "Sources/WindowPin"
)
```

- [ ] **Step 2: Implement Carbon hotkey registration**

Create `HotkeyController.swift` as `@MainActor public final class HotkeyController` with `public init(action: @escaping () -> Void)`, `public func start() throws`, and `public func stop()`. Register virtual key `kVK_ANSI_P` with `controlKey | optionKey | cmdKey`; install a keyboard hotkey event handler on `GetApplicationEventTarget`; use a stable `EventHotKeyID` signature `0x57504E31` and ID `1`.

The registration core is:

```swift
let modifiers = UInt32(controlKey | optionKey | cmdKey)
var reference: EventHotKeyRef?
let status = RegisterEventHotKey(
    UInt32(kVK_ANSI_P),
    modifiers,
    EventHotKeyID(signature: 0x57504E31, id: 1),
    GetApplicationEventTarget(),
    0,
    &reference
)
guard status == noErr else {
    throw WindowPinError.hotkeyRegistrationFailed(code: status)
}
hotKeyRef = reference
```

The C callback must recover the controller with `Unmanaged<HotkeyController>.fromOpaque(context).takeUnretainedValue()` and dispatch its action with `Task { @MainActor in controller.action() }`. `stop()` calls `UnregisterEventHotKey` and `RemoveEventHandler` when non-nil, then clears both references.

- [ ] **Step 3: Wire a minimal runnable accessory app**

Create `main.swift`:

```swift
import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
```

Create `AppDelegate.swift` that owns one gateway, service, permission controller, hotkey controller, and a temporary status item with `pin` icon plus a Quit menu item. On hotkey: if permission is missing call `request()`; otherwise call `toggleFocusedWindow()` and print either the pinned count or the exact error. Do not swallow failures.

Implement termination as:

```swift
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let failures = service.unpinAll()
    guard failures.isEmpty else {
        let alert = NSAlert()
        alert.messageText = "部分窗口未能恢复原层级"
        alert.informativeText = failures.map { "Window \($0.windowID): \($0.error.localizedDescription)" }.joined(separator: "\n")
        alert.runModal()
        return .terminateCancel
    }
    hotkeyController.stop()
    return .terminateNow
}
```

- [ ] **Step 4: Run the real hotkey and quit-restore check**

```bash
xcrun swift build --product WindowPin
.build/debug/WindowPin
```

With Safari focused, press `⌃⌥⌘P`; focus Notes and verify Safari remains above. Press the shortcut on Safari again and verify restoration. Pin two windows, choose Quit, and verify both restore. To test a hotkey conflict, keep one `.build/debug/WindowPin` instance running and launch a second instance with the same command; expected: the second instance shows the numeric `RegisterEventHotKey` error while its menu remains usable. Quit both instances after the check.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/WindowPin Sources/WindowPinCore/HotkeyController.swift
git diff --cached --check
git commit -m "feat: add global hotkey and safe app lifecycle" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

### Task 5: Implement the Approved Menu-Bar Interface

**Files:**
- Create: `Sources/WindowPin/MenuBarController.swift`
- Create: `Sources/WindowPin/MenuViewController.swift`
- Modify: `Sources/WindowPin/AppDelegate.swift`

**Interfaces:**
- Consumes: service, gateway, permission controller, and the app delegate's quit action.
- Produces: idle, pinned, and permission popover states; per-window unpin; unpin all; live pinned count.

- [ ] **Step 1: Define the popover controller contract**

Use these exact controller interfaces so AppDelegate and views do not duplicate business logic:

```swift
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    init(
        service: WindowPinService,
        gateway: any SystemWindowGateway,
        permission: PermissionController,
        onQuit: @escaping () -> Void
    )
    func show()
    func refresh()
}

@MainActor
final class MenuViewController: NSViewController {
    var onToggle: () -> Void = {}
    var onUnpin: (CGWindowID) -> Void = {}
    var onUnpinAll: () -> Void = {}
    var onOpenPermission: () -> Void = {}
    var onRecheckPermission: () -> Void = {}
    var onQuit: () -> Void = {}
}
```

- [ ] **Step 2: Build the three native AppKit states**

Create a 338-point-wide `NSPopover` with `.transient` behavior and an `NSStackView` content layout. Match the approved design:

- Idle: app title, current app/title, `置顶当前窗口` plus `⌃⌥⌘P`, helper text, `暂无置顶窗口`.
- Pinned: `已置顶 N 个`, current target, toggle button, pinned rows with individual `取消`, and `取消全部置顶`.
- Permission: `需要辅助功能权限`, explanation that no window content is read, `打开系统设置`, and `已开启权限，重新检查`.

Use `NSImage(systemSymbolName: "pin")` for idle and `"pin.fill"` for active. Set `statusItem.button?.title` to an empty string for zero pins and `" \(count)"` otherwise. Do not call `NSApp.activate` when opening the popover; doing so can replace the target window with the popover itself.

- [ ] **Step 3: Wire every action and error state**

`show()` first calls `service.cleanupClosedWindows()`, then refreshes target and rows. Toggle and unpin call the service and update the view only after return. `unpinAll` displays returned failures and keeps failed rows visible. Permission buttons call `openSettings()` and `refresh()` respectively. Any thrown `WindowPinError` appears in a wrapping label with its numeric system code where available.

Replace the temporary status item in `AppDelegate` with `MenuBarController`; retain the same service instance used by the hotkey and termination path.

- [ ] **Step 4: Verify the approved states on real windows**

Run `.build/debug/WindowPin` and check:

1. With Accessibility disabled, the permission view is visible and both settings/recheck buttons work.
2. With permission enabled and no pins, Safari appears as the current target.
3. Pin Safari, then open the menu after focusing Notes; Safari remains the listed pinned window and count is one.
4. Pin Notes as a second window; both rows appear, sorted by app name, and both remain above ordinary windows.
5. Cancel Safari only; Notes remains pinned and count becomes one.
6. Close the pinned Notes window; reopening the popover removes its stale row.
7. Choose `取消全部置顶`; all remaining live windows restore.

Expected: all seven checks PASS with no Dock icon and no screen-recording prompt.

- [ ] **Step 5: Commit**

```bash
git add Sources/WindowPin
git diff --cached --check
git commit -m "feat: add menu bar pinning interface" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

### Task 6: Package, Document, and Run Full Acceptance

**Files:**
- Create: `Resources/Info.plist`
- Create: `Scripts/build-app.sh`
- Create: `docs/testing/manual-acceptance.md`
- Create: `README.md`
- Create: `LICENSE`

**Interfaces:**
- Consumes: all executable and core targets from Tasks 1–5.
- Produces: `dist/WindowPin.app`, reusable acceptance instructions, and MIT-licensed source ready for local review. GitHub publication remains unauthorized.

- [ ] **Step 1: Add bundle metadata and a repeatable build script**

Create `Resources/Info.plist` as a property-list XML with these exact values:

```xml
<key>CFBundleExecutable</key><string>WindowPin</string>
<key>CFBundleIdentifier</key><string>local.windowpin</string>
<key>CFBundleName</key><string>窗口置顶</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSAccessibilityUsageDescription</key><string>用于识别并置顶你当前使用的窗口，不读取窗口内容。</string>
```

Create `Scripts/build-app.sh`:

```zsh
#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
xcrun swift build -c release --product WindowPin

APP="$ROOT/dist/WindowPin.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/release/WindowPin" "$APP/Contents/MacOS/WindowPin"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/WindowPin"
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
```

Run `chmod +x Scripts/build-app.sh && Scripts/build-app.sh`. Expected: `dist/WindowPin.app` exists and `codesign --verify --verbose=2 dist/WindowPin.app` exits zero.

- [ ] **Step 2: Write reusable manual acceptance instructions**

Create `docs/testing/manual-acceptance.md` with these exact test groups and expected results:

1. **Focus independence:** pin Safari, focus Notes and the installed IDE; Safari remains above ordinary windows.
2. **Restore:** toggle Safari again; original numeric level is restored and ordinary focus stacking resumes.
3. **Multiple pins:** pin Safari and Notes; both are above ordinary windows, individual cancel affects only the selected row.
4. **Closed-window cleanup:** close a pinned window, reopen the popover; its row disappears without an error.
5. **Permission denial:** disable Accessibility for WindowPin in System Settings; permission state appears, no pin attempt is reported as successful, re-enable and recheck.
6. **Hotkey conflict:** keep one WindowPin instance running and launch a second from the terminal with `dist/WindowPin.app/Contents/MacOS/WindowPin`; the second reports the numeric registration error and menu actions still work. Quit both instances.
7. **Normal quit:** pin two windows and quit; both live windows restore. If any restore fails, termination is cancelled and the alert lists failures.
8. **No extra access:** throughout testing, no screen-recording prompt, network prompt, Dock icon, or window-content capture appears.

Store dated tester output and screenshots only under `.artifacts/acceptance/`; do not commit them.

- [ ] **Step 3: Add README and MIT license**

Create `README.md` with this content, then append the acceptance result only if Step 5 passes:

````markdown
# 窗口置顶

原生 macOS 菜单栏工具，用 `⌃⌥⌘P` 置顶或取消置顶当前普通 App 窗口。焦点切到其他 App 后，置顶窗口仍位于普通窗口上方。

## 使用

1. 构建并打开 `dist/WindowPin.app`。
2. 在系统设置的辅助功能列表中允许「窗口置顶」。不需要屏幕录制权限。
3. 切到目标窗口，按 `⌃⌥⌘P`。再按一次恢复原层级。
4. 点击菜单栏图钉，可查看置顶数量、单独取消或取消全部置顶。

正常退出 App 会恢复本进程置顶且仍然存在的窗口。

## 构建

```bash
xcrun swift test
Scripts/build-app.sh
open dist/WindowPin.app
```

只需要 macOS Command Line Tools，不需要完整 Xcode。

## 诊断

```bash
open -a Safari
xcrun swift run WindowPinProbe verify
```

看到 `PINNED` 后的八秒内切到备忘录和 IDE，确认 Safari 仍在前。探针随后自动恢复原层级并打印 `RESTORED`。失败信息包含 bridge 和 system 数字代码。

## 限制

- 使用 Apple 未公开文档的 SkyLight 接口，不上架 App Store。
- 当前只在本机 macOS 26.6.2 验收；其他版本未验证，系统升级可能使接口失效。
- 只支持普通窗口，不支持全屏、Dock、菜单栏、桌面或系统受保护窗口。
- 不修改 SIP，不注入其他 App，不读取窗口正文，不联网，不上传遥测。
- 异常退出后不保证恢复窗口层级；可重开目标窗口或目标 App 恢复。

## 许可证

MIT。发布 GitHub 前需由项目所有者确认公开范围及 LICENSE 版权行。
````

Create `LICENSE` with the complete MIT text:

```text
MIT License

Copyright (c) 2026 Yintong

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The user reviews the copyright line before any future GitHub publication.

- [ ] **Step 4: Run all automated checks**

```bash
cd /Users/mi/AIWorkSpace/macos-window-pin
xcrun swift test
xcrun swift build -c release --product WindowPinProbe
Scripts/build-app.sh
codesign --verify --verbose=2 dist/WindowPin.app
git diff --check
```

Expected: all six unit tests PASS, both executables build, ad-hoc signature verifies, and no whitespace error is reported.

- [ ] **Step 5: Execute every real acceptance group**

Run `open dist/WindowPin.app` and execute all eight groups from `docs/testing/manual-acceptance.md`. Save raw command output under `.artifacts/acceptance/`. Any failed group blocks a completion claim; fix it through a new tested change and rerun the affected group plus the state-machine suite.

- [ ] **Step 6: Review the final diff and commit without publishing**

```bash
git status --short
git add Resources Scripts docs/testing README.md LICENSE
git diff --cached --check
git diff --cached --stat
git commit -m "docs: package and document local app acceptance" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
git status --short
```

Expected: the commit contains only source, reusable tests/probe, packaging, and documentation; `.artifacts/`, `.build/`, and `dist/` remain untracked. Do not run `git remote add`, `git push`, or any GitHub publication command.

---

## Completion Gate

The app is complete only when Tasks 1–6 are committed, all automated checks pass, and every real acceptance group passes on macOS 26.6.2. Compatibility with other macOS versions remains unclaimed until separately tested. GitHub publication is a later, separately approved action.
