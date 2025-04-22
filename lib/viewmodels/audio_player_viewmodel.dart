import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class AudioPlayerViewModel extends ChangeNotifier {
  // The audio player instance
  final AudioPlayer _player = AudioPlayer();
  
  // Current playback state
  bool _isPlaying = false;
  bool _isLoaded = false;
  String? _currentFilePath;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  
  // Getters
  bool get isPlaying => _isPlaying;
  bool get isLoaded => _isLoaded;
  String? get currentFilePath => _currentFilePath;
  Duration get duration => _duration;
  Duration get position => _position;
  double get progressPercent => _duration.inMilliseconds > 0 
      ? _position.inMilliseconds / _duration.inMilliseconds 
      : 0.0;
  
  AudioPlayerViewModel() {
    // Listen to player state changes
    _player.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      notifyListeners();
    });
    
    // Listen to duration changes
    _player.durationStream.listen((newDuration) {
      if (newDuration != null) {
        _duration = newDuration;
        notifyListeners();
      }
    });
    
    // Listen to position changes
    _player.positionStream.listen((newPosition) {
      _position = newPosition;
      notifyListeners();
    });
  }
  
  // Load a file for playback
  Future<void> loadFile(String filePath) async {
    try {
      if (!File(filePath).existsSync()) {
        debugPrint('File does not exist: $filePath');
        return;
      }
      
      await _player.stop();
      
      // Properly dispose and recreate player if there were issues
      try {
        await _player.setFilePath(filePath);
      } catch (e) {
        debugPrint('Error setting file path: $e');
        // Try with a slight delay (sometimes helps with initialization issues)
        await Future.delayed(const Duration(milliseconds: 500));
        await _player.setFilePath(filePath);
      }
      
      _isLoaded = true;
      _currentFilePath = filePath;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading audio file: $e');
      _isLoaded = false;
      notifyListeners();
    }
  }
  
  // Play or pause the current track
  Future<void> togglePlay() async {
    if (!_isLoaded) return;
    
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        await _player.play();
      }
    } catch (e) {
      debugPrint('Error toggling playback: $e');
    }
  }
  
  // Seek to a specific position
  Future<void> seekTo(Duration position) async {
    if (!_isLoaded) return;
    
    try {
      await _player.seek(position);
    } catch (e) {
      debugPrint('Error seeking: $e');
    }
  }
  
  // Seek by percentage (0.0 to 1.0)
  Future<void> seekByPercentage(double percentage) async {
    if (!_isLoaded || _duration == Duration.zero) return;
    
    final newPosition = Duration(
      milliseconds: (percentage * _duration.inMilliseconds).round(),
    );
    await seekTo(newPosition);
  }
  
  // Clean up resources
  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}