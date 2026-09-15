import WatchKit

/// The haptic palette: the reminder tap, which Start and Stop also play, and
/// the paused alert. The paused alert is the one that must never be mistaken
/// for a reminder, since both arrive unprompted.
/// Kept as single constants/functions so each can be retuned by ear.
enum Haptics {
    /// Key shared with the in-app picker (`@AppStorage`) so the reminder tap is
    /// user-selectable at runtime rather than a compile-time constant.
    static let reminderKey = "reminderHapticRaw"

    /// Stored ids of the multi-tick patterns, outside `WKHapticType`'s range,
    /// which the single built-in types use as their ids (see `TapChoice`).
    static let doubleTickID = 1002
    static let tripleTickID = 1003

    /// The tap used until the user picks one: Double tick, because it is silent
    /// even with Silent Mode off. It is both the picker's `@AppStorage` default
    /// and the fallback in `reminder`. `@AppStorage` never writes its default,
    /// so the two must be one value, or the settings row would name one tap
    /// while another played.
    static let defaultTapID = doubleTickID

    /// Gap between the clicks of a multi-tick pattern. Closer together the
    /// Taptic Engine can blur them into one; further apart they stop reading as
    /// a single signal. The other two-part patterns below use 0.18 s.
    static let tickSpacing: TimeInterval = 0.2

    /// The reminder tap, read live from the user's picker choice. Falls back to
    /// `defaultTapID` when nothing has been chosen, or the stored value is not
    /// a current choice.
    static var reminder: [WKHapticType] {
        let raw = UserDefaults.standard.object(forKey: reminderKey) as? Int
        let choice = hapticChoices.first { $0.id == raw }
            ?? hapticChoices.first { $0.id == defaultTapID }
        return choice?.haptics ?? [.click]
    }

    static func playReminder() {
        play(reminder)
    }

    /// Plays haptics in sequence, `tickSpacing` apart.
    static func play(_ pattern: [WKHapticType]) {
        let device = WKInterfaceDevice.current()
        for (i, type) in pattern.enumerated() {
            if i == 0 { device.play(type); continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + tickSpacing * Double(i)) {
                device.play(type)
            }
        }
    }

    /// "Started" confirmation: the user's chosen tap, so pressing Start doubles
    /// as a preview of every reminder, and is silent whenever that tap is. It
    /// was `.start` → `.directionUp`, both of which sound when the Watch is not
    /// in Silent Mode.
    static func playStarted() {
        play(reminder)
    }

    /// "Stopped" confirmation: the chosen tap, like Start. The paused alert
    /// keeps its own pattern, so a stop the user chose never feels like a
    /// session that ended on its own.
    static func playStopped() {
        play(reminder)
    }

    /// Descending three-part "paused — resume" alert. Deliberately not the
    /// chosen tap: it marks the end of the session rather than a reminder, and
    /// like a notification it sounds unless the Watch is in Silent Mode.
    static func playPaused() {
        let device = WKInterfaceDevice.current()
        device.play(.directionDown)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { device.play(.stop) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { device.play(.failure) }
    }
}

/// One row of the Tap Type picker: the name shown (also its string-catalog
/// key), the value stored in `@AppStorage`, and the built-in haptics it plays.
///
/// A single built-in type stores its own `WKHapticType.rawValue`, so a choice
/// saved by any earlier version still resolves unchanged. The multi-tick
/// patterns are not WKHapticTypes and use ids well outside that enum's range.
struct TapChoice {
    let name: String
    let id: Int
    let haptics: [WKHapticType]
    /// A shorter form for rows too narrow for `name` ("2× Tick"), if it has one.
    let shortName: String?

    /// True when every haptic in it is `.click`, the only built-in type watchOS
    /// plays without a sound when Silent Mode is off. Worked out from the
    /// haptics rather than set by hand, so a new choice can't be mislabelled.
    var isSilent: Bool { haptics.allSatisfy { $0 == .click } }

    init(_ name: String, _ type: WKHapticType, short: String? = nil) {
        self.name = name
        self.id = type.rawValue
        self.haptics = [type]
        self.shortName = short
    }

    init(_ name: String, id: Int, ticks: Int, short: String? = nil) {
        self.name = name
        self.id = id
        self.haptics = Array(repeating: .click, count: ticks)
        self.shortName = short
    }
}

/// The reminder haptics, named for how they feel rather than for the API constant.
///
/// The ticks come first because they are the only silent ones. With the
/// Watch's Silent Mode off, watchOS plays a system sound with every built-in
/// haptic except `.click`, and no public API reports Silent Mode, so the app
/// cannot tell which case it is in. The rest stay for people who keep Silent
/// Mode on and want a stronger tap.
let hapticChoices: [TapChoice] = [
    TapChoice("Tick", .click, short: "1× Tick"),
    TapChoice("Double tick", id: Haptics.doubleTickID, ticks: 2, short: "2× Tick"),
    TapChoice("Triple tick", id: Haptics.tripleTickID, ticks: 3, short: "3× Tick"),
    TapChoice("Gentle", .start),
    TapChoice("Knock", .notification),
    TapChoice("Double", .success),
    TapChoice("Rise", .directionUp),
    TapChoice("Fall", .directionDown),
    TapChoice("Firm", .stop),
    TapChoice("Heavy", .failure),
    TapChoice("Echo", .retry),
]
