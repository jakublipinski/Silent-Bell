import Foundation
import WatchKit

/// One diagnostic line: every scheduled and fired tap, plus lifecycle events.
struct LogEntry: Identifiable, Codable {
    var id = UUID()
    let time: Date
    let kind: String
    let detail: String
}

/// The diagnostic log, **persisted to disk**.
///
/// The in-memory log died with the process, which is exactly when the interesting
/// failures happen — an early `suppressedBySystem` death or a watchdog kill would
/// erase its own evidence. Entries are written on every append, so the log survives
/// the app being terminated and can be exported afterwards.
final class LogStore: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []

    private let fileURL: URL
    private let maxEntries = 400        // a developer aid, not a data store

    init() {
        let dir = (try? FileManager.default.url(for: .documentDirectory,
                                                in: .userDomainMask,
                                                appropriateFor: nil,
                                                create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL = dir.appendingPathComponent("silentbell-log.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([LogEntry].self, from: data) {
            entries = decoded
        }
    }

    /// Newest first, matching how the log is read on screen.
    ///
    /// Every entry is stamped with the battery snapshot. Battery used to be
    /// recorded only at session invalidation, which made drain analysis lopsided:
    /// active sessions were bracketed by readings, idle gaps never were, so the
    /// idle rate could only be inferred. With a reading on every line — including
    /// `started` and `launched` — each idle gap gets a clean before/after pair.
    func append(_ kind: String, _ time: Date = Date(), _ detail: String = "") {
        let stamped = detail.isEmpty
            ? Self.batterySnapshot()
            : "\(detail) · \(Self.batterySnapshot())"
        entries.insert(LogEntry(time: time, kind: kind, detail: stamped), at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        persist()
    }

    /// Battery percentage, charging state and Low Power Mode, e.g.
    /// `battery=85% state=unplugged lowPower=false`.
    static func batterySnapshot() -> String {
        let dev = WKInterfaceDevice.current()
        dev.isBatteryMonitoringEnabled = true
        let pct = dev.batteryLevel < 0 ? "unknown" : "\(Int(dev.batteryLevel * 100))%"
        let state: String
        switch dev.batteryState {
        case .unknown: state = "unknown"
        case .unplugged: state = "unplugged"
        case .charging: state = "charging"
        case .full: state = "full"
        @unknown default: state = "?"
        }
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        return "battery=\(pct) state=\(state) lowPower=\(lowPower)"
    }

    func clear() {
        entries = []
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Export

    /// The whole log plus device context as plain text, ready to share or paste.
    /// Oldest first — a report reads forwards even though the screen reads backwards.
    func exportText() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var out = ["Silent Bell — diagnostic log", Self.deviceContext(), ""]
        for e in entries.reversed() {
            let detail = e.detail.isEmpty ? "" : "  \(e.detail)"
            out.append("\(f.string(from: e.time))  \(e.kind)\(detail)")
        }
        out.append("")
        out.append("\(entries.count) entries")
        return out.joined(separator: "\n")
    }

    /// Everything needed to reproduce a report, and nothing identifying.
    static func deviceContext() -> String {
        let device = WKInterfaceDevice.current()
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"

        var sys = utsname()
        uname(&sys)
        let machine = withUnsafeBytes(of: &sys.machine) { raw -> String in
            guard let base = raw.baseAddress else { return "?" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }

        let bounds = device.screenBounds
        return """
        app \(version) (\(build)) · tag \(buildTag)
        \(device.systemName) \(device.systemVersion) · \(machine) · \
        \(Int(bounds.width))x\(Int(bounds.height))@\(Int(device.screenScale))x
        locale \(Locale.current.identifier) · tz \(TimeZone.current.identifier)
        """
    }
}
