import SwiftUI

/// Timer, fill gauge and foam gauge.
struct HUDView: View {
    @ObservedObject var game: GameController

    var body: some View {
        let _ = game.frame
        let liquid = min(max(game.physics.liquid, 0), 1)
        let foam = min(max(game.physics.foam, 0), 1)
        let urgent = game.timeLeft <= 6

        VStack(spacing: 12) {
            HStack {
                StatChip(label: "TIME",
                         value: String(format: "%.1f", game.timeLeft),
                         color: urgent ? Palette.danger : Palette.accent)
                Spacer()
                StatChip(label: "TARGET",
                         value: "\(Int(GameController.targetLiquid * 100))%",
                         color: .white.opacity(0.7))
                Spacer()
                StatChip(label: "BEST", value: "\(game.bestScore)", color: .white.opacity(0.7))
            }
            FillGauge(liquid: liquid, foam: foam,
                      capacity: game.physics.capacity, warning: game.isWarning)
            HStack {
                Text("LIQUID \(Int(liquid * 100))%")
                    .font(.system(size: 12, weight: .heavy)).kerning(1.1)
                    .foregroundColor(Palette.colaLight)
                Spacer()
                Text("FOAM \(Int(foam * 100))%")
                    .font(.system(size: 12, weight: .heavy)).kerning(1.1)
                    .foregroundColor(game.isWarning ? Palette.danger : Palette.foamShade)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }
}

struct StatChip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 10, weight: .bold)).kerning(1.6)
                .foregroundColor(.white.opacity(0.38))
            Text(value)
                .font(.system(size: 20, weight: .black))
                .foregroundColor(color)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
    }
}

/// Stacked bar: cola first, foam on top, target and rim markers overlaid.
struct FillGauge: View {
    let liquid: CGFloat
    let foam: CGFloat
    let capacity: CGFloat
    let warning: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.35))
                HStack(spacing: 0) {
                    Rectangle().fill(Palette.colaLight)
                        .frame(width: w * min(max(liquid, 0), 1))
                    Rectangle().fill(Palette.foam)
                        .frame(width: w * min(max(foam, 0), 1 - min(max(liquid, 0), 1)))
                }
                .clipShape(RoundedRectangle(cornerRadius: 9))
                Rectangle().fill(Palette.accent).frame(width: 2)
                    .offset(x: w * GameController.targetLiquid - 1)
                Rectangle().fill(warning ? Palette.danger : Color.white.opacity(0.55))
                    .frame(width: 3)
                    .offset(x: min(max(w * capacity - 2, 0), w - 3))
            }
        }
        .frame(height: 18)
    }
}

/// A compact reminder of the active control scheme.
struct ControlHint: View {
    let mode: ControlMode

    var body: some View {
        Text(mode == .tilt
             ? "TILT PHONE = GLASS   •   DRAG = BOTTLE"
             : "LEFT DRAG = GLASS   •   RIGHT DRAG = BOTTLE")
            .font(.system(size: 11, weight: .bold)).kerning(1.2)
            .foregroundColor(.white.opacity(0.35))
            .multilineTextAlignment(.center)
    }
}

struct PillButton: View {
    let label: String
    var primary = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .black)).kerning(1.4)
                .foregroundColor(primary ? Palette.onAccent : .white)
                .padding(.horizontal, 34)
                .padding(.vertical, 14)
                .background(
                    Capsule().fill(primary ? Palette.accent : Color.white.opacity(0.08))
                        .overlay(Capsule().stroke(primary ? Palette.accent : Color.white.opacity(0.24),
                                                  lineWidth: 2))
                )
        }
        .buttonStyle(.plain)
    }
}
