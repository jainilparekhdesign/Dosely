import SwiftUI

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt64(s, radix: 16) ?? 0xFFFFFF
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static let doseTaken = Color(hex: "#2FA36B")
    static let doseMissed = Color(hex: "#E0533D")
    static let doseSkipped = Color(hex: "#8E8E93")
    static let doseDue = Color(hex: "#E8930C")
}

/// A recognisable drawing of the medicine: tablet shapes, two-tone capsules, or a symbol for other forms.
struct PillIconView: View {
    var type: MedType
    var shape: PillShape = .round
    var colorHex: String
    var secondaryHex: String = "#3D7BF0"
    var size: CGFloat = 44

    private var main: Color { Color(hex: colorHex) }
    private var second: Color { Color(hex: secondaryHex) }
    private var outline: Color { Color.black.opacity(0.18) }

    var body: some View {
        ZStack {
            switch type {
            case .tablet: tablet
            case .capsule: capsule
            default: symbol
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var tablet: some View {
        switch shape {
        case .round:
            Circle().fill(main.gradient)
                .overlay(Circle().strokeBorder(outline, lineWidth: 1))
                .overlay(Rectangle().fill(outline).frame(width: size * 0.5, height: 1.2))
                .frame(width: size * 0.82, height: size * 0.82)
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        case .oval:
            Ellipse().fill(main.gradient)
                .overlay(Ellipse().strokeBorder(outline, lineWidth: 1))
                .frame(width: size * 0.9, height: size * 0.6)
                .rotationEffect(.degrees(-30))
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        case .oblong:
            Capsule().fill(main.gradient)
                .overlay(Capsule().strokeBorder(outline, lineWidth: 1))
                .overlay(Rectangle().fill(outline).frame(width: 1.2, height: size * 0.3))
                .frame(width: size * 0.95, height: size * 0.42)
                .rotationEffect(.degrees(-30))
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        case .diamond:
            RoundedRectangle(cornerRadius: size * 0.12).fill(main.gradient)
                .overlay(RoundedRectangle(cornerRadius: size * 0.12).strokeBorder(outline, lineWidth: 1))
                .frame(width: size * 0.6, height: size * 0.6)
                .rotationEffect(.degrees(45))
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        }
    }

    private var capsule: some View {
        HStack(spacing: 0) {
            UnevenRoundedRectangle(topLeadingRadius: size * 0.2, bottomLeadingRadius: size * 0.2).fill(main.gradient)
            UnevenRoundedRectangle(bottomTrailingRadius: size * 0.2, topTrailingRadius: size * 0.2).fill(second.gradient)
        }
        .overlay(Capsule().strokeBorder(outline, lineWidth: 1))
        .clipShape(Capsule())
        .frame(width: size * 0.95, height: size * 0.4)
        .rotationEffect(.degrees(-35))
        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
    }

    private var symbol: some View {
        Circle()
            .fill(main.opacity(colorHex.uppercased() == "#FFFFFF" ? 0 : 0.18))
            .overlay(Circle().strokeBorder(main.opacity(0.35), lineWidth: 1))
            .overlay(
                Image(systemName: type.symbol)
                    .resizable().scaledToFit()
                    .foregroundStyle(colorHex.uppercased() == "#FFFFFF" ? Color.accentColor : main)
                    .padding(size * 0.24)
            )
    }
}

extension PillIconView {
    init(_ med: Medication, size: CGFloat = 44) {
        self.init(type: med.type, shape: med.shape, colorHex: med.colorHex, secondaryHex: med.secondaryColorHex, size: size)
    }

    init(_ draft: DraftMedication, size: CGFloat = 44) {
        self.init(type: draft.type, shape: draft.shape, colorHex: draft.colorHex, secondaryHex: draft.secondaryColorHex, size: size)
    }
}

/// Medicine icon on a tile; shows the user's photo instead when one exists.
struct MedicationThumb: View {
    let med: Medication
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let data = med.photoData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                PillIconView(med, size: size * 0.8)
                    .frame(width: size, height: size)
                    .background(Color(.tertiarySystemFill))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 8
    var color: Color = .doseTaken

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.5), value: progress)
        }
    }
}

struct StatusChip: View {
    let status: DisplayStatus

    var color: Color {
        switch status {
        case .taken: .doseTaken
        case .missed: .doseMissed
        case .skipped: .doseSkipped
        case .due: .doseDue
        case .upcoming: .secondary
        }
    }

    var icon: String {
        switch status {
        case .taken: "checkmark.circle.fill"
        case .missed: "exclamationmark.circle.fill"
        case .skipped: "forward.fill"
        case .due: "bell.fill"
        case .upcoming: "clock"
        }
    }

    var body: some View {
        Label(status.label, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// Coloured banner used for refill warnings, permissions and disclaimers.
struct InfoBanner: View {
    let icon: String
    let title: String
    var message: String?
    var tint: Color = .accentColor
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                if let actionTitle, let action {
                    Button(actionTitle, action: action).font(.footnote.weight(.semibold)).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
