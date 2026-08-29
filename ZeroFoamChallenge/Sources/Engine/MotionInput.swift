import CoreMotion
import Foundation

/// Wraps CoreMotion so the rest of the game never has to know whether a
/// motion sensor exists. Falls back silently when it doesn't.
final class MotionInput {
    private let manager = CMMotionManager()
    private(set) var isAvailable = false

    /// Called on the main queue with a -1...1 left/right tilt.
    var onTilt: ((CGFloat) -> Void)?

    func start() {
        guard manager.isAccelerometerAvailable else {
            isAvailable = false
            return
        }
        manager.accelerometerUpdateInterval = 1.0 / 60.0
        manager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self else { return }
            guard let data, error == nil else {
                self.stop()
                self.isAvailable = false
                return
            }
            self.isAvailable = true
            // Portrait: x is the left/right component of gravity, in g.
            let raw = min(max(CGFloat(data.acceleration.x), -1), 1)
            // Dead zone keeps a hand-held phone steady.
            let value = abs(raw) < 0.06 ? 0 : raw
            self.onTilt?(min(max(value * 1.5, -1), 1))
        }
    }

    func stop() {
        if manager.isAccelerometerActive { manager.stopAccelerometerUpdates() }
    }
}
