# The Zero Foam Challenge

Two implementations of the same game and the same simulation model:
the Flutter app at the repository root, and a native SwiftUI/iOS port in
[`ZeroFoamChallenge/`](ZeroFoamChallenge/README.md).

A mobile-native, 2D physics-based hyper-casual pouring game built in Flutter.
Pour cola down the tilted wall of the glass to keep the flow laminar, fill to
90% before the timer runs out — and never let it overflow.

## Running (Flutter)

The repository contains the Dart sources only; generate the platform folders
once with:

```bash
flutter create . --platforms=android,ios
flutter pub get
flutter run          # portrait-only, iOS + Android
flutter test         # physics unit tests
```

## Structure

Physics and rendering are fully separated — the engine has no widget, canvas
or platform dependency, and the painter never mutates state.

| Path | Role |
| --- | --- |
| `lib/engine/geometry.dart` | Convex-polygon maths, tilted-glass geometry, liquid-level solver |
| `lib/engine/physics.dart` | `PourPhysics`: flow rate, ballistic stream tracing, impact-angle foam model, foam decay |
| `lib/engine/effects.dart` | Cosmetic particles (fizz bubbles, splash droplets) |
| `lib/engine/game_controller.dart` | Game loop (`Ticker`), phases, timer, scoring, feedback orchestration |
| `lib/engine/audio.dart` | Software synth: pour noise, fizz crackle, win/lose stings, generated as in-memory WAVs |
| `lib/engine/haptics.dart` | Rate-limited pour ticks, warning thuds, overflow error buzz |
| `lib/render/game_painter.dart` | Single `CustomPainter` for the whole playfield |
| `lib/ui/` | Input layer (touch / accelerometer), HUD, overlays, screen |

## Simulation model

* **Flow** — the bottle only pours past ~31° of tilt and ramps smoothly to full
  flow at ~83°; the stream leaves the mouth along the bottle axis and follows a
  ballistic arc under gravity.
* **Foam** — the stream is traced until it hits the glass wall, the liquid
  surface or the dry base. The angle between the stream and the surface it hits
  decides the foam share of that instant's pour:
  * grazing a tilted wall → laminar, ~5–15% foam
  * a vertical drop into the liquid → up to ~78%
  * hitting the dry base → worst case
  Impact speed and stream thickness scale the result.
* **Volume** — `liquid + foam` is tracked against the glass capacity. Foam
  collapses continuously; 45% of it drains back into the liquid body.
* **Overflow** — tilting the glass lowers its effective capacity (the geometry
  solver measures the volume below the lower lip), so an aggressive tilt can
  spill a glass that was safe upright.

## Controls

* **Touch** — drag on the left half to tilt the glass, on the right half to
  move the bottle (horizontal) and tilt it (vertical).
* **Tilt + touch** — the accelerometer tilts the glass, one finger drives the
  bottle. Offered only when a motion sensor is actually reporting; any sensor
  error falls back to touch controls automatically.

## Feedback

Light haptic ticks while pouring (rate scaled by flow), repeating medium thuds
at the 90% warning threshold with a red pulsing rim and screen shake, and a
double heavy-impact buzz on overflow.
