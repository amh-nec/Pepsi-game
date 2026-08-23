import 'package:flutter/material.dart';

import '../engine/game_controller.dart';
import '../render/game_painter.dart';
import 'hud.dart';
import 'input_layer.dart';
import 'overlays.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final GameController game = GameController(vsync: this);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    game.boot();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Never keep pouring audio alive in the background.
    if (state != AppLifecycleState.resumed) game.audio.stopAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    game.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: Palette.bg2,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          game.layout(size, padding);
          return AnimatedBuilder(
            animation: game,
            builder: (context, _) {
              return InputLayer(
                game: game,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: GamePainter(game),
                        size: size,
                      ),
                    ),
                    if (game.phase == GamePhase.playing)
                      SafeArea(
                        child: Column(
                          children: [
                            Hud(game: game),
                            const Spacer(),
                            ControlHint(mode: game.controlMode),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    if (game.phase == GamePhase.menu)
                      Positioned.fill(child: MenuOverlay(game: game)),
                    if (game.phase == GamePhase.success ||
                        game.phase == GamePhase.gameOver)
                      Positioned.fill(
                        child: ResultOverlay(
                          game: game,
                          success: game.phase == GamePhase.success,
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
