import ApplicationServices
import Foundation

struct KeyboardDriver {
    /// Types a string at the current cursor position by sending low-level CGEvents.
    static func type(_ string: String) {
        let source = CGEventSource(stateID: .privateState)
        for char in string {
            let utf16 = Array(String(char).utf16)
            
            // Create keyDown and keyUp events using the private state source
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            
            // Explicitly clear flags to isolate from active physical modifiers (Control+Shift)
            keyDown?.flags = []
            keyUp?.flags = []
            
            // Override character output with the Unicode sequence
            keyDown?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            
            // Post to system-wide HID event tap
            let tap = CGEventTapLocation.cghidEventTap
            keyDown?.post(tap: tap)
            keyUp?.post(tap: tap)
            
            // Small pause (1ms) to allow the OS and target application to process keypresses sequentially
            usleep(1000)
        }
    }
    
    /// Simulates pressing backspace a specified number of times to delete text.
    static func sendBackspaces(count: Int) {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .privateState)
        let virtualKey: CGKeyCode = 0x33 // Backspace keycode on macOS
        
        for _ in 0..<count {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
            
            keyDown?.flags = []
            keyUp?.flags = []
            
            let tap = CGEventTapLocation.cghidEventTap
            keyDown?.post(tap: tap)
            keyUp?.post(tap: tap)
            
            // 15ms delay ensures the OS and target application process each backspace event reliably
            usleep(15000)
        }
    }
}
