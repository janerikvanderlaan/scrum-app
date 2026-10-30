import AppKit
import ApplicationServices

/// The Accessibility helpers the probe needs. A copy of the coach's own (an executable
/// can't import another executable), kept small and read-only.
enum ProbeAX {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func textValue(_ element: AXUIElement) -> String? {
        let value = attribute(element, kAXValueAttribute)
        return (value as? String) ?? (value as? NSNumber)?.stringValue
    }

    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func label(of element: AXUIElement) -> String {
        var parts: [String] = []
        for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXPlaceholderValueAttribute, kAXHelpAttribute] {
            if let text = string(element, name), !text.isEmpty { parts.append(text) }
        }
        if let titleElement = self.element(element, kAXTitleUIElementAttribute),
           let text = string(titleElement, kAXValueAttribute) ?? string(titleElement, kAXTitleAttribute),
           !text.isEmpty {
            parts.append(text)
        }
        return parts.joined(separator: " · ")
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }

    /// The nearest ancestor (or the element itself) with this role, looking at most 8 levels up.
    static func ancestor(of element: AXUIElement, role: String) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let el = current else { return nil }
            if string(el, kAXRoleAttribute) == role { return el }
            current = self.element(el, kAXParentAttribute)
        }
        return nil
    }

    private static let dialogSubroles: Set<String> = ["AXApplicationDialog", "AXDialog", "AXSystemDialog"]

    static func dialog(containing element: AXUIElement) -> AXUIElement? {
        var current = self.element(element, kAXParentAttribute)
        for _ in 0..<40 {
            guard let el = current else { return nil }
            let role = string(el, kAXRoleAttribute)
            if role == "AXSheet" || string(el, kAXSubroleAttribute).map(dialogSubroles.contains) == true { return el }
            if role == "AXWebArea" || role == "AXWindow" { return nil }
            current = self.element(el, kAXParentAttribute)
        }
        return nil
    }

    static func pageURL(of element: AXUIElement) -> String? {
        var current: AXUIElement? = element
        for _ in 0..<60 {
            guard let el = current else { return nil }
            if string(el, kAXRoleAttribute) == "AXWebArea", let value = attribute(el, "AXURL") {
                if let url = value as? URL { return url.absoluteString }
                if let text = value as? String { return text }
            }
            current = self.element(el, kAXParentAttribute)
        }
        return nil
    }
}
