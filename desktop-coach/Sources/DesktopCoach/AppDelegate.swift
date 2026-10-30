import AppKit
import ApplicationServices
import CoachCore

/// Menu bar app: watches the focused field, runs the rules, shows friendly hints.
/// It only advises; it never types, clicks or changes anything in other apps.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var anyAppItem: NSMenuItem!
    private var velocityItem: NSMenuItem!
    private let watcher: FieldSource = FocusWatcher()
    private let panel = HintPanel()
    private var anyAppMode = false
    private var started = false
    private var accessTimer: Timer?
    /// Findings the person already saw a hint for; not repeated this session.
    private var explained = Set<String>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMenu()
        HotKey.register { [weak self] in self?.checkNow() }
        // Text rules only look at what the person wrote or changed, so tabbing through
        // existing items stays quiet; the Sprint Goal check looks at the whole dialog.
        watcher.onFieldLeft = { [weak self] field, changed, nextLabel in
            self?.evaluate(field, changed: changed, nextLabel: nextLabel, askedByUser: false)
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

    private var settings: CoachSettings {
        let stored = UserDefaults.standard.integer(forKey: "averageVelocity")
        return CoachSettings(averageVelocity: stored > 0 ? stored : 10)
    }

    private func evaluate(_ field: FieldSnapshot, changed: Bool, nextLabel: String? = nil, askedByUser: Bool) {
        let outcome = CoachScope.shouldCoach(field.info, anyApp: anyAppMode)
            ? CoachRules.check(field: field.info, text: field.text, form: field.form,
                               changed: changed || askedByUser, settings: settings,
                               nextLabel: nextLabel, sprintTotal: field.sprintTotal, anyApp: anyAppMode)
            : .notApplicable
        switch outcome {
        case .hint(let hint):
            // Explain once per finding unless the person asks again.
            let key = hint.dedupeKey
            if !askedByUser && explained.contains(key) { return }
            panel.show(hint.message, near: field.frame) { [weak self] in self?.explained.insert(key) }
        case .fine(let message, let key):
            // Fixed now: if it goes wrong again later, explain it again.
            explained.remove(key)
            if askedByUser { panel.show(message, near: field.frame) }
        case .notApplicable:
            if askedByUser { panel.show(CoachMessages.nothingToCheck, near: field.frame) }
        }
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
        velocityItem = menu.addItem(withTitle: velocityTitle(), action: #selector(setVelocity), keyEquivalent: "")
        velocityItem.target = self
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
        evaluate(field, changed: true, askedByUser: true)
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
            "Dialog fields: \(field.form.isEmpty ? "none" : field.form.map { CoachRules.shortLabel($0.label) }.joined(separator: ", "))",
            "Sprint total on page: \(field.sprintTotal.map { String($0) } ?? "not found")",
        ]
        let message = CoachMessage(
            title: "What the coach sees",
            sections: [.init(heading: nil, text: lines.joined(separator: "\n"))],
            buttonTitle: "Close"
        )
        panel.show(message, near: field.frame)
    }

    private func velocityTitle() -> String {
        "Average velocity: \(settings.averageVelocity) points…"
    }

    /// The team's average velocity, used by SG-200. Stored on this Mac only.
    @objc private func setVelocity() {
        let alert = NSAlert()
        alert.messageText = "Team's average velocity"
        alert.informativeText = "The average number of story points the team finishes per Sprint. Items estimated above it get a tip about splitting."
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        input.stringValue = String(settings.averageVelocity)
        alert.accessoryView = input
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn,
              let value = Int(input.stringValue.trimmingCharacters(in: .whitespaces)), value > 0 else { return }
        UserDefaults.standard.set(value, forKey: "averageVelocity")
        velocityItem.title = velocityTitle()
    }

    @objc private func toggleAnyApp() {
        anyAppMode.toggle()
        anyAppItem.state = anyAppMode ? .on : .off
    }
}
