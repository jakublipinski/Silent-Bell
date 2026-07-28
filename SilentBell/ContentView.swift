import SwiftUI
import WatchKit

struct ContentView: View {
    @StateObject private var session = ReminderSession()

    @AppStorage("tapsPerHour") private var tapsPerHour = 4
    @AppStorage("minGapMinutes") private var minGapMinutes = 10
    @AppStorage("debugFastHour") private var debugFastHour = false
    @AppStorage(Haptics.reminderKey) private var reminderHapticRaw = WKHapticType.start.rawValue
    @AppStorage("hasSeenIntro") private var hasSeenIntro = false

    @Environment(\.scenePhase) private var scenePhase

    private var config: ScheduleConfig {
        ScheduleConfig(
            tapsPerHour: tapsPerHour,
            minGap: TimeInterval(minGapMinutes * 60),
            debugFastHour: debugFastHour
        )
    }

    var body: some View {
        if hasSeenIntro {
            main
        } else {
            IntroView {
                hasSeenIntro = true
                session.requestNotificationPermission()
            }
        }
    }

    private var main: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    primaryAction
                    if session.phase != .active { settings }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        // Auto-start when the app is (re)opened via the resume notification. Starting
        // a session is only legal while active, so we trigger it on the active phase.
        .onAppear { session.autoStartIfRequested(config: config) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.autoStartIfRequested(config: config) }
        }
        .onChange(of: session.shouldAutoStart) { _, want in
            if want && scenePhase == .active { session.autoStartIfRequested(config: config) }
        }
    }

    // MARK: - Header: the mark, the state word, and (when active) the times

    @ViewBuilder private var header: some View {
        VStack(spacing: 0) {
            RippleMark(mode: markMode)
                .padding(.top, 6)

            Text(stateWord)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(stateColor)
                .padding(.top, 4)

            switch session.phase {
            case .active:
                // Density is part of the glance signal: Active carries two lines.
                if let next = session.nextFire {
                    Text("Next tap around \(ReminderSession.hhmm(next))")
                        .font(.system(size: 15))
                        .foregroundStyle(Design.activeDetail)
                        .padding(.top, 11)
                }
                if let end = session.expiry {
                    Text("Session ends at \(ReminderSession.hhmm(end))")
                        .font(.system(size: 13))
                        .foregroundStyle(Design.activeSub)
                        .padding(.top, 4)
                }
            case .paused:
                Text("Sessions rest after an hour.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Design.pausedNote)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            default:
                EmptyView()
            }
        }
    }

    private var markMode: RippleMark.Mode {
        switch session.phase {
        case .active: return .active
        case .paused: return .paused
        default: return .stopped
        }
    }

    private var stateWord: String {
        switch session.phase {
        case .stopped: return "Stopped"
        case .starting: return "Starting"
        case .active: return "Active"
        case .paused: return "Paused"
        }
    }

    private var stateColor: Color {
        switch session.phase {
        case .active: return Design.accent       // top-lit = running
        case .paused: return Design.pausedWord
        default: return Design.stoppedWord
        }
    }

    // MARK: - The single primary action

    @ViewBuilder private var primaryAction: some View {
        Group {
            if session.phase == .active {
                PillButton(title: "Stop",
                           background: Design.rowBg,
                           foreground: Design.stopFg) { session.stop() }
            } else if session.phase == .paused {
                // The only accent on this screen sits down here.
                PillButton(title: "Resume",
                           background: Design.accentTint,
                           foreground: Design.accent) { session.start(config: config) }
            } else {
                PillButton(title: "Start",
                           background: Design.accent,
                           foreground: .black) { session.start(config: config) }
            }
        }
        .padding(.top, 13)
    }

    // MARK: - Settings (only when a session isn't running)

    @ViewBuilder private var settings: some View {
        VStack(spacing: 5) {
            NavigationLink {
                OptionPicker(title: "Taps per hour",
                             options: Array(1...10),
                             format: { "\($0)" },
                             selection: $tapsPerHour)
            } label: {
                SettingRow(label: "Taps per hour", value: "\(tapsPerHour)")
            }
            .buttonStyle(.plain)

            NavigationLink {
                OptionPicker(title: "Min. gap",
                             options: Array(1...15),
                             format: { "\($0) min" },
                             selection: $minGapMinutes)
            } label: {
                SettingRow(label: "Min. gap", value: "\(minGapMinutes) min")
            }
            .buttonStyle(.plain)

            NavigationLink {
                ReminderTapView(selectedRaw: $reminderHapticRaw)
            } label: {
                SettingRow(label: "Tap",
                           value: hapticName(reminderHapticRaw),
                           showChevron: true)
            }
            .buttonStyle(.plain)

            NavigationLink {
                AboutView()
            } label: {
                SettingRow(label: "About", showChevron: true)
            }
            .buttonStyle(.plain)

            // Debug builds only. An App Store archive is Release, so a reviewer
            // never sees the event log or the test buttons — which would read as an
            // unfinished app — while `./run.sh` (Debug) keeps them for diagnostics.
            #if DEBUG
            NavigationLink {
                DeveloperView(session: session, logStore: session.logStore, debugFastHour: $debugFastHour)
            } label: {
                SettingRow(label: "Log", showChevron: true)
            }
            .buttonStyle(.plain)
            #endif
        }
        .padding(.top, 11)
    }
}

