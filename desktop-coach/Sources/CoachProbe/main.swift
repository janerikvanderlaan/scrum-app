import AppKit
import ApplicationServices

// CoachProbe: logs focus, value, window, click and key events so we can see what the
// Accessibility API really reports. Start it with `swift run CoachProbe`; stop with Control-C.
// `--no-text` logs only the length of field values instead of a preview.
let showText = !CommandLine.arguments.contains("--no-text")
let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("coach-probe-logs")
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let probeLog = ProbeLog(folder: folder)
let probe = Probe(showText: showText, log: probeLog)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

print("CoachProbe: logging to \(probeLog.url.path)")
print("Press Control-Option-M to add a marker line, Control-C here to stop.")
print(showText ? "Field values are shown as a short preview (start with --no-text to hide them)." : "Field values are hidden; only their length is logged.")

let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
if AXIsProcessTrustedWithOptions(prompt) {
    probe.start()
} else {
    print("Waiting for Accessibility access: System Settings > Privacy & Security > Accessibility > Terminal.")
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
        guard AXIsProcessTrusted() else { return }
        timer.invalidate()
        print("Access granted, logging starts.")
        probe.start()
    }
}
app.run()
