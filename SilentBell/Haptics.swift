import WatchKit

/// The haptic palette. Four distinct signals that must never be confusable:
/// the reminder tap, the start/stop confirmations, and the paused alert.
/// Kept as single constants/functions so each can be retuned by ear.
enum Haptics {
    /// Key shared with the in-app picker (`@AppStorage`) so the reminder tap is
    /// user-selectable at runtime rather than a compile-time constant.
    static let reminderKey = "reminderHapticRaw"

    /// The reminder tap, read live from the user's picker choice. Defaults to `.start`.
    static var reminder: WKHapticType {
        if let raw = UserDefaults.standard.object(forKey: reminderKey) as? Int,
           let type = WKHapticType(rawValue: raw) {
            return type
        }
        return .start
    }

    static func playReminder() {
        WKInterfaceDevice.current().play(reminder)
    }

    /// Ascending two-part "started" confirmation.
    static func playStarted() {
        let device = WKInterfaceDevice.current()
        device.play(.start)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { device.play(.directionUp) }
    }

    /// Descending two-part "stopped" confirmation — the mirror of `playStarted`,
    /// and deliberately shorter than the three-part paused alert so a stop the user
    /// chose never feels like a session that ended on its own.
    static func playStopped() {
        let device = WKInterfaceDevice.current()
        device.play(.directionDown)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { device.play(.stop) }
    }

    /// Descending three-part "paused — resume" alert.
    static func playPaused() {
        let device = WKInterfaceDevice.current()
        device.play(.directionDown)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { device.play(.stop) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { device.play(.failure) }
    }
}
