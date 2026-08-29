import SwiftUI

struct MenuOverlay: View {
    @ObservedObject var game: GameController

    var body: some View {
        Scrim {
            VStack(spacing: 0) {
                Text("THE ZERO")
                    .font(.system(size: 34, weight: .black)).kerning(4)
                    .foregroundColor(.white)
                Text("FOAM CHALLENGE")
                    .font(.system(size: 30, weight: .black)).kerning(2)
                    .foregroundColor(Palette.accent)
                Text("""
                     Pour down the tilted wall for a laminar, foam-free flow. \
                     Fill to \(Int(GameController.targetLiquid * 100))% before the \
                     timer runs out — and never let the glass overflow.
                     """)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.top, 18)
                ModeSwitch(game: game).padding(.top, 24)
                PillButton(label: "POUR") { game.startRound() }.padding(.top, 24)
            }
        }
    }
}

struct ModeSwitch: View {
    @ObservedObject var game: GameController

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                option(.touch, "TOUCH", enabled: true)
                option(.tilt, "TILT + TOUCH", enabled: game.sensorAvailable)
            }
            if !game.sensorAvailable {
                Text("No motion sensor detected — touch controls only")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    private func option(_ mode: ControlMode, _ label: String, enabled: Bool) -> some View {
        let active = game.controlMode == mode
        return Text(label)
            .font(.system(size: 12, weight: .heavy)).kerning(1.2)
            .foregroundColor(active ? Palette.accent : .white.opacity(0.7))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(active ? Palette.accent.opacity(0.2) : Color.white.opacity(0.05))
                    .overlay(Capsule().stroke(active ? Palette.accent : Color.white.opacity(0.24),
                                              lineWidth: 1))
            )
            .opacity(enabled ? 1 : 0.35)
            .onTapGesture { if enabled { game.setControlMode(mode) } }
    }
}

struct ResultOverlay: View {
    @ObservedObject var game: GameController
    let success: Bool

    var body: some View {
        Scrim {
            VStack(spacing: 0) {
                Text(success ? "NICE POUR!" : "ROUND OVER")
                    .font(.system(size: 34, weight: .black)).kerning(3)
                    .foregroundColor(success ? Palette.accent : Palette.danger)
                if let r = game.lastResult {
                    Text(r.reason)
                        .font(.system(size: 14, weight: .bold)).kerning(2)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 6)
                    Text("\(r.score)")
                        .font(.system(size: 56, weight: .black))
                        .foregroundColor(.white)
                        .padding(.top, 20)
                    VStack(spacing: 6) {
                        row("Liquid", String(format: "%.1f%%", r.liquid * 100))
                        row("Foam", String(format: "%.1f%%", r.foam * 100))
                        row("Time", String(format: "%.1fs", r.timeUsed))
                        row("Multiplier", String(format: "×%.2f", r.multiplier))
                        row("Best", "\(game.bestScore)")
                    }
                    .padding(.top, 12)
                }
                HStack(spacing: 12) {
                    PillButton(label: "MENU", primary: false) { game.toMenu() }
                    PillButton(label: "RETRY") { game.startRound() }
                }
                .padding(.top, 26)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundColor(.white.opacity(0.55))
            Spacer()
            Text(value).font(.system(size: 14, weight: .heavy)).foregroundColor(.white)
        }
        .frame(width: 220)
    }
}

struct Scrim<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.04, blue: 0.08).opacity(0.8).ignoresSafeArea()
            ScrollView {
                content.padding(.horizontal, 28).padding(.vertical, 40)
            }
        }
    }
}
