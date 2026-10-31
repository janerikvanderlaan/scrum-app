import AppKit
import ApplicationServices
import CoachCore

/// Logs what the Accessibility API reports while you use the mouse and keyboard, so we can
/// see how the focus moves in an app (Jira in Safari) instead of guessing. It only reads and
/// writes a log; it never changes anything. Key presses are logged by kind (Tab, Return,
/// "character"), never by what you type; password and search fields are never read.
final class Probe: NSObject {
    private let showText: Bool
    private let log: ProbeLog
    private var observer: AXObserver?
    private var watchedApp: NSRunningApplication?
    private var monitors: [Any] = []
    private var pollTimer: Timer?
    /// The focused element as last reported by a notification or the poll, and its value then.
    private var lastFocus: AXUIElement?
    private var lastValue: String?
    private var markers = 0
    /// The app the probe was started from (Terminal). Its text changes with every line the probe
    /// writes, so watching it would log the probe's own output in an endless loop.
    private let ownTerminal = Probe.hostApp()

    init(showText: Bool, log: ProbeLog) {
        self.showText = showText
        self.log = log
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        if let ownTerminal { log.write("app", "\(ownTerminal.localizedName ?? "?") is where the probe writes; it is not watched") }
        if let app = NSWorkspace.shared.frontmostApplication {
            log.write("app", "at start: \(app.localizedName ?? "?") (\(app.bundleIdentifier ?? "no bundle id"), pid \(app.processIdentifier))")
            observe(app)
        }

        let mouse: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .rightMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mouse, handler: { [weak self] event in
            self?.mouse(event)
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.key(event)
        }) { monitors.append(monitor) }

