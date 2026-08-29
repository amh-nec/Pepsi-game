# The Zero Foam Challenge — SwiftUI

A native SwiftUI/iOS port of the game. Same simulation, no Flutter: the
rendering is a single SwiftUI `Canvas`, the loop is a `CADisplayLink`, motion
comes from CoreMotion and the sound effects are synthesized into
`AVAudioPCMBuffer`s at launch.

## Building

The sources are project-file free. Either drop `Sources/` into a new Xcode
iOS App target (deployment target **iOS 16**, portrait only), or generate the
project with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
cd ZeroFoamChallenge
xcodegen generate
open ZeroFoamChallenge.xcodeproj
```

Portrait lock, hidden status bar and the accelerometer capability are declared
in `Resources/Info.plist`. No usage-description key is needed: the
accelerometer is not a privacy-gated sensor.

## Structure

Physics and rendering stay fully separated — the engine imports only
CoreGraphics/Foundation and has no SwiftUI dependency at all, and the canvas
never mutates state.

| Path | Role |
| --- | --- |
| `Sources/Engine/Geometry.swift` | Convex-polygon maths, tilted-glass geometry, liquid-level solver |
| `Sources/Engine/PourPhysics.swift` | Flow rate, ballistic stream tracing, impact-angle foam model, foam decay |
| `Sources/Engine/Effects.swift` | Cosmetic particles (fizz bubbles, splash droplets) |
| `Sources/Engine/GameController.swift` | `CADisplayLink` loop, phases, timer, scoring, feedback orchestration |
| `Sources/Engine/GameAudio.swift` | `AVAudioEngine` software synth: pour noise, fizz crackle, win/lose stings |
| `Sources/Engine/Haptics.swift` | Rate-limited pour ticks, warning thuds, overflow error buzz |
| `Sources/Engine/MotionInput.swift` | CoreMotion accelerometer with silent fallback |
| `Sources/Views/GameCanvas.swift` | The whole playfield in one SwiftUI `Canvas` |
| `Sources/Views/` | HUD, overlays, gesture layer, palette |
| `Tests/` | XCTest cover of the geometry and pour physics |

## Flutter → SwiftUI mapping

| Flutter | SwiftUI |
| --- | --- |
| `Ticker` / `AnimationController` | `CADisplayLink` (60 FPS preferred frame-rate range) |
| `CustomPainter` + `Canvas` | `Canvas` + `GraphicsContext` |
| `ChangeNotifier` + `AnimatedBuilder` | `ObservableObject` + `@Published` frame counter |
| `Path.combine(difference)` | `Path.subtracting(_:)` |
| `sensors_plus` | `CMMotionManager` |
| `audioplayers` + in-memory WAV | `AVAudioEngine` + `AVAudioPCMBuffer` |
| `HapticFeedback` | `UIFeedbackGenerator` |
| `GestureDetector` halves | `DragGesture` on two `Color.clear` halves |

The simulation model (flow curve, impact-angle foam, foam decay, tilt-reduced
capacity, scoring) is unchanged — see the root `README.md` for the details.
