import AppKit
import ApplicationServices
import CoachCore

/// Follows the keyboard focus in the frontmost app with an AXObserver.
/// When the focus leaves a field (another field, or another app), it reports
/// that field's final content, so the coach explains afterwards and never interrupts typing.
final class FocusWatcher: NSObject, FieldSource {
    /// The field that lost the focus, whether its text changed, and the next field's label.
    var onFieldLeft: ((FieldSnapshot, Bool, String?) -> Void)?

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
    /// when you confirm them, so the field can't be read any more once the focus leaves it.
    private var lastSnapshot: FieldSnapshot?
    private var observer: AXObserver?
    private var appElement: AXUIElement?

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        if let app = NSWorkspace.shared.frontmostApplication { observe(app) }
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
                watcher.focusMoved(to: watcher.resolve(element))
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
        current = AX.focusedElement(ofApp: appElement).map(resolve)
    }

    private func stopObserving() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        appElement = nil
        current = nil
    }

    private func focusMoved(to element: AXUIElement?) {
        if let previous = current {
            let left = element.map { !CFEqual(previous, $0) } ?? true
            // Read it once more for its final text; if it's gone (an inline editor that
            // closed), use what was read last while it had the focus.
            if left, let snapshot = AX.snapshot(of: previous) ?? lastSnapshot {
                onFieldLeft?(snapshot, snapshot.text != (textOnEntry ?? ""), element.map(AX.label(of:)))
            }
        }
        current = element
    }

    func currentField() -> FieldSnapshot? {
        guard let element = current ?? AX.focusedElementSystemWide() else { return nil }
        return AX.snapshot(of: resolve(element))
    }

    /// Keeps the last reading of the current field up to date while the person types.
    private func valueChanged(in element: AXUIElement) {
        guard let current, CFEqual(current, element), let snapshot = AX.snapshot(of: element, context: false) else { return }
        lastSnapshot = snapshot
    }

    /// Safari sometimes reports the window or the page as focused while a web input has
    /// the focus; ask for the focused element again and prefer a text field.
    private func resolve(_ element: AXUIElement) -> AXUIElement {
        if isTextField(element) { return element }
        if let appElement, let focused = AX.focusedElement(ofApp: appElement), isTextField(focused) { return focused }
        if let focused = AX.focusedElementSystemWide(), isTextField(focused) { return focused }
        return element
    }

    private func isTextField(_ element: AXUIElement) -> Bool {
        AX.string(element, kAXRoleAttribute).map(CoachScope.textRoles.contains) ?? false
    }
}
