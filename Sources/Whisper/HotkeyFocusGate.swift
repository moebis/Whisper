import CoreGraphics
import Foundation

struct HotkeyFocusGate {
    func shouldAcceptHotkey(
        frontmostBundleIdentifier: String?,
        mouseLocation: CGPoint,
        screenFrames: [CGRect]
    ) -> Bool {
        guard !screenFrames.isEmpty else {
            return true
        }

        return screenFrames.contains { frame in
            frame.contains(mouseLocation)
        }
    }
}
