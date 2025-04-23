import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_size/window_size.dart';
import 'views/audio_extractor_view.dart';
import 'viewmodels/audio_extractor_viewmodel.dart';
import 'viewmodels/audio_player_viewmodel.dart';

Future<void> main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Set up window size and position for desktop platforms
  await setWindowsAppSizeAndPosition();

  runApp(const MyApp());
}

/// If app runs on Windows, Linux or MacOS, set the app size
/// and position.
Future<void> setWindowsAppSizeAndPosition({bool isTest = true}) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await getScreenList().then((List<Screen> screens) {
      // Assumez que vous voulez utiliser le premier écran (principal)
      final Screen screen = screens.first;
      final Rect screenRect = screen.visibleFrame;

      // Définissez la largeur et la hauteur de votre fenêtre
      double windowWidth = (isTest) ? 900 : 730;
      const double windowHeight = 1500;

      // Calculez la position X pour placer la fenêtre sur le côté droit de l'écran
      final double posX = screenRect.right - windowWidth + 10;
      // Optionnellement, ajustez la position Y selon vos préférences
      final double posY = (screenRect.height - windowHeight) / 2;

      final Rect windowRect = Rect.fromLTWH(
        posX,
        posY,
        windowWidth,
        windowHeight,
      );
      setWindowFrame(windowRect);
    });
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MP3 Extractor',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (context) => AudioExtractorViewModel(),
          ),
          ChangeNotifierProvider(create: (context) => AudioPlayerViewModel()),
        ],
        child: const AudioExtractorView(),
      ),
    );
  }
}