        // Notifications can be missed (Safari doesn't always send them), so also look 4 times a second.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
    }

    // MARK: Apps

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        log.write("app", "\(app.localizedName ?? "?") (\(app.bundleIdentifier ?? "no bundle id"), pid \(app.processIdentifier))")
        observe(app)
    }

    private static let notifications = [
        kAXFocusedUIElementChangedNotification,
        kAXValueChangedNotification,
        kAXFocusedWindowChangedNotification,
        kAXWindowCreatedNotification,
        kAXUIElementDestroyedNotification,
        kAXSheetCreatedNotification,
        kAXMenuOpenedNotification,
        kAXMenuClosedNotification,
    ]

    private func observe(_ app: NSRunningApplication) {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        watchedApp = app
        let pid = app.processIdentifier
        guard pid != getpid() else { return }
        if pid == ownTerminal?.processIdentifier {
            lastFocus = nil
            lastValue = nil
            return log.write("app", "  not watched: the probe writes its log here")
        }

        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            Unmanaged<Probe>.fromOpaque(refcon).takeUnretainedValue().notified(notification as String, element)
        }
        var created: AXObserver?
        let status = AXObserverCreate(pid, callback, &created)
        guard status == .success, let created else {
            return log.write("error", "can't observe \(app.localizedName ?? "?"): AXError \(status.rawValue)")
        }
        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var failed: [String] = []
        for name in Self.notifications {
            let result = AXObserverAddNotification(created, appElement, name as CFString, refcon)
            if result != .success && result != .notificationAlreadyRegistered { failed.append("\(name) (\(result.rawValue))") }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        if !failed.isEmpty { log.write("error", "not reported by this app: \(failed.joined(separator: ", "))") }
        if let focused = ProbeAX.element(appElement, kAXFocusedUIElementAttribute) { remember(focused) }
        log.write("focus", "at start: \(describe(lastFocus))")
    }

    // MARK: Accessibility notifications

    private func notified(_ name: String, _ element: AXUIElement) {
        switch name {
        case kAXFocusedUIElementChangedNotification:
            remember(element)
            log.write("focus", describe(element))
            // Safari sometimes names the window or page here while a field has the focus.
            if let app = watchedApp,
               let asked = ProbeAX.element(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedUIElementAttribute),
               !CFEqual(asked, element) {
                log.write("focus", "  but the app says the focus is on: \(describe(asked))")
            }
        case kAXValueChangedNotification:
            let isFocus = lastFocus.map { CFEqual($0, element) } ?? false
            if isFocus { lastValue = value(of: element) }
            log.write("value", "\(isFocus ? "" : "(not the focused element) ")\(describe(element))")
        case kAXUIElementDestroyedNotification:
            // A destroyed element can't be read any more; say when it was the focused one.
            if let lastFocus, CFEqual(lastFocus, element) {
                log.write("gone", "the focused element was removed (an inline editor that closed?)")
            }
        default:
            let short = name.hasPrefix("AX") ? String(name.dropFirst(2)) : name
            log.write("window", "\(short): \(describe(element))")
        }
    }

    // MARK: Poll

    private func poll() {
        if let watchedApp, watchedApp.processIdentifier == ownTerminal?.processIdentifier { return }
        guard let focused = ProbeAX.element(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute) else {
            if lastFocus != nil {
                log.write("poll", "no focused element (no notification was sent)")
                lastFocus = nil
                lastValue = nil
            }
            return
        }
        if let lastFocus, CFEqual(lastFocus, focused) {
            let now = value(of: focused)
            if now != lastValue {
                log.write("poll", "value changed without a notification: \(describe(focused))")
                lastValue = now
            }
        } else {
            log.write("poll", "focus moved without a notification: \(describe(focused))")
            remember(focused)
        }
    }

    /// The first app among the probe's parent processes (swift run, the shell, …, Terminal).
    private static func hostApp() -> NSRunningApplication? {
        var pid = getppid()
        for _ in 0..<10 where pid > 1 {
            if let app = NSRunningApplication(processIdentifier: pid) { return app }
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
            pid = info.kp_eproc.e_ppid
        }
        return nil
    }

    private func remember(_ element: AXUIElement) {
        lastFocus = element
        lastValue = value(of: element)
    }

    // MARK: Mouse and keys

    private func mouse(_ event: NSEvent) {
        let kind: String
        switch event.type {
        case .leftMouseDown: kind = event.clickCount > 1 ? "double-click down" : "down"
        case .leftMouseUp: kind = "up"
        default: kind = "right-click"
        }
        // AppKit counts from the bottom-left of the main screen, Accessibility from the top-left.
        let location = NSEvent.mouseLocation
        let height = NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: location.x, y: height - location.y)
        var hit: AXUIElement?
        AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit)
        var details = "\(kind) at (\(Int(point.x)), \(Int(point.y))) on \(describe(hit))"
        if let hit, let button = ProbeAX.ancestor(of: hit, role: "AXButton"), !CFEqual(button, hit) {
            details += "\n                inside button: \(describe(button))"
        }
        log.write("click", details)
    }

    private func key(_ event: NSEvent) {
        let flags = event.modifierFlags
        // Control-Option-M writes a marker line, so you can point at a moment ("now I click Start").
        if event.keyCode == 46, flags.contains(.control), flags.contains(.option) {
            markers += 1
            return log.write("mark", "----- marker \(markers) -----")
        }
        let name = ProbeFormat.keyName(keyCode: event.keyCode, shift: flags.contains(.shift),
                                       control: flags.contains(.control), option: flags.contains(.option),
                                       command: flags.contains(.command))
        log.write("key", name + (event.isARepeat ? " (held)" : ""))
    }

    // MARK: Describing elements

    private func value(of element: AXUIElement) -> String? {
        let subrole = ProbeAX.string(element, kAXSubroleAttribute)
        if subrole.map(CoachScope.skippedSubroles.contains) == true { return nil }
        return ProbeAX.textValue(element)
    }

    private func describe(_ element: AXUIElement?) -> String {
        guard let element else { return "nothing" }
        guard let role = ProbeAX.string(element, kAXRoleAttribute) else { return "an element that can't be read" }
        var parts = [role + (ProbeAX.string(element, kAXSubroleAttribute).map { "/\($0)" } ?? "")]
        let label = ProbeAX.label(of: element)
        parts.append("label=" + (label.isEmpty ? "-" : "\"\(label)\""))
        let subrole = ProbeAX.string(element, kAXSubroleAttribute)
        if subrole.map(CoachScope.skippedSubroles.contains) == true {
            parts.append("value=(not read)")
        } else if let text = ProbeAX.textValue(element) {
            parts.append("value=" + ProbeFormat.preview(text, showText: showText))
        }
        if let frame = ProbeAX.frame(of: element) {
            parts.append("at=(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)))")
        }
        if let dialog = ProbeAX.dialog(containing: element) {
            let name = ProbeAX.label(of: dialog)
            parts.append("in dialog" + (name.isEmpty ? "" : " \"\(name)\""))
        }
        if let host = ProbeAX.pageURL(of: element).flatMap({ URL(string: $0)?.host }) { parts.append("page=\(host)") }
        return parts.joined(separator: " ")
    }
}

/// Writes each line to the Terminal and to the log file straight away.
final class ProbeLog {
    let url: URL
    private let handle: FileHandle?

    init(folder: URL) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        url = folder.appendingPathComponent("coach-probe-\(formatter.string(from: Date())).log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    func write(_ tag: String, _ details: String) {
        let line = ProbeFormat.line(at: Date(), tag: tag, details)
        print(line)
        fflush(stdout)
        handle?.write(Data((line + "\n").utf8))
    }
}
