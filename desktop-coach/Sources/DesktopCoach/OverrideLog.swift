import Foundation
import CoachCore

/// Every "Start anyway" with its reason, one JSON line each, kept on this Mac only:
/// ~/Library/Application Support/DesktopCoach/overrides.log. It's for the team's own
/// Retrospective; nothing is sent anywhere.
enum OverrideLog {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DesktopCoach/overrides.log")
    }

    static func append(_ hints: [Hint], reason: String) {
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        let time = ISO8601DateFormatter().string(from: Date())
        for hint in hints {
            let entry: [String: String] = ["time": time, "rule": hint.ruleID, "about": hint.key, "reason": reason]
            if let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) {
                handle.write(data + Data("\n".utf8))
            }
        }
    }
}
