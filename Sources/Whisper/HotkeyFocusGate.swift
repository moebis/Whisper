import CoreGraphics
import Foundation

struct HotkeyFocusGate {
    private static let universalControlBundleIdentifier = "com.apple.universalcontrol"

    func shouldAcceptHotkey(
        frontmostBundleIdentifier: String?,
        mouseLocation: CGPoint,
        screenFrames: [CGRect]
    ) -> Bool {
        if frontmostBundleIdentifier == Self.universalControlBundleIdentifier {
            return false
        }

        guard !screenFrames.isEmpty else {
            return true
        }

        return screenFrames.contains { frame in
            frame.contains(mouseLocation)
        }
    }
}
