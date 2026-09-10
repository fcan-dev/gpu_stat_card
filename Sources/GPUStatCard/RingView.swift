import SwiftUI

/// A circular progress ring. `fraction` is 0…1 (clamped); `active=false` dims
/// the ring (used when the server is unreachable).
struct RingView: View {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat
    var active: Bool = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(active ? 0.15 : 0.06), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(fraction, 1)))
                .stroke(color.opacity(active ? 1 : 0.35),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

extension Color {
    /// Slightly darker takes on the system heat colors, easier to read on
    /// the vibrant card background.
    static let statGreen = Color(.sRGB, red: 0x1E / 255, green: 0x9C / 255, blue: 0x44 / 255)
    static let statAmber = Color(.sRGB, red: 0xC8 / 255, green: 0x7A / 255, blue: 0x00 / 255)
    static let statRed = Color(.sRGB, red: 0xC1 / 255, green: 0x36 / 255, blue: 0x2E / 255)

    /// Temperature heat color: green < 60, amber 60–74, red ≥ 75.
    static func heat(_ tempC: Int) -> Color {
        switch tempC {
        case ..<60: return .statGreen
        case 60..<75: return .statAmber
        default: return .statRed
        }
    }

    /// Power draw color, relative to the power limit: green below 75%,
    /// amber 75–90%, red at or above 90%.
    static func power(_ fraction: Double?) -> Color {
        guard let fraction else { return .primary }
        switch fraction {
        case ..<0.75: return .statGreen
        case 0.75..<0.9: return .statAmber
        default: return .statRed
        }
    }
}
