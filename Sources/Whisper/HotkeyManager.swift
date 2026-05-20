import AppKit
import Foundation

class HotkeyManager: @unchecked Sendable {
    static let shared = HotkeyManager()
    
    var onKeyDown: (() -> Bool)?
    var onKeyUp: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var stateMachine = ControlKeyDictationStateMachine()
    private let focusGate = HotkeyFocusGate()
    private var isLeftControlDown = false
    
    private init() {}
    
    func startMonitoring() {
        stopMonitoring()
        setupModifierMonitors()
        AppLogger.info("Whisper [HotkeyManager]: Monitoring Left Control with NSEvent (double-tap within 1s to start, single tap to stop)")
    }

    // MARK: - NSEvent modifier monitoring

    private func setupModifierMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let keyCode = event.keyCode
            let controlEnabled = event.modifierFlags.contains(.control)
            let timestamp = event.timestamp
            DispatchQueue.main.async {
                self?.handleModifierEvent(keyCode: keyCode, controlEnabled: controlEnabled, timestamp: timestamp)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let keyCode = event.keyCode
            let controlEnabled = event.modifierFlags.contains(.control)
            let timestamp = event.timestamp
            DispatchQueue.main.async {
                self?.handleModifierEvent(keyCode: keyCode, controlEnabled: controlEnabled, timestamp: timestamp)
            }
            return event
        }
    }
    
    // MARK: - Left Control Event Handling
    
    private func handleModifierEvent(keyCode: UInt16, controlEnabled: Bool, timestamp: TimeInterval) {
        guard keyCode == 59 else {
            return
        }

        guard controlEnabled != isLeftControlDown else {
            AppLogger.info("Whisper [HotkeyManager]: Left Control duplicate edge ignored (down=\(controlEnabled))")
            return
        }

        isLeftControlDown = controlEnabled
        guard controlEnabled else {
            AppLogger.info("Whisper [HotkeyManager]: Left Control release ignored")
            return
        }

        if stateMachine.isDictating {
            AppLogger.info("Whisper [HotkeyManager]: Left Control press observed")
            perform(stateMachine.leftControlPressed(at: timestamp))
            return
        }

        guard shouldAcceptStartHotkeyForCurrentFocus() else { return }

        AppLogger.info("Whisper [HotkeyManager]: Left Control press observed")
        perform(stateMachine.leftControlPressed(at: timestamp))
    }

    private func shouldAcceptStartHotkeyForCurrentFocus() -> Bool {
        guard focusGate.shouldAcceptHotkey(
            frontmostBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            mouseLocation: NSEvent.mouseLocation,
            screenFrames: NSScreen.screens.map(\.frame)
        ) else {
            AppLogger.info("Whisper [HotkeyManager]: Left Control press ignored because the pointer is outside local screens")
            return false
        }
        
        return true
    }
    
    private func perform(_ action: ControlKeyDictationAction) {
        switch action {
        case .none:
            break
        case .start:
            startRecording()
        case .stop:
            stopRecording()
        }
    }

    private func startRecording() {
        let didStart = onKeyDown?() ?? false
        if didStart {
            AppLogger.info("Whisper [HotkeyManager]: Recording STARTED")
        } else {
            stateMachine.rejectStart()
            AppLogger.info("Whisper [HotkeyManager]: Recording start rejected")
        }
    }
    
    private func stopRecording() {
        DispatchQueue.main.async {
            self.onKeyUp?()
        }
        AppLogger.info("Whisper [HotkeyManager]: Recording STOPPED")
    }

    func stopMonitoring() {
        if let globalMonitor = globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        isLeftControlDown = false
        stateMachine.reset()
    }
    
    deinit {
        stopMonitoring()
    }
}
