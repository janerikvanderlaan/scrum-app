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
    /// The text fields of the dialog the field is in (such as Jira's Start Sprint dialog), else empty.
    let form: [FormField]
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

    static func children(of element: AXUIElement) -> [AXUIElement] {
        guard let value = attribute(element, kAXChildrenAttribute) as? [AnyObject] else { return [] }
        return value.compactMap { child in
            CFGetTypeID(child) == AXUIElementGetTypeID() ? (child as! AXUIElement) : nil
        }
    }

    private static let dialogSubroles: Set<String> = ["AXApplicationDialog", "AXDialog", "AXSystemDialog"]

    /// The nearest dialog around the element (a web dialog in Safari, or a sheet), if any.
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

    /// The readable text fields inside a dialog, with their labels and written text.
    static func formFields(in dialog: AXUIElement) -> [FormField] {
        var fields: [FormField] = []
        var queue = [dialog]
        var visited = 0
        while !queue.isEmpty, visited < 400 {
            let el = queue.removeFirst()
            visited += 1
            if let role = string(el, kAXRoleAttribute), CoachScope.textRoles.contains(role) {
                let subrole = string(el, kAXSubroleAttribute)
                if subrole.map(CoachScope.skippedSubroles.contains) != true {
                    let value = string(el, kAXValueAttribute) ?? ""
                    let text = CoachScope.writtenText(value, placeholder: string(el, kAXPlaceholderValueAttribute))
                    fields.append(FormField(label: label(of: el), text: text))
                }
                continue
            }
            queue.append(contentsOf: children(of: el))
        }
        return fields
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
        let form = dialog(containing: element).map(formFields(in:)) ?? []
        return FieldSnapshot(info: info, text: text, frame: frame(of: element), form: form)
    }
}
