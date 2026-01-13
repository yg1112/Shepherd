import SwiftUI
import Carbon.HIToolbox
import Combine

@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    private var eventHandler: EventHandlerRef?
    private var hotkeyRef: EventHotKeyRef?

    private init() {
        registerGlobalHotkey()
    }

    // Note: Since this is a singleton, deinit won't be called in normal usage
    // Hotkey unregistration happens when the app terminates

    // MARK: - Register Cmd+Shift+S
    private func registerGlobalHotkey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Install event handler
        let handlerBlock: EventHandlerUPP = { _, event, _ -> OSStatus in
            Task { @MainActor in
                HotkeyManager.shared.handleHotkey()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handlerBlock,
            1,
            &eventType,
            nil,
            &eventHandler
        )

        // Register Cmd+Shift+S (keycode 1 = 's')
        let hotkeyID = EventHotKeyID(signature: OSType(0x5348_5044), id: 1) // "SHPD"
        let modifiers = UInt32(cmdKey | shiftKey)

        RegisterEventHotKey(
            UInt32(kVK_ANSI_S),
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }

    private func unregisterGlobalHotkey() {
        if let hotkeyRef = hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private func handleHotkey() {
        let appState = AppState.shared
        switch appState.currentState {
        case .idle, .monitoring:
            appState.enterSelectionMode()
            OverlayWindowController.shared.show()
        case .selecting:
            appState.exitSelectionMode()
            OverlayWindowController.shared.hide()
        case .triggered:
            appState.acknowledgeAlert()
        }
    }
}
