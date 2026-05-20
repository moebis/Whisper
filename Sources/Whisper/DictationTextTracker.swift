import Foundation

struct DictationReplacementPlan: Equatable {
    let backspaceCount: Int
    let replacementText: String
    
    var shouldReplace: Bool {
        backspaceCount > 0 || !replacementText.isEmpty
    }
}

final class DictationTextTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var nextSessionID = 0
    private var activeSessionID: Int?
    private var typedText = ""
    private var cursorAnchorLocation: Int?
    
    func beginSession(cursorAnchorLocation: Int? = nil) -> Int {
        lock.lock()
        defer { lock.unlock() }
        
        nextSessionID += 1
        activeSessionID = nextSessionID
        typedText = ""
        self.cursorAnchorLocation = cursorAnchorLocation
        return nextSessionID
    }
    
    func currentSessionID() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        
        return activeSessionID
    }
    
    func prepareDeltaForTyping(_ delta: String, sessionID: Int) -> String {
        lock.lock()
        defer { lock.unlock() }
        
        guard activeSessionID == sessionID else { return "" }
        guard typedText.isEmpty else { return delta }
        
        return String(delta.drop { $0.isWhitespace })
    }
    
    func recordTypedDelta(_ delta: String, sessionID: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        guard activeSessionID == sessionID else { return }
        typedText += delta
    }
    
    func replacementPlan(
        for sessionID: Int,
        rawTranscript: String,
        polishedText: String,
        maximumBackspaceCount: Int? = nil
    ) -> DictationReplacementPlan {
        lock.lock()
        defer { lock.unlock() }
        let normalizedReplacement = polishedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard activeSessionID == sessionID else {
            return DictationReplacementPlan(backspaceCount: 0, replacementText: normalizedReplacement)
        }
        
        if typedText.isEmpty {
            return DictationReplacementPlan(backspaceCount: 0, replacementText: normalizedReplacement)
        }
        
        if typedText == normalizedReplacement {
            return DictationReplacementPlan(backspaceCount: 0, replacementText: "")
        }
        
        let backspaceCount = min(typedText.count, maximumBackspaceCount ?? typedText.count)
        return DictationReplacementPlan(backspaceCount: backspaceCount, replacementText: normalizedReplacement)
    }
    
    func maximumBackspaceCount(for sessionID: Int, currentCursorLocation: Int?) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        
        guard activeSessionID == sessionID,
              let cursorAnchorLocation,
              let currentCursorLocation else {
            return nil
        }
        
        return max(0, currentCursorLocation - cursorAnchorLocation)
    }
    
    func endSession(_ sessionID: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        guard activeSessionID == sessionID else { return }
        activeSessionID = nil
        typedText = ""
        cursorAnchorLocation = nil
    }
}
