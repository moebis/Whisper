import AppKit
import ApplicationServices
import Foundation

struct FocusedElementDescriptor: Equatable {
    let role: String?
    let subrole: String?
    let attributeNames: Set<String>
}

struct FocusedTextInputGate {
    private let acceptedRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox"
    ]
    
    private let acceptedSubroles: Set<String> = [
        "AXSearchField"
    ]
    
    func shouldAcceptFocusedElement(
        _ element: FocusedElementDescriptor?,
        fallbackElements: [FocusedElementDescriptor] = []
    ) -> Bool {
        if accepts(element) {
            return true
        }

        guard element == nil else {
            return false
        }

        return fallbackElements.contains { accepts($0) }
    }

    private func accepts(_ element: FocusedElementDescriptor?) -> Bool {
        guard let element else { return false }
        
        if let role = element.role, acceptedRoles.contains(role) {
            return true
        }
        
        if let subrole = element.subrole, acceptedSubroles.contains(subrole) {
            return true
        }
        
        return element.attributeNames.contains("AXSelectedTextRange")
            && element.attributeNames.contains("AXValue")
    }
}

enum AccessibilityFocusInspector {
    static func focusedElementDescriptor() -> FocusedElementDescriptor? {
        guard let element = focusedElement() else { return nil }
        
        return descriptor(from: element)
    }

    static func focusedWindowTextCandidateDescriptors() -> [FocusedElementDescriptor] {
        focusedWindowTextCandidateElements().map { descriptor(from: $0) }
    }
    
    static func selectedTextRangeLocation() -> Int? {
        guard let element = focusedElement() ?? focusedWindowTextCandidateElements().first else { return nil }
        
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range.location
    }
    
    private static func focusedElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementValue
        )
        
        guard focusedResult == .success,
              let focusedElement = focusedElementValue,
              CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            return nil
        }
        
        return (focusedElement as! AXUIElement)
    }

    private static func focusedWindowTextCandidateElements() -> [AXUIElement] {
        guard let focusedWindow = frontmostApplicationFocusedWindow() else { return [] }

        var remainingVisitCount = 200
        var candidates: [AXUIElement] = []
        collectTextCandidates(
            in: focusedWindow,
            depth: 0,
            remainingVisitCount: &remainingVisitCount,
            candidates: &candidates
        )
        return candidates
    }

    private static func frontmostApplicationFocusedWindow() -> AXUIElement? {
        guard let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        return elementAttribute(kAXFocusedWindowAttribute, from: application)
    }

    private static func collectTextCandidates(
        in element: AXUIElement,
        depth: Int,
        remainingVisitCount: inout Int,
        candidates: inout [AXUIElement]
    ) {
        guard depth <= 8,
              remainingVisitCount > 0,
              candidates.count < 20 else {
            return
        }

        remainingVisitCount -= 1

        if isTextCandidate(element) {
            candidates.append(element)
            return
        }

        for child in childElements(from: element) {
            collectTextCandidates(
                in: child,
                depth: depth + 1,
                remainingVisitCount: &remainingVisitCount,
                candidates: &candidates
            )
        }
    }

    private static func isTextCandidate(_ element: AXUIElement) -> Bool {
        FocusedTextInputGate().shouldAcceptFocusedElement(descriptor(from: element))
    }

    private static func descriptor(from element: AXUIElement) -> FocusedElementDescriptor {
        FocusedElementDescriptor(
            role: stringAttribute(kAXRoleAttribute, from: element),
            subrole: stringAttribute(kAXSubroleAttribute, from: element),
            attributeNames: attributeNames(from: element)
        )
    }

    private static func elementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private static func childElements(from element: AXUIElement) -> [AXUIElement] {
        let children = arrayAttribute(kAXChildrenAttribute, from: element)
        if !children.isEmpty {
            return children
        }

        return arrayAttribute("AXChildrenInNavigationOrder", from: element)
    }

    private static func arrayAttribute(_ attribute: String, from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success,
              let array = value as? [AXUIElement] else {
            return []
        }

        return array
    }
    
    private static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }
    
    private static func attributeNames(from element: AXUIElement) -> Set<String> {
        var names: CFArray?
        let result = AXUIElementCopyAttributeNames(element, &names)
        guard result == .success,
              let namesArray = names as? [String] else {
            return []
        }
        
        return Set(namesArray)
    }
}
