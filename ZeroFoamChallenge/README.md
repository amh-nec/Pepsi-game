# The Zero Foam Challenge — SwiftUI

A native SwiftUI/iOS port of the game. Same simulation, no Flutter: the
rendering is a single SwiftUI `Canvas`, the loop is a `CADisplayLink`, motion
comes from CoreMotion and the sound effects are synthesized into
`AVAudioPCMBuffer`s at launch.

## Building

A ready-to-open Xcode project is checked in — no tooling to install:

```bash
cd ZeroFoamChallenge
open ZeroFoamChallenge.xcodeproj
```

Deployment target is iOS 16, iPhone only. Portrait lock and the hidden status
bar are set as `INFOPLIST_KEY_*` build settings, so the target generates its
own Info.plist; no usage-description key is needed, as the accelerometer is
not a privacy-gated sensor. Set your own team under Signing & Capabilities to
run on a device — the Simulator needs no signing, but it reports no
accelerometer, so tilt control only appears on hardware.

`project.yml` and `Resources/Info.plist` remain for anyone who would rather
regenerate the project with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`xcodegen generate`); the checked-in project does not read them. The XCTest
target exists only on that path — the checked-in project builds the app alone.

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
| `Tests/` | XCTest cover of the geometry and pour physics (XcodeGen path only) |

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
