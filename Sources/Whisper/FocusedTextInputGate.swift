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
    
    func shouldAcceptFocusedElement(_ element: FocusedElementDescriptor?) -> Bool {
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
        
        return FocusedElementDescriptor(
            role: stringAttribute(kAXRoleAttribute, from: element),
            subrole: stringAttribute(kAXSubroleAttribute, from: element),
            attributeNames: attributeNames(from: element)
        )
    }
    
    static func selectedTextRangeLocation() -> Int? {
        guard let element = focusedElement() else { return nil }
        
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
