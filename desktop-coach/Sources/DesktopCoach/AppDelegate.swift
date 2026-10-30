import AppKit
import ApplicationServices
import CoachCore

/// Menu bar app: watches the focused field, runs the rules, shows friendly hints.
/// It only advises; it never types, clicks or changes anything in other apps.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var anyAppItem: NSMenuItem!
    private let watcher: FieldSource = FocusWatcher()
    private let panel = HintPanel()
    private var anyAppMode = false
    private var started = false
    private var accessTimer: Timer?
    /// Texts the person already saw a hint for; not repeated this session.
    private var explained = Set<String>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMenu()
        HotKey.register { [weak self] in self?.checkNow() }
        // Only what the person wrote or changed: tabbing through existing items stays quiet.
        watcher.onFieldLeft = { [weak self] field, changed in
            if changed { self?.evaluate(field, askedByUser: false) }
        }

        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt) {
            startWatching()
        } else {
            setStatus(needsAccess: true)
            // Start by itself as soon as the person allows access in System Settings.
            accessTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                if AXIsProcessTrusted() { self?.startWatching() }
            }
        }
    }

    private func startWatching() {
        accessTimer?.invalidate()
        accessTimer = nil
        guard !started else { return }
        started = true
        setStatus(needsAccess: false)
        watcher.start()
    }

    // MARK: Rules

    private func evaluate(_ field: FieldSnapshot, askedByUser: Bool) {
        guard CoachScope.shouldCoach(field.info, anyApp: anyAppMode) else {
            if askedByUser { panel.show(CoachMessages.nothingToCheck, near: field.frame) }
            return
        }
        if let hint = UserStoryRule.check(field.text) {
            // Explain once per text unless the person asks again.
            if !askedByUser && explained.contains(field.text) { return }
            let text = field.text
            panel.show(hint.message, near: field.frame) { [weak self] in self?.explained.insert(text) }
        } else if askedByUser {
            panel.show(CoachMessages.allGood(fieldLabel: shortLabel(field.info.label)), near: field.frame)
        }
    }

    private func shortLabel(_ label: String) -> String {
        label.components(separatedBy: " · ").first ?? ""
    }

    // MARK: Menu

    private func setUpMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.addItem(withTitle: "Coach me on this field (⌃⌥C)", action: #selector(checkNow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show what the coach sees", action: #selector(showWhatISee), keyEquivalent: "").target = self
        menu.addItem(.separator())
        anyAppItem = menu.addItem(withTitle: "Coach in every app (test mode)", action: #selector(toggleAnyApp), keyEquivalent: "")
        anyAppItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Coach", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func setStatus(needsAccess: Bool) {
        guard let button = statusItem.button else { return }
        let symbol = needsAccess ? "exclamationmark.bubble" : "graduationcap"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Coach") {
            button.image = image
            button.title = ""
        } else {
            button.title = needsAccess ? "Coach (needs access)" : "Coach"
        }
        button.toolTip = needsAccess ? "Coach needs Accessibility access" : "Coach"
    }

    private func currentField() -> FieldSnapshot? {
        watcher.currentField()
    }

    @objc private func checkNow() {
        guard AXIsProcessTrusted() else { return panel.show(CoachMessages.needsAccess, near: nil) }
        guard let field = currentField(), CoachScope.isReadableTextField(field.info) else {
            return panel.show(CoachMessages.cannotRead, near: nil)
        }
        evaluate(field, askedByUser: true)
    }

    /// For the spike: shows exactly what the Accessibility API gives us, so we can learn what Jira exposes.
    @objc private func showWhatISee() {
        guard AXIsProcessTrusted() else { return panel.show(CoachMessages.needsAccess, near: nil) }
        guard let field = currentField() else { return panel.show(CoachMessages.cannotRead, near: nil) }
        let info = field.info
        let preview = field.text.count > 120 ? String(field.text.prefix(120)) + "…" : field.text
        let lines = [
            "App: \(info.appBundleID ?? "unknown")",
            "Page: \(info.pageURL.flatMap { URL(string: $0)?.host } ?? "none")",
            "Field type: \(info.role)\(info.subrole.map { " / \($0)" } ?? "")",
            "Label: \(info.label.isEmpty ? "none" : info.label)",
            "Text: \(preview.isEmpty ? "(empty or not read)" : preview)",
            "Coached: \(CoachScope.shouldCoach(info, anyApp: anyAppMode) ? "yes" : "no")",
        ]
        let message = CoachMessage(
            title: "What the coach sees",
            sections: [.init(heading: nil, text: lines.joined(separator: "\n"))],
            buttonTitle: "Close"
        )
        panel.show(message, near: field.frame)
    }

    @objc private func toggleAnyApp() {
        anyAppMode.toggle()
        anyAppItem.state = anyAppMode ? .on : .off
    }
}
