import AppKit
import Carbon.HIToolbox

/// System-wide Allow / Deny shortcuts, registered only while a request card is showing.
/// Uses Carbon hot keys, which need no Accessibility permission.
final class HotKeys {
    var onAllow: () -> Void = {}
    var onDeny: () -> Void = {}

    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x4352_4E53   // 'CRNS'

    var isEnabled: Bool { !refs.isEmpty }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if enabled { register() } else { unregister() }
    }

    private func register() {
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                               nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard status == noErr, id.signature == HotKeys.signature else { return OSStatus(eventNotHandledErr) }
                let me = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { id.id == 1 ? me.onAllow() : me.onDeny() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        }
        let modifiers = UInt32(controlKey | optionKey)
        for (id, key) in [(UInt32(1), kVK_ANSI_Y), (UInt32(2), kVK_ANSI_N)] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(key), modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) }
        }
    }

    private func unregister() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }
}
