import SwiftUI

/// Root screen: canvas, HUD, overlays, and the gesture layer that translates
/// touches into the normalised inputs the controller expects.
struct GameView: View {
    @StateObject private var game = GameController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let safeTop = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom

            ZStack {
                GameCanvas(game: game)
                gestureLayer(size: size)

                if game.phase == .playing {
                    VStack {
                        HUDView(game: game)
                        Spacer()
                        ControlHint(mode: game.controlMode).padding(.bottom, 10)
                    }
                }
                switch game.phase {
                case .menu:
                    MenuOverlay(game: game).transition(.opacity)
                case .success:
                    ResultOverlay(game: game, success: true).transition(.opacity)
                case .gameOver:
                    ResultOverlay(game: game, success: false).transition(.opacity)
                case .playing:
                    EmptyView()
                }
            }
            .onAppear {
                game.layout(size: size, safeTop: safeTop, safeBottom: safeBottom)
                game.boot()
            }
            .onChange(of: size) { _ in
                game.layout(size: size, safeTop: safeTop, safeBottom: safeBottom)
            }
        }
        .background(Palette.bg2)
        .ignoresSafeArea(.container, edges: .bottom)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onChange(of: scenePhase) { phase in
            // Never keep pouring audio alive in the background.
            if phase != .active { game.audio.stopAll() }
        }
    }

    // MARK: Gestures

    @ViewBuilder
    private func gestureLayer(size: CGSize) -> some View {
        if game.controlMode == .tilt {
            // One finger anywhere drives the bottle; the phone drives the glass.
            Color.clear
                .contentShape(Rectangle())
                .gesture(bottleDrag(size: size, xOffset: 0))
        } else {
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(glassDrag(size: size))
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(bottleDrag(size: size, xOffset: size.width * 0.5))
            }
        }
    }

    private func glassDrag(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dx = value.translation.width - lastGlassTranslation
                lastGlassTranslation = value.translation.width
                game.glassTiltInput = min(max(game.glassTiltInput + dx / (size.width * 0.4), -1), 1)
            }
            .onEnded { _ in lastGlassTranslation = 0 }
    }

    private func bottleDrag(size: CGSize, xOffset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dy = value.translation.height - lastBottleTranslation
                lastBottleTranslation = value.translation.height
                game.bottleXInput = min(max((value.location.x + xOffset) / size.width, 0), 1)
                // Dragging up tilts the bottle over; dragging down rights it.
                game.bottleTiltInput = min(max(game.bottleTiltInput - dy / (size.height * 0.45), 0), 1)
            }
            .onEnded { _ in lastBottleTranslation = 0 }
    }

    // Drag gestures report cumulative translation, so the per-event delta has
    // to be tracked by hand.
    @State private var lastGlassTranslation: CGFloat = 0
    @State private var lastBottleTranslation: CGFloat = 0
}
