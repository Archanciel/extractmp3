import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'views/audio_extractor_view.dart';
import 'viewmodels/audio_extractor_viewmodel.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MP3 Extractor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: ChangeNotifierProvider(
        create: (context) => AudioExtractorViewModel(),
        child: const AudioExtractorView(),
      ),
    );
  }
}
