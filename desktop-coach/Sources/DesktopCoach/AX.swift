import AppKit
import ApplicationServices
import CoachCore

/// What the coach read from one field at one moment. Kept in memory only:
/// nothing is written to disk, and no pixels are ever captured.
struct FieldSnapshot {
    let info: FieldInfo
    let text: String
    /// Field position in Accessibility coordinates (origin top-left of the main screen).
    let frame: CGRect?
}

/// Thin helpers around the macOS Accessibility (AXUIElement) API.
enum AX {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func focusedElementSystemWide() -> AXUIElement? {
        element(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute)
    }

    static func focusedElement(ofApp app: AXUIElement) -> AXUIElement? {
        element(app, kAXFocusedUIElementAttribute)
    }

    /// In a browser, the URL of the web page that holds the element (Safari exposes it on AXWebArea).
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

    /// Everything that names the field: its title, description, placeholder and label element.
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

    static func snapshot(of element: AXUIElement) -> FieldSnapshot? {
        guard let role = string(element, kAXRoleAttribute) else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let info = FieldInfo(
            appBundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
            pageURL: pageURL(of: element),
            role: role,
            subrole: string(element, kAXSubroleAttribute),
            label: label(of: element)
        )
        // Never read the value of a password or search field.
        let value = CoachScope.isReadableTextField(info) ? (string(element, kAXValueAttribute) ?? "") : ""
        let text = CoachScope.writtenText(value, placeholder: string(element, kAXPlaceholderValueAttribute))
        return FieldSnapshot(info: info, text: text, frame: frame(of: element))
    }
}
