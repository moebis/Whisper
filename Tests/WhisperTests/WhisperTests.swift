import Testing
import CoreGraphics
@testable import Whisper

@Test func singleLeftControlPressDoesNotStartDictation() {
    var machine = ControlKeyDictationStateMachine()

    #expect(machine.leftControlPressed(at: 10.0) == .none)
    #expect(machine.isDictating == false)
}

@Test func doubleLeftControlPressWithinWindowStartsDictation() {
    var machine = ControlKeyDictationStateMachine()

    #expect(machine.leftControlPressed(at: 10.0) == .none)
    #expect(machine.leftControlPressed(at: 10.7) == .start)
    #expect(machine.isDictating == true)
}

@Test func singleLeftControlPressStopsWhenAlreadyDictating() {
    var machine = ControlKeyDictationStateMachine()

    #expect(machine.leftControlPressed(at: 10.0) == .none)
    #expect(machine.leftControlPressed(at: 10.7) == .start)
    #expect(machine.isDictating == true)

    #expect(machine.leftControlPressed(at: 20.0) == .stop)
    #expect(machine.isDictating == false)
}

@Test func staleLeftControlPressCannotBecomeSecondPress() {
    var machine = ControlKeyDictationStateMachine()

    #expect(machine.leftControlPressed(at: 10.0) == .none)
    #expect(machine.leftControlPressed(at: 13.0) == .none)
    #expect(machine.isDictating == false)
}

@Test func exactlyOneSecondBetweenLeftControlPressesStillCountsAsDoublePress() {
    var machine = ControlKeyDictationStateMachine()

    #expect(machine.leftControlPressed(at: 10.0) == .none)
    #expect(machine.leftControlPressed(at: 11.0) == .start)
    #expect(machine.isDictating == true)
}

@Test func rejectedStartAllowsNextDoubleLeftControlPressToTryStartingAgain() {
    var machine = ControlKeyDictationStateMachine()

    #expect(machine.leftControlPressed(at: 10.0) == .none)
    #expect(machine.leftControlPressed(at: 10.4) == .start)
    #expect(machine.isDictating == true)

    machine.rejectStart()
    #expect(machine.isDictating == false)

    #expect(machine.leftControlPressed(at: 20.0) == .none)
    #expect(machine.leftControlPressed(at: 20.4) == .start)
    #expect(machine.isDictating == true)
}

@Test func focusGateRejectsUniversalControlProxyFocus() {
    let gate = HotkeyFocusGate()

    #expect(gate.shouldAcceptHotkey(
        frontmostBundleIdentifier: "com.apple.universalcontrol",
        mouseLocation: CGPoint(x: 2559, y: 700),
        screenFrames: [CGRect(x: 0, y: 0, width: 2560, height: 1440)]
    ) == false)
}

@Test func focusGateAcceptsNormalLocalFocusInsideLocalScreen() {
    let gate = HotkeyFocusGate()

    #expect(gate.shouldAcceptHotkey(
        frontmostBundleIdentifier: "com.apple.TextEdit",
        mouseLocation: CGPoint(x: 1200, y: 700),
        screenFrames: [CGRect(x: 0, y: 0, width: 2560, height: 1440)]
    ) == true)
}

@Test func focusGateRejectsPointerOutsideLocalScreens() {
    let gate = HotkeyFocusGate()

    #expect(gate.shouldAcceptHotkey(
        frontmostBundleIdentifier: "com.apple.TextEdit",
        mouseLocation: CGPoint(x: 3000, y: 700),
        screenFrames: [CGRect(x: 0, y: 0, width: 2560, height: 1440)]
    ) == false)
}

@Test func replacementPlanDeletesOnlyLiveTypedDeltasWhenFinalTranscriptDiffers() {
    let tracker = DictationTextTracker()
    let session = tracker.beginSession()

    tracker.recordTypedDelta("Hello", sessionID: session)

    let plan = tracker.replacementPlan(
        for: session,
        rawTranscript: "Hello!",
        polishedText: "Hello."
    )

    #expect(plan.backspaceCount == 5)
    #expect(plan.replacementText == "Hello.")
}

@Test func staleDeltasCannotExpandReplacementRangeForNextSession() {
    let tracker = DictationTextTracker()
    let firstSession = tracker.beginSession()
    tracker.recordTypedDelta("old text", sessionID: firstSession)
    tracker.endSession(firstSession)

    let secondSession = tracker.beginSession()
    tracker.recordTypedDelta("late old delta", sessionID: firstSession)
    tracker.recordTypedDelta("new", sessionID: secondSession)

    let plan = tracker.replacementPlan(
        for: secondSession,
        rawTranscript: "new",
        polishedText: "new."
    )

    #expect(plan.backspaceCount == 3)
    #expect(plan.replacementText == "new.")
}

@Test func replacementPlanAppliesFinalTranscriptWhenLiveDeltasDiffer() {
    let tracker = DictationTextTracker()
    let session = tracker.beginSession()

    tracker.recordTypedDelta("hello", sessionID: session)

    let plan = tracker.replacementPlan(
        for: session,
        rawTranscript: "Hello.",
        polishedText: "Hello."
    )

    #expect(plan.backspaceCount == 5)
    #expect(plan.replacementText == "Hello.")
}

@Test func audioLevelMappingKeepsRoomNoiseLowAndSpeechResponsive() {
    #expect(AudioLevelMeter.normalizedLevel(rms: 0.0) == 0.0)
    #expect(AudioLevelMeter.normalizedLevel(rms: 0.001) < 0.05)
    #expect(AudioLevelMeter.normalizedLevel(rms: 0.05) > 0.45)
    #expect(AudioLevelMeter.normalizedLevel(rms: 0.16) > 0.85)
}

@Test func audioLevelSmoothingRisesFasterThanItFalls() {
    let rising = AudioLevelMeter.smoothedLevel(previous: 0.10, current: 0.80)
    let falling = AudioLevelMeter.smoothedLevel(previous: 0.80, current: 0.10)

    #expect(rising > 0.60)
    #expect(falling > 0.50)
}
