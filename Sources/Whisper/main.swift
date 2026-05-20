import AppKit
import SwiftUI
import AVFoundation

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?
    
    let audioEngine = AudioEngine()
    let webSocketClient = WebSocketClient()
    private let dictationTextTracker = DictationTextTracker()
    private let textInputGate = FocusedTextInputGate()
    
    private var polishTimeoutWorkItem: DispatchWorkItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Configure the menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            // Using SF Symbols for the menu bar icon
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Whisper")
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
        }
        
        // Build the dropdown menu
        let menu = NSMenu()
        let titleItem = NSMenuItem(title: "Whisper Dictation", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit Whisper", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
        
        // 2. Connect components
        audioEngine.onAudioChunk = { [weak self] base64Chunk in
            self?.webSocketClient.sendAudio(base64Data: base64Chunk)
        }
        
        webSocketClient.onTranscriptDelta = { [weak self] delta in
            guard let self = self,
                  let sessionID = self.dictationTextTracker.currentSessionID() else { return }
            
            let typedDelta = self.dictationTextTracker.prepareDeltaForTyping(delta, sessionID: sessionID)
            guard !typedDelta.isEmpty else { return }
            
            // Type the delta immediately in the background so the user sees it in the active text field
            KeyboardDriver.type(typedDelta)
            self.dictationTextTracker.recordTypedDelta(typedDelta, sessionID: sessionID)
        }
        
        webSocketClient.onTranscriptUpdate = { transcript in
            DispatchQueue.main.async {
                OverlayWindow.shared.state.transcript = transcript
            }
        }
        
        webSocketClient.onError = { errorMsg in
            AppLogger.error("Whisper [AppDelegate]: WebSocket error: \(errorMsg)")
        }
        
        // Pre-warm the WebSocket connection on startup
        let apiKey = UserDefaults.standard.string(forKey: "OpenAI_API_Key") ?? ""
        if !apiKey.isEmpty {
            webSocketClient.connect(apiKey: apiKey)
        }
        
        // 3. Setup global hotkeys
        setupHotkeys()
    }
    
    private func cancelPendingPolish() {
        polishTimeoutWorkItem?.cancel()
        polishTimeoutWorkItem = nil
        webSocketClient.onTranscriptionCompleted = nil
    }
    
    private func setupHotkeys() {
        HotkeyManager.shared.onKeyDown = { [weak self] in
            guard let self = self else { return false }
            
            // Cancel any pending polish/timeout tasks from previous sessions
            self.cancelPendingPolish()
            
            // Do not start recording if authorization is not completed
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                AppLogger.error("Whisper [AppDelegate]: Microphone permission not granted. Opening settings.")
                self.openSettings()
                return false
            }
            
            guard AXIsProcessTrusted() else {
                AppLogger.error("Whisper [AppDelegate]: Accessibility permission not granted. Opening settings.")
                self.openSettings()
                return false
            }
            
            let apiKey = UserDefaults.standard.string(forKey: "OpenAI_API_Key") ?? ""
            guard !apiKey.isEmpty else {
                AppLogger.error("Whisper [AppDelegate]: API Key is missing. Opening settings.")
                self.openSettings()
                return false
            }
            
            let focusedElement = AccessibilityFocusInspector.focusedElementDescriptor()
            guard self.textInputGate.shouldAcceptFocusedElement(focusedElement) else {
                let role = focusedElement?.role ?? "nil"
                let subrole = focusedElement?.subrole ?? "nil"
                AppLogger.info("Whisper [AppDelegate]: Recording start rejected because no focused text input is active on this Mac (role=\(role), subrole=\(subrole))")
                return false
            }
            
            let sessionID = self.dictationTextTracker.beginSession(
                cursorAnchorLocation: AccessibilityFocusInspector.selectedTextRangeLocation()
            )
            AppLogger.info("Whisper [AppDelegate]: Dictation text session \(sessionID) started")
            
            // Connect to WebSocket and start audio engine
            self.webSocketClient.connect(apiKey: apiKey)
            self.audioEngine.start()
            
            // Reset overlay state before displaying
            DispatchQueue.main.async {
                OverlayWindow.shared.state.transcript = ""
                OverlayWindow.shared.state.isPolishing = false
            }
            
            // Display visual feedback HUD overlay
            OverlayWindow.shared.show(withLevelObservable: self.audioEngine)
            return true
        }
        
        HotkeyManager.shared.onKeyUp = { [weak self] in
            guard let self = self else { return }
            
            // Stop mic capture
            self.audioEngine.stop()
            
            let smartPolish = UserDefaults.standard.object(forKey: "SmartPolishEnabled") as? Bool ?? true
            
            if smartPolish {
                // Show polishing state on the HUD immediately
                DispatchQueue.main.async {
                    OverlayWindow.shared.state.isPolishing = true
                }
                
                // Setup timeout fallback work item
                let timeoutWork = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.webSocketClient.onTranscriptionCompleted = nil
                    let rawTranscript = self.webSocketClient.accumulatedTranscriptText
                    AppLogger.info("Whisper [AppDelegate]: Transcription completion timeout, proceeding with raw transcript: \"\(rawTranscript)\"")
                    self.runPolishFlow(rawTranscript: rawTranscript)
                }
                self.polishTimeoutWorkItem = timeoutWork
                
                // Register the completion callback from WebSocketClient
                self.webSocketClient.onTranscriptionCompleted = { [weak self] finalTranscript in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.polishTimeoutWorkItem?.cancel()
                        self.polishTimeoutWorkItem = nil
                        self.webSocketClient.onTranscriptionCompleted = nil
                        AppLogger.info("Whisper [AppDelegate]: Received final completed transcription: \"\(finalTranscript)\"")
                        self.runPolishFlow(rawTranscript: finalTranscript)
                    }
                }
                
                // Trigger the commit
                self.webSocketClient.stopAndPrepareNext()
                
                // Schedule the timeout fallback (1.5s total time matching server stop timeout)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: timeoutWork)
                
            } else {
                // Verbatim mode: no corrections or backspaces needed. Just reset and dismiss HUD.
                if let sessionID = self.dictationTextTracker.currentSessionID() {
                    self.dictationTextTracker.endSession(sessionID)
                }
                DispatchQueue.main.async {
                    OverlayWindow.shared.state.transcript = ""
                    OverlayWindow.shared.hide()
                }
                self.webSocketClient.stopAndPrepareNext()
            }
        }
        
        HotkeyManager.shared.startMonitoring()
    }
    
    private func runPolishFlow(rawTranscript: String) {
        let apiKey = UserDefaults.standard.string(forKey: "OpenAI_API_Key") ?? ""
        guard let sessionID = dictationTextTracker.currentSessionID() else {
            AppLogger.error("Whisper [AppDelegate]: No active dictation text session while polishing.")
            DispatchQueue.main.async {
                OverlayWindow.shared.state.transcript = ""
                OverlayWindow.shared.hide()
            }
            return
        }
        
        if !rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Show polishing state on the HUD
            OverlayWindow.shared.state.isPolishing = true
                        
            self.webSocketClient.polishTranscript(rawTranscript, apiKey: apiKey) { polishedText in
                let replacementPlan = self.dictationTextTracker.replacementPlan(
                    for: sessionID,
                    rawTranscript: rawTranscript,
                    polishedText: polishedText,
                    maximumBackspaceCount: self.dictationTextTracker.maximumBackspaceCount(
                        for: sessionID,
                        currentCursorLocation: AccessibilityFocusInspector.selectedTextRangeLocation()
                    )
                )
                AppLogger.info("Whisper [AppDelegate]: Polish replacement plan deletes \(replacementPlan.backspaceCount) typed characters")
                
                // Perform deletion and typing in a background thread to prevent UI freezing
                DispatchQueue.global(qos: .userInitiated).async {
                    if replacementPlan.shouldReplace {
                        KeyboardDriver.sendBackspaces(count: replacementPlan.backspaceCount)
                        KeyboardDriver.type(replacementPlan.replacementText)
                    }
                    
                    // Cleanup UI and prewarm connection on main thread
                    DispatchQueue.main.async {
                        self.dictationTextTracker.endSession(sessionID)
                        OverlayWindow.shared.state.isPolishing = false
                        OverlayWindow.shared.state.transcript = ""
                        OverlayWindow.shared.hide()
                    }
                }
            }
        } else {
            // Nothing was dictated
            DispatchQueue.main.async {
                self.dictationTextTracker.endSession(sessionID)
                OverlayWindow.shared.state.transcript = ""
                OverlayWindow.shared.hide()
            }
        }
    }
    
    @objc func statusBarButtonClicked(_ sender: Any?) {
        // Dropdown menu will appear automatically when clicked
    }
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Whisper Preferences"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            self.settingsWindow = window
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// Start application cycle within MainActor context
@MainActor
func run() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

run()
