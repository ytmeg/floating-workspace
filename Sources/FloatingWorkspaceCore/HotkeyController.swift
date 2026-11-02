import Carbon
import Foundation

public enum HotkeyError: LocalizedError {
    case registrationFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return "全局快捷键注册失败（OSStatus \(status)）。菜单栏仍可使用。"
        }
    }
}

@MainActor
public final class HotkeyController {
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var callbackContext: UnsafeMutableRawPointer?

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public func start() throws {
        guard hotKeyRef == nil, eventHandlerRef == nil else { return }

        let context = Unmanaged.passRetained(self).toOpaque()
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        var handlerRef: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &eventType,
            context,
            &handlerRef
        )
        guard handlerStatus == noErr else {
            Unmanaged<HotkeyController>.fromOpaque(context).release()
            throw HotkeyError.registrationFailed(handlerStatus)
        }

        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            UInt32(controlKey | optionKey | cmdKey),
            EventHotKeyID(signature: 0x46575031, id: 1),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            Unmanaged<HotkeyController>.fromOpaque(context).release()
            throw HotkeyError.registrationFailed(status)
        }

        self.hotKeyRef = hotKeyRef
        self.eventHandlerRef = handlerRef
        self.callbackContext = context
    }

    public func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        if let callbackContext {
            Unmanaged<HotkeyController>.fromOpaque(callbackContext).release()
            self.callbackContext = nil
        }
    }

    fileprivate func invokeAction() {
        action()
    }
}

private func hotkeyEventHandler(
    _ eventHandlerCallRef: EventHandlerCallRef?,
    _ eventRef: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        controller.invokeAction()
    }
    return noErr
}
