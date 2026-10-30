import AppKit
import ApplicationServices

/// Follows the keyboard focus in the frontmost app with an AXObserver.
/// When the focus leaves a field (another field, or another app), it reports
/// that field's final content, so the coach explains afterwards and never interrupts typing.
final class FocusWatcher: NSObject, FieldSource {
    /// The field that lost the focus, whether its text changed, and the next field's label.
    var onFieldLeft: ((FieldSnapshot, Bool, String?) -> Void)?

    /// The element that has the focus in the watched app right now.
    private(set) var current: AXUIElement? {
        didSet { textOnEntry = current.flatMap { AX.snapshot(of: $0)?.text } }
    }
    /// The text the current field had when it got the focus.
    private var textOnEntry: String?
    private var observer: AXObserver?

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

        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            Unmanaged<FocusWatcher>.fromOpaque(refcon).takeUnretainedValue().focusMoved(to: element)
        }
        var created: AXObserver?
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(created, appElement, kAXFocusedUIElementChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        current = AX.focusedElement(ofApp: appElement)
    }

    private func stopObserving() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        current = nil
    }

    private func focusMoved(to element: AXUIElement?) {
        if let previous = current {
            let left = element.map { !CFEqual(previous, $0) } ?? true
            if left, let snapshot = AX.snapshot(of: previous) {
                onFieldLeft?(snapshot, snapshot.text != (textOnEntry ?? ""), element.map(AX.label(of:)))
            }
        }
        current = element
    }

    func currentField() -> FieldSnapshot? {
        guard let element = current ?? AX.focusedElementSystemWide() else { return nil }
        return AX.snapshot(of: element)
    }
}
