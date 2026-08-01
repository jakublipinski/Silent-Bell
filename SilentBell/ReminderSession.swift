import Foundation
import Combine
import WatchKit
import UserNotifications
import os

/// Unified-log channel. Persists in the system log independent of the app process,
/// so entries survive the session being suppressed or the app being killed.
/// Filter in Console/`log` with:  subsystem:app.silentbell.watch
private let rlog = Logger(subsystem: "app.silentbell.watch", category: "session")

/// Owns the extended runtime session, drives the scheduler one tap at a time, and
/// plays the haptics. Starting a session requires the app to be foreground/active
/// (a platform rule). When a session ends for any reason other than the user
/// stopping it, a self-clearing "resume" local notification nudges the user;
/// tapping it relaunches the app and auto-starts. That notification is also
/// pre-scheduled for the expiry moment so it still fires if the app is killed
/// before it can run cleanup.
final class ReminderSession: NSObject, ObservableObject, WKExtendedRuntimeSessionDelegate,
                             UNUserNotificationCenterDelegate {
    /// The four states the UI renders. `paused` means the session ended on its own
    /// (time limit or system suppression) and is waiting to be resumed.
    enum Phase { case stopped, starting, active, paused }

    @Published private(set) var phase: Phase = .stopped
    @Published private(set) var nextFire: Date?
    @Published private(set) var expiry: Date?
    let logStore = LogStore()
    /// Set when the resume notification is tapped; ContentView consumes it once active.
    @Published var shouldAutoStart = false

    private var session: WKExtendedRuntimeSession?
    private var scheduler: Scheduler<SystemRandomNumberGenerator>?
    private var pending: DispatchWorkItem?
    private var config = ScheduleConfig()
    private var startedAt: Date?
    /// True once the resume notification has been posted for this session, so
    /// `didInvalidate` does not post a second one over the top.
    private var didPostResume = false

    private let resumeID = "resume"
    private let resumeCategory = "RESUME_CATEGORY"
    private let resumeAction = "RESUME_ACTION"

    var isActive: Bool { phase == .active }

    /// The session ended on its own (time limit or system suppression) and is
    /// waiting for the user to resume — as opposed to being stopped deliberately.
    var isPaused: Bool { phase == .paused }

    override init() {
        super.init()
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        UNUserNotificationCenter.current().delegate = self

        // A tappable "Resume" button on the notification itself. `.foreground` is
        // essential: a background action could not start a session, since sessions
        // may only be started while the app is active.
        let action = UNNotificationAction(identifier: resumeAction,
                                          title: "Resume",
                                          options: [.foreground])
        let category = UNNotificationCategory(identifier: resumeCategory,
                                              actions: [action],
                                              intentIdentifiers: [],
                                              options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])

        logStore.append("launched", Date(), LogStore.deviceContext().replacingOccurrences(of: "\n", with: " · "))
        rlog.notice("ReminderSession init")
    }

    /// Ask for notification permission only once the user has been told what the
    /// notification is *for* — i.e. after the intro explains that sessions pause and
    /// need resuming. Asking at launch shows a bare system dialog before the app has
    /// said anything, which reads as thoughtless and is what Apple's own guidance
    /// warns against.
    ///
    /// Deliberately never called while starting a session: a system alert can take
    /// the app out of the active state, and an extended runtime session may only be
    /// started while active.
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, err in
                rlog.notice("notif auth granted=\(granted) err=\(String(describing: err), privacy: .public)")
            }
        }
    }

    // MARK: - Start / stop

    func start(config: ScheduleConfig) {
        self.config = config
        cancelTimer()
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        session = s
        phase = .starting
        rlog.notice("start requested — \(Self.configSummary(config), privacy: .public); \(Self.context(), privacy: .public)")
        s.start()                       // session begins when the app is active
    }

    func stop() {
        cancelTimer()
        clearResumeNotifications()      // deliberate stop — cancel any pending nudge
        session?.invalidate()           // fires didInvalidate with reason .none
        session = nil
        nextFire = nil
        expiry = nil
        phase = .stopped
        Haptics.playStopped()           // confirm the deliberate stop on the wrist
        rlog.notice("stopped (user) — \(Self.context(), privacy: .public)")
    }

    /// Called by ContentView once the app is active, so a session start is legal.
    func autoStartIfRequested(config: ScheduleConfig) {
        guard shouldAutoStart else { return }
        shouldAutoStart = false
        rlog.notice("auto-start from notification tap")
        start(config: config)
    }

    private func cancelTimer() {
        pending?.cancel()
        pending = nil
    }

    /// Dev helper: fire the resume notification (in ~5s, giving you time to lower
    /// your wrist / background the app) so the notify → tap → auto-start flow can be
    /// verified without waiting for a real session end.
    func fireTestResume() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            rlog.notice("test resume: authStatus=\(s.authorizationStatus.rawValue) alert=\(s.alertSetting.rawValue)")
        }
        rlog.notice("test resume notification scheduled (5s)")
        scheduleResumeNotification(fireAt: Date().addingTimeInterval(5), passive: false)
    }

    /// Dev helper: the graceful-expiry sequence as actually experienced — our
    /// Focus-proof haptic, then the silent (`.passive`) resume notification.
    func fireTestResumePassive() {
        // Mirrors the real graceful-expiry order: notification first, haptic second,
        // both immediately. Simulating the old order (haptic, then a delayed
        // notification) would reproduce the very lag this was changed to remove.
        rlog.notice("test PASSIVE resume: silent notification now, then haptic")
        scheduleResumeNotification(fireAt: nil, passive: true)
        Haptics.playPaused()
    }

    // MARK: - Scheduling (one tap at a time)

    private func scheduleNext() {
        guard isActive, let scheduler else { return }
        let now = Date()
        guard let fire = scheduler.nextFire(after: now) else {
            nextFire = nil
            rlog.error("scheduler returned no next fire")
            return
        }
        nextFire = fire
        // Log at *now* with the target in the detail. Stamping the entry with the
        // future fire time made exported logs appear out of chronological order —
        // a "scheduled" line for 14:27 sat above a "pausing" line from 14:14.
        logStore.append("scheduled", Date(), "next at \(Self.hm(fire))")
        rlog.notice("scheduled next fire at \(Self.hm(fire), privacy: .public) (in \(Int(fire.timeIntervalSinceNow))s)")
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isActive else { return }
            Haptics.playReminder()
            self.logStore.append("fired", Date())
            rlog.notice("fired tap — \(Self.context(), privacy: .public)")
            self.scheduleNext()
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, fire.timeIntervalSinceNow), execute: item)
    }

    // MARK: - Resume notification

    /// Schedule the single "resume" notification. `fireAt == nil` delivers it
    /// immediately; a date pre-schedules it (the killed-app safety net). Same
    /// identifier each time, so a new schedule replaces the old rather than
    /// stacking up.
    ///
    /// `passive == true` uses the `.passive` interruption level: filed with no
    /// alerting haptic, no screen wake and — as it turns out — no unread indicator
    /// on the watch face. Every real path now passes `false`; only the developer
    /// screen still posts a passive one, kept so the two can be compared on-device.
    private func scheduleResumeNotification(fireAt date: Date?, passive: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "Silent Bell paused"
        content.body = "Tap Resume to start a new session."
        content.sound = nil             // never any sound
        content.categoryIdentifier = resumeCategory
        content.interruptionLevel = passive ? .passive : .active
        // A nil trigger delivers immediately. Only the pre-scheduled safety net
        // needs a timed one, and UNTimeIntervalNotificationTrigger rejects
        // intervals <= 0 — hence the floor on that path only.
        let trigger: UNNotificationTrigger? = date.map {
            UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0.timeIntervalSinceNow),
                                              repeats: false)
        }
        let req = UNNotificationRequest(identifier: resumeID, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [resumeID])
        center.add(req)
    }

    private func clearResumeNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [resumeID])
        center.removeDeliveredNotifications(withIdentifiers: [resumeID])
    }

    // MARK: - WKExtendedRuntimeSessionDelegate

    func extendedRuntimeSessionDidStart(_ s: WKExtendedRuntimeSession) {
        DispatchQueue.main.async {
            self.phase = .active
            self.startedAt = Date()
            self.didPostResume = false
            self.expiry = s.expirationDate
            // Anchor the bucket grid to the start moment so all taps land inside this session.
            self.scheduler = Scheduler(config: self.config,
                                       rng: SystemRandomNumberGenerator(),
                                       epoch: self.startedAt ?? Date())
            Haptics.playStarted()
            let exp = self.expiry.map { Self.hm($0) } ?? "?"
            self.logStore.append("started", Date(), "expires \(exp)")
            rlog.notice("session STARTED — expires \(exp, privacy: .public); \(Self.context(), privacy: .public)")

            // A fresh start clears any delivered nudge, then pre-schedules the safety
            // net for the expiry moment (fires even if the app is killed first).
            // Active: if the app was killed it never got to buzz, so this must alert.
            self.clearResumeNotifications()
            self.scheduleResumeNotification(fireAt: s.expirationDate, passive: false)

            self.scheduleNext()
            self.requestNotificationPermission()   // safe now: session already started
        }
    }

    func extendedRuntimeSessionWillExpire(_ s: WKExtendedRuntimeSession) {
        DispatchQueue.main.async {
            self.logStore.append("pausing", Date(), "session ending — resume")
            rlog.notice("willExpire (graceful) — \(Self.context(), privacy: .public)")

            // Post the notification *before* the haptic, and both from here rather
            // than from didInvalidate. watchOS calls willExpire seconds ahead of the
            // cap so an app can wind down while its session is still valid; posting
            // at didInvalidate meant the nudge trailed the haptic by that whole
            // window — long enough that raising your wrist showed nothing, and the
            // notification appeared a few seconds later.
            //
            // Alerting, not passive. Passive filed the notification so quietly that
            // nothing marked the session as over: no screen wake, and no unread dot
            // on the watch face either. Once the haptic faded there was no trace,
            // which is how hours of a day were lost to sessions that had quietly
            // ended. The cost is a second buzz from the notification itself, and it
            // now lands together with ours rather than as a delayed echo.
            self.scheduleResumeNotification(fireAt: nil, passive: false)
            self.didPostResume = true

            Haptics.playPaused()        // session still valid here, so the haptic lands (Focus-proof)
        }
    }

    func extendedRuntimeSession(_ s: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                error: Error?) {
        DispatchQueue.main.async {
            self.cancelTimer()
            self.nextFire = nil
            self.session = nil

            let ran = self.startedAt.map { Int(Date().timeIntervalSince($0)) } ?? -1
            var errStr = "none"
            if let e = error as NSError? {
                errStr = "\(e.domain)#\(e.code): \(e.localizedDescription)"
            }
            let detail = "reason \(reason.rawValue) (\(Self.reasonName(reason))) ran=\(ran)s"
            self.logStore.append("invalidated", Date(), "\(detail) · \(Self.context())")
            rlog.error("session INVALIDATED — \(detail, privacy: .public); err=\(errStr, privacy: .public); \(Self.context(), privacy: .public)")

            if reason == .sessionInProgress {
                // The resume notification is posted at willExpire, seconds before the
                // outgoing session actually dies. Tapping it inside that window asks
                // for a new session while the old one still holds the single slot,
                // and watchOS refuses. Wait for the old one to expire and try again,
                // rather than stranding the user on Paused after they asked to resume.
                self.logStore.append("retrying", Date(), "previous session still alive")
                rlog.notice("start refused (session in progress) — retrying shortly")
                let cfg = self.config
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    guard let self, self.phase != .active else { return }
                    self.start(config: cfg)
                }
            } else if reason == .none {
                // Deliberate stop — no nudge; stop() already set the phase.
                self.clearResumeNotifications()
            } else {
                self.phase = .paused
                // A graceful expiry has already posted from willExpire. This branch
                // is now only the early-death path: the system cut the session short
                // with no warning, so nothing has buzzed and the notification is the
                // only possible cue — it must alert.
                if !self.didPostResume {
                    self.scheduleResumeNotification(fireAt: nil, passive: false)
                    self.didPostResume = true
                }
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Both the "Resume" button and tapping the notification body itself should
        // relaunch and start; only an explicit dismiss should do nothing.
        let wasDismissed = response.actionIdentifier == UNNotificationDismissActionIdentifier
        if response.notification.request.identifier == resumeID, !wasDismissed {
            DispatchQueue.main.async {
                self.clearResumeNotifications()
                self.shouldAutoStart = true
                rlog.notice("resume notification action=\(response.actionIdentifier, privacy: .public) -> auto-start requested")
            }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Present even in the foreground so the nudge is never silently swallowed
        // (and the test button is verifiable without racing to background the app).
        completionHandler([.banner, .list])
    }

    // MARK: - Helpers

    static func hm(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    /// Clock time without seconds — the taps are approximate, so the UI says so.
    static func hhmm(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private static func reasonName(_ r: WKExtendedRuntimeSessionInvalidationReason) -> String {
        switch r {
        case .none: return "none"
        case .sessionInProgress: return "sessionInProgress"
        case .expired: return "expired"
        case .resignedFrontmost: return "resignedFrontmost"
        case .suppressedBySystem: return "suppressedBySystem"
        case .error: return "error"
        @unknown default: return "unknown"
        }
    }

    private static func configSummary(_ c: ScheduleConfig) -> String {
        "taps=\(c.tapsPerHour) gap=\(Int(c.minGap))s debug=\(c.debugFastHour)"
    }

    /// Snapshot of the conditions most likely to cause a suppressedBySystem end.
    private static func context() -> String {
        let dev = WKInterfaceDevice.current()
        let pct = dev.batteryLevel < 0 ? "unknown" : "\(Int(dev.batteryLevel * 100))%"
        let batState: String
        switch dev.batteryState {
        case .unknown: batState = "unknown"
        case .unplugged: batState = "unplugged"
        case .charging: batState = "charging"
        case .full: batState = "full"
        @unknown default: batState = "?"
        }
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        return "battery=\(pct) state=\(batState) lowPower=\(lowPower)"
    }
}
