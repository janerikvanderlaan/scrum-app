import AppKit
import ApplicationServices
import CoachCore

/// Follows the keyboard focus in the frontmost app. When the focus leaves a field
/// (another field, or another app), it reports that field's final content, so the
/// coach explains afterwards and never interrupts typing.
///
/// CoachProbe showed (2026-10-31) that Safari sends no focus notification for most moves in
/// Jira, and that the ones it sends name an empty window instead of the field. So the focus
/// is followed by asking the app a few times a second; notifications only make it ask sooner.
final class FocusWatcher: NSObject, FieldSource {
    /// The field that lost the focus, and whether its text changed.
    var onFieldLeft: ((FieldSnapshot, Bool) -> Void)?
    var onButtonPressed: ((ButtonPress) -> Bool)?
    var onFocusMoved: (() -> Void)?

    /// The element that has the focus in the watched app right now.
    private(set) var current: AXUIElement? {
        didSet {
            lastSnapshot = current.flatMap { AX.snapshot(of: $0, context: false) }
            textOnEntry = lastSnapshot?.text
        }
    }
    /// The text the current field had when it got the focus.
    private var textOnEntry: String?
    /// The current field as last read. Jira's inline editors (such as story points) disappear
    /// when you confirm them, without telling, so the field can't be read once the focus leaves it.
    private var lastSnapshot: FieldSnapshot?
    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var monitors: [Any] = []
    /// Sees clicks and Return before the app does, so a blocking rule can hold a press back.
    private var tap: CFMachPort?
    /// The mouse-down was held back, so its mouse-up is held back too.
    private var holdMouseUp = false
    private var pollTimer: Timer?
    /// The page texts around the "Start sprint" button on the backlog, read when it was clicked:
    /// Jira's Start Sprint dialog may hide the rest of the page while it is open.
    private var backlogTexts: [String] = []

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        if let app = NSWorkspace.shared.frontmostApplication { observe(app) }
        // Only the element under a click is looked at, to recognise buttons such as Start, and only
        // Return among the keys (it submits a dialog); nothing is recorded.
        let tapped = installTap()
        // Shown in Terminal, so we can tell from there whether blocking rules can work.
        print(tapped ? "Coach: can hold back a click on Start (blocking rules on)."
                     : "Coach: can't hold back clicks (event tap refused), blocking rules only explain.")
        if !tapped {
            // Without the tap the coach can still explain afterwards, but not hold a step back.
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
                _ = self?.mouseDown(at: event.cgEvent?.location ?? .zero)
            }) { monitors.append(monitor) }
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
                if event.keyCode == 36 || event.keyCode == 76 { _ = self?.returnPressed() }
            }) { monitors.append(monitor) }
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        // The coach's own windows don't count as leaving the field.
        guard app.processIdentifier != getpid() else { return }
        focusMoved(to: nil)
        observe(app)
    }

    private func observe(_ app: NSRunningApplication) {
        stopObserving()
        let pid = app.processIdentifier
        guard pid != getpid() else { return }

        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<FocusWatcher>.fromOpaque(refcon).takeUnretainedValue()
            if (notification as String) == kAXValueChangedNotification {
                watcher.valueChanged(in: element)
            } else {
                // Don't trust the element named here (Safari names an empty window); ask now.
                watcher.poll()
            }
        }
        var created: AXObserver?
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(created, appElement, kAXFocusedUIElementChangedNotification as CFString, refcon)
        AXObserverAddNotification(created, appElement, kAXValueChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        self.appElement = appElement
        current = focusedNow()
    }

    private func stopObserving() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        appElement = nil
        current = nil
    }

    /// What the watched app says has the focus, asked directly.
    private func focusedNow() -> AXUIElement? {
        guard let appElement else { return nil }
        return AX.focusedElement(ofApp: appElement)
    }

    /// Looks at the focus: reports a field that was left, else keeps the current field's reading fresh.
    private func poll() {
        guard appElement != nil else { return }
        let now = focusedNow()
        if let current, let now, CFEqual(current, now) {
            refreshCurrent()
        } else if current != nil || now != nil {
            focusMoved(to: now)
        }
    }

    private func focusMoved(to element: AXUIElement?) {
        if let previous = current {
            let left = element.map { !CFEqual(previous, $0) } ?? true
            // Read it once more for its final text; if it's gone (an inline editor that
            // closed), use what was read last while it had the focus. The field rules don't need
            // the dialog around it (the Sprint checks run on Start), so this stays cheap.
            if left, let snapshot = AX.snapshot(of: previous, context: false) ?? lastSnapshot {
                onFieldLeft?(snapshot, snapshot.text != (textOnEntry ?? ""))
            }
            if left { onFocusMoved?() }
        }
        current = element
    }

    func currentField() -> FieldSnapshot? {
        guard let element = focusedNow() ?? current ?? AX.focusedElementSystemWide() else { return nil }
        return AX.snapshot(of: element)
    }

    /// Keeps the last reading of the current field up to date while the person types.
    private func valueChanged(in element: AXUIElement) {
        guard let current, CFEqual(current, element) else { return }
        refreshCurrent()
    }

    private func refreshCurrent() {
        guard let current, let snapshot = AX.snapshot(of: current, context: false) else { return }
        lastSnapshot = snapshot
    }

    // MARK: Submitting a dialog

    /// An active event tap: clicks and keys pass through it before they reach the app.
    private func installTap() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let watcher = Unmanaged<FocusWatcher>.fromOpaque(refcon).takeUnretainedValue()
            return watcher.holds(type, event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    /// Whether to hold this event back. Everything else passes straight through.
    private func holds(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS switches a slow tap off; switch it on again.
            print("Coach: macOS paused the click check (\(type == .tapDisabledByTimeout ? "too slow" : "user input")); switched it on again.")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .leftMouseDown:
            // The coach's own windows (its tips, the reason dialog) are never held back.
            holdMouseUp = !isCoachInFront() && mouseDown(at: event.location)
            return holdMouseUp
        case .leftMouseUp:
            defer { holdMouseUp = false }
            return holdMouseUp
        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            return (code == 36 || code == 76) && !isCoachInFront() && returnPressed()
        default:
            return false
        }
    }

    private func isCoachInFront() -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
    }

    /// Mouse-down comes before the click takes effect, so the dialog can still be read.
    /// `point` is in Accessibility (and Core Graphics) coordinates: top-left of the main screen.
    private func mouseDown(at point: CGPoint) -> Bool {
        guard let button = AX.button(at: point) else { return false }
        let dialog = AX.dialog(containing: button)
        if dialog == nil, CoachRules.isStartButton(label: AX.buttonLabel(of: button)) {
            // "Start sprint" on the backlog opens the dialog: remember the Sprint totals shown now,
            // right after the click has gone through (reading the page takes a moment).
            DispatchQueue.main.async { [weak self] in self?.backlogTexts = AX.pageTexts(around: button) }
        }
        let started = Date()
        let held = report(label: AX.buttonLabel(of: button), from: button, dialog: dialog)
        if dialog != nil {
            print("Coach: button \"\(AX.buttonLabel(of: button))\" in a dialog, \(held ? "held back" : "let through") after \(Int(Date().timeIntervalSince(started) * 1000)) ms.")
        }
        return held
    }

    /// Return in a dialog's single-line field submits it, like clicking Start. In a text area it
    /// starts a new line and in a combo box it picks an option, so those are skipped.
    private func returnPressed() -> Bool {
        guard let element = focusedNow() ?? current,
              !["AXTextArea", "AXComboBox"].contains(AX.string(element, kAXRoleAttribute) ?? ""),
              let dialog = AX.dialog(containing: element) else { return false }
        return report(label: ButtonPress.returnKey, from: element, dialog: dialog)
    }

    private func report(label: String, from element: AXUIElement, dialog: AXUIElement?) -> Bool {
        let form = dialog.map(AX.formFields(in:)) ?? []
        // The page stays when the dialog closes, so the total can be read from it afterwards.
        let page = AX.webArea(of: element)
        let name = SprintGoalRule.key(form: form)
        let sprintTotal: () -> Double? = { [weak self] in
            guard SprintGoalRule.goalField(in: form) != nil else { return nil }
            return page.flatMap { SprintTotal.find(in: AX.pageTexts(around: $0), sprintName: name) }
                ?? SprintTotal.find(in: self?.backlogTexts ?? [], sprintName: name)
        }
        return onButtonPressed?(ButtonPress(label: label, pageURL: AX.pageURL(of: element),
                                            form: form, sprintTotal: sprintTotal, frame: AX.frame(of: element))) ?? false
    }
}
