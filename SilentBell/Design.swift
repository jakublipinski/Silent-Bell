import SwiftUI

/// Visual language for Silent Bell.
///
/// Nothing here animates. State is carried by three redundant *static* signals:
///   1. Where the colour sits — accent at the top means running; when paused the
///      only accent is the Resume button at the bottom.
///   2. Fill — Active is a filled accent dot with two full ripples; Paused is a
///      grey dot whose ripples have settled to one faint ring.
///   3. Density — Active shows two lines of times; Paused is nearly empty, so the
///      silhouettes differ even when blurred by motion.
enum Design {
    /// Sand — a low-saturation amber. Warm like the tap itself; reads as lamplight
    /// rather than alert-orange, and holds up on OLED black at low brightness.
    /// Alternatives from the design: Moonlight 0x97A8C2, Bone 0xBFB8A8.
    static let accent = Color(hex: 0xCFA86F)
    static let accentTint = accent.opacity(0.16)

    static let rowBg = Color(hex: 0x1C1C1E)
    static let rowValue = Color(hex: 0x98989D)
    static let chevron = Color(hex: 0x48484A)

    static let stoppedMark = Color(hex: 0x8E8E93)
    static let stoppedWord = Color(hex: 0xA1A1A6)
    static let pausedMark = Color(hex: 0x98989D)
    static let pausedWord = Color(hex: 0xA8A8AD)
    static let pausedNote = Color(hex: 0x6B6B70)

    static let activeDetail = Color(hex: 0xE5E5EA)
    static let activeSub = Color(hex: 0x8E8E93)
    static let stopFg = Color(hex: 0xEBEBF0)
    static let footer = Color(hex: 0x5B5852)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// The mark: a dot and its ripples — a sound wave rendered as something felt.
/// It never animates; the state is told by fill and how far the ripple reaches.
struct RippleMark: View {
    enum Mode { case stopped, active, paused }
    let mode: Mode

    var body: some View {
        ZStack {
            switch mode {
            case .stopped:
                ring(28, Design.stoppedMark.opacity(0.16), 1.25)
                ring(17, Design.stoppedMark.opacity(0.40), 1.25)
                dot(6, Design.stoppedMark)
            case .active:
                ring(31.5, Design.accent.opacity(0.25), 1.7)
                ring(19, Design.accent.opacity(0.55), 1.7)
                dot(7.5, Design.accent)
            case .paused:
                // Ripples have settled: one faint ring, nothing further out.
                ring(17, Design.pausedMark.opacity(0.22), 1.25)
                dot(6, Design.pausedMark)
            }
        }
        .frame(width: 36, height: 36)
    }

    private func ring(_ d: CGFloat, _ c: Color, _ w: CGFloat) -> some View {
        Circle().stroke(c, lineWidth: w).frame(width: d, height: d)
    }

    private func dot(_ d: CGFloat, _ c: Color) -> some View {
        Circle().fill(c).frame(width: d, height: d)
    }
}

/// Full-width pill: the single primary action on each screen.
struct PillButton: View {
    let title: LocalizedStringKey
    let background: Color
    let foreground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 47)
                .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// One rounded settings row: label left, value / chevron / checkmark right.
struct SettingRow: View {
    let label: LocalizedStringKey
    var value: String? = nil
    var showChevron = false
    var checked = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 14.5))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)    // shrink rather than truncate on 41mm
            Spacer(minLength: 4)
            if let value {
                Text(value)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Design.rowValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Design.accent)
            }
            if showChevron {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Design.chevron)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(Design.rowBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A list of values rendered in the same row language as the rest of the app.
struct OptionPicker: View {
    let title: LocalizedStringKey
    let options: [Int]
    let format: (Int) -> String
    @Binding var selection: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 5) {
                ForEach(options, id: \.self) { option in
                    Button { selection = option } label: {
                        // `format` already returns display-ready text ("5 min",
                        // localized at the call site), so this is a key with no
                        // catalog entry — LocalizedStringKey then renders it verbatim,
                        // which is exactly what we want.
                        SettingRow(label: LocalizedStringKey(format(option)),
                                   checked: option == selection)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle(title)
    }
}
