import SwiftUI

/// The explanation of how Silent Bell behaves, written once and shown twice: as a
/// one-time intro on first launch, and permanently under Settings → About.
///
/// The third paragraph is the important one. A stranger who feels taps for an hour
/// and then finds the app "Paused" concludes it is broken — that is the single most
/// predictable one-star review this app can attract. The pause is a platform limit
/// we cannot remove, so the only defence is saying so *before* it happens: framed up
/// front it reads as honesty, discovered cold it reads as a defect.
struct AboutBody: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RippleMark(mode: .active)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)

            Text("Silent Bell")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Design.accent)
                .frame(maxWidth: .infinity, alignment: .center)

            // Each of these is a single literal, not a concatenation:
            // LocalizedStringKey is a lookup key, and "a" + "b" would build a
            // key that exists in no catalog.
            para("Random taps on your wrist — a prompt to notice where your attention is. Predictable reminders are ignored over time; unpredictable ones aren't.")

            para("No sound, nothing on screen. Only you feel it, even in Do Not Disturb.")

            heading("Sessions last one hour")
            para("Apple caps background running, so Silent Bell pauses when the hour is up. You'll feel a descending pattern. Tap Resume to carry on.")
        }
        .padding(.horizontal, 4)
    }

    private func para(_ s: LocalizedStringKey) -> some View {
        Text(s)
            .font(.system(size: 13))
            .foregroundStyle(Design.activeDetail)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func heading(_ s: LocalizedStringKey) -> some View {
        Text(s)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.top, 4)
    }
}

/// Shown once, on first launch.
struct IntroView: View {
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                AboutBody()
                PillButton(title: "Get started",
                           background: Design.accent,
                           foreground: .black,
                           action: onDone)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
    }
}

/// The same text, reachable forever from Settings → About.
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                AboutBody()
                footer
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .navigationTitle("About")
    }

    /// Version and home page. Deliberately here and not in `AboutBody`, so the
    /// first-run intro stays a welcome rather than a colophon.
    ///
    /// The address is plain text, not a `Link`: watchOS has no browser to hand it
    /// to, so a tappable link would promise something it cannot do.
    private var footer: some View {
        VStack(spacing: 2) {
            Text(Self.version)
            Text("silentbell.app")
        }
        .font(.system(size: 12))
        .foregroundStyle(Design.footer)
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return String(localized: "Version \(short) (\(build))")
    }
}