/// Bumped each deploy so we can confirm the Watch is running a fresh build.
let buildTag = "nodelay-1"

/// The reminder haptics, named for how they feel rather than for the API constant.
let hapticChoices: [(String, WKHapticType)] = [
    ("Gentle", .start),
    ("Tick", .click),
    ("Knock", .notification),
    ("Double", .success),
    ("Rise", .directionUp),
    ("Fall", .directionDown),
    ("Firm", .stop),
    ("Heavy", .failure),
    ("Echo", .retry),
]

func hapticName(_ raw: Int) -> String {
    hapticChoices.first { $0.1.rawValue == raw }?.0 ?? "—"
}

/// Pick the reminder tap. Tapping a row **plays it immediately** and selects it;
/// the selection is what actually fires on every reminder.
struct ReminderTapView: View {
    @Binding var selectedRaw: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 5) {
                ForEach(hapticChoices, id: \.0) { name, type in
                    Button {
                        selectedRaw = type.rawValue
                        WKInterfaceDevice.current().play(type)
                    } label: {
                        SettingRow(label: name, checked: type.rawValue == selectedRaw)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("Tap Type")
    }
}

/// Developer-only: the session log plus the test affordances. Kept off the main
/// screen so the app the user actually sees stays at three controls.
struct DeveloperView: View {
    @ObservedObject var session: ReminderSession
    @ObservedObject var logStore: LogStore
    @Binding var debugFastHour: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 5) {
                // Share the whole log + device context. watchOS has no mailto: /
                // openURL, so ShareLink's share sheet (Mail, Messages…) is the way
                // a diagnostic report gets off the wrist.
                ShareLink(item: logStore.exportText()) {
                    SettingRow(label: "Share log", showChevron: true)
                }
                .buttonStyle(.plain)

                Button { debugFastHour.toggle() } label: {
                    SettingRow(label: "60-sec hour",
                               value: debugFastHour ? "On" : "Off",
                               checked: debugFastHour)
                }
                .buttonStyle(.plain)

                Button { session.fireTestResume() } label: {
                    SettingRow(label: "Test resume (alerting)")
                }
                .buttonStyle(.plain)

                Button { session.fireTestResumePassive() } label: {
                    SettingRow(label: "Test resume (silent)")
                }
                .buttonStyle(.plain)

                Button(role: .destructive) { logStore.clear() } label: {
                    SettingRow(label: "Clear log")
                }
                .buttonStyle(.plain)

                Text(LogStore.deviceContext())
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Design.footer)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 6)

                ForEach(logStore.entries) { entry in
                    HStack(spacing: 5) {
                        Text(ReminderSession.hm(entry.time))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Design.rowValue)
                        Text(entry.kind)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white)
                        if !entry.detail.isEmpty {
                            Text(entry.detail)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Design.rowValue)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("Log")
    }
}
