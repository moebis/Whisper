import Foundation

enum ControlKeyDictationAction: Equatable {
    case none
    case start
    case stop
}

struct ControlKeyDictationStateMachine {
    private let doubleTapWindow: TimeInterval
    private var lastStartPressTime: TimeInterval?
    private(set) var isDictating = false

    init(doubleTapWindow: TimeInterval = 1.0) {
        self.doubleTapWindow = doubleTapWindow
    }

    mutating func leftControlPressed(at timestamp: TimeInterval) -> ControlKeyDictationAction {
        if isDictating {
            lastStartPressTime = nil
            isDictating = false
            return .stop
        }

        guard let previousPressTime = lastStartPressTime else {
            lastStartPressTime = timestamp
            return .none
        }

        guard timestamp - previousPressTime <= doubleTapWindow else {
            lastStartPressTime = timestamp
            return .none
        }

        lastStartPressTime = nil
        isDictating = true
        return .start
    }

    mutating func reset() {
        lastStartPressTime = nil
        isDictating = false
    }

    mutating func rejectStart() {
        reset()
    }
}
