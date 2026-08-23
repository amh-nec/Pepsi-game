import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/game_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only, edge-to-edge so the art reaches under the notch.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));
  runApp(const ZeroFoamApp());
}

class ZeroFoamApp extends StatelessWidget {
  const ZeroFoamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Zero Foam Challenge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Roboto',
      ),
      home: const GameScreen(),
    );
  }
}
