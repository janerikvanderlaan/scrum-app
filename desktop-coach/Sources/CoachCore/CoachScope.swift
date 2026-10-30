import Foundation

/// What the coach knows about a field. Read through the Accessibility API:
/// the field's role and label, the app it belongs to and, in a browser, the page URL.
public struct FieldInfo: Equatable, Sendable {
    public var appBundleID: String?
    public var pageURL: String?
    public var role: String
    public var subrole: String?
    public var label: String

    public init(appBundleID: String?, pageURL: String?, role: String, subrole: String?, label: String) {
        self.appBundleID = appBundleID
        self.pageURL = pageURL
        self.role = role
        self.subrole = subrole
        self.label = label
    }
}

/// Decides which fields the coach looks at. By default: story fields in Jira only.
/// Password and search fields are never read.
public enum CoachScope {
    public static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]
    public static let skippedSubroles: Set<String> = ["AXSecureTextField", "AXSearchField"]
    private static let storyLabels = ["summary", "description", "title", "story", "samenvatting", "beschrijving", "titel"]

    public static func isJiraPage(_ url: String?) -> Bool {
        guard let url, let host = URL(string: url)?.host?.lowercased() else { return false }
        return host.hasSuffix(".atlassian.net") || host.contains("jira")
    }

    public static func isStoryField(label: String) -> Bool {
        let lower = label.lowercased()
        return storyLabels.contains { lower.contains($0) }
    }

    public static func isReadableTextField(_ field: FieldInfo) -> Bool {
        guard textRoles.contains(field.role) else { return false }
        if let subrole = field.subrole, skippedSubroles.contains(subrole) { return false }
        return true
    }

    /// Prompts some web editors expose as the field's value while it is still empty
    /// (Jira's description editor: "Typ /ai om het aan Rovo te vragen …").
    private static let editorPrompts = ["typ /ai", "type /ai"]

    /// The text the person wrote: empty when the field only shows its placeholder or an editor prompt.
    public static func writtenText(_ value: String, placeholder: String?) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let placeholder, !placeholder.isEmpty,
           trimmed == placeholder.trimmingCharacters(in: .whitespacesAndNewlines) {
            return ""
        }
        let lower = trimmed.lowercased()
        if editorPrompts.contains(where: { lower.hasPrefix($0) }) { return "" }
        return value
    }

    /// anyApp is the test mode from the menu: coach every text field in every app.
    public static func shouldCoach(_ field: FieldInfo, anyApp: Bool) -> Bool {
        guard isReadableTextField(field) else { return false }
        if anyApp { return true }
        return isJiraPage(field.pageURL) && isStoryField(label: field.label)
    }
}
