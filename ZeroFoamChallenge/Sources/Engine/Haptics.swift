import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Haptic feedback with built-in rate limiting, so the continuous pour ticks
/// never flood the Taptic Engine.
final class Haptics {
    var enabled = true

    #if canImport(UIKit)
    private let selection = UISelectionFeedbackGenerator()
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()
    #endif

    private var lastTick = Date.distantPast
    private var lastWarn = Date.distantPast

    func prepare() {
        #if canImport(UIKit)
        selection.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        #endif
    }

    /// Light ticks while liquid is flowing. `intensity` 0...1 shortens the gap
    /// between ticks so a heavy pour feels heavier.
    func pourTick(intensity: CGFloat) {
        guard enabled else { return }
        let gap = 0.150 - 0.080 * Double(min(max(intensity, 0), 1))
        guard Date().timeIntervalSince(lastTick) >= gap else { return }
        lastTick = Date()
        #if canImport(UIKit)
        selection.selectionChanged()
        selection.prepare()
        #endif
    }

    /// Repeating warning thud as the glass approaches the rim.
    func warning() {
        guard enabled, Date().timeIntervalSince(lastWarn) >= 0.32 else { return }
        lastWarn = Date()
        #if canImport(UIKit)
        impactMedium.impactOccurred(intensity: 0.9)
        impactMedium.prepare()
        #endif
    }

    func success() {
        guard enabled else { return }
        #if canImport(UIKit)
        notification.notificationOccurred(.success)
        #endif
    }

    /// Strong error buzz on overflow.
    func error() {
        guard enabled else { return }
        #if canImport(UIKit)
        notification.notificationOccurred(.error)
        for (i, delay) in [0.09, 0.18].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.enabled else { return }
                self.impactHeavy.impactOccurred(intensity: i == 0 ? 1.0 : 0.8)
            }
        }
        #endif
    }
}
