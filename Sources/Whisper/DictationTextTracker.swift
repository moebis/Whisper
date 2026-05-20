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
    
    func beginSession() -> Int {
        lock.lock()
        defer { lock.unlock() }
        
        nextSessionID += 1
        activeSessionID = nextSessionID
        typedText = ""
        return nextSessionID
    }
    
    func currentSessionID() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        
        return activeSessionID
    }
    
    func recordTypedDelta(_ delta: String, sessionID: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        guard activeSessionID == sessionID else { return }
        typedText += delta
    }
    
    func replacementPlan(for sessionID: Int, rawTranscript: String, polishedText: String) -> DictationReplacementPlan {
        lock.lock()
        defer { lock.unlock() }
        
        guard activeSessionID == sessionID else {
            return DictationReplacementPlan(backspaceCount: 0, replacementText: polishedText)
        }
        
        if typedText.isEmpty {
            return DictationReplacementPlan(backspaceCount: 0, replacementText: polishedText)
        }
        
        if polishedText == rawTranscript && typedText == rawTranscript {
            return DictationReplacementPlan(backspaceCount: 0, replacementText: "")
        }
        
        return DictationReplacementPlan(backspaceCount: typedText.count, replacementText: polishedText)
    }
    
    func endSession(_ sessionID: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        guard activeSessionID == sessionID else { return }
        activeSessionID = nil
        typedText = ""
    }
}
