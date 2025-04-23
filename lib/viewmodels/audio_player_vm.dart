import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

class AudioPlayerVM extends ChangeNotifier {
  // The audio player instance
  AudioPlayer? _player;
  
  // Current playback state
  bool _isPlaying = false;
  
  bool _isLoaded = false;
  set isLoaded(bool value) {
    _isLoaded = value;
    notifyListeners();
  }

  String? _currentFilePath;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  
  // Error tracking
  bool _hasError = false;
  String _errorMessage = '';
  
  // Stream subscriptions
  List<StreamSubscription?> _subscriptions = [];
  
  // Getters
  bool get isPlaying => _isPlaying;
  bool get isLoaded => _isLoaded;
  String? get currentFilePath => _currentFilePath;
  Duration get duration => _duration;
  Duration get position => _position;
  bool get hasError => _hasError;
  String get errorMessage => _errorMessage;
  
  double get progressPercent => _duration.inMilliseconds > 0 
      ? _position.inMilliseconds / _duration.inMilliseconds 
      : 0.0;
  
  AudioPlayerVM() {
    _initializePlayer();
  }
  
  void _initializePlayer() {
    try {
      // Create a new player instance
      _disposeCurrentPlayer();
      _player = AudioPlayer();
      _setupPlayerListeners();
    } catch (e) {
      _setError('Error initializing player: $e');
    }
  }
  
  void _setupPlayerListeners() {
    if (_player == null) return;
    
    // Clear previous subscriptions if any
    _cancelSubscriptions();
    
    try {
      // Listen to player state changes
      _subscriptions.add(_player!.onPlayerStateChanged.listen((state) {
        _isPlaying = state == PlayerState.playing;
        notifyListeners();
      }, onError: (e) {
        debugPrint('Player state error: $e');
      }));
      
      // Listen to duration changes
      _subscriptions.add(_player!.onDurationChanged.listen((newDuration) {
        _duration = newDuration;
        notifyListeners();
      }, onError: (e) {
        debugPrint('Duration stream error: $e');
      }));
      
      // Listen to position changes
      _subscriptions.add(_player!.onPositionChanged.listen((newPosition) {
        _position = newPosition;
        notifyListeners();
      }, onError: (e) {
        debugPrint('Position stream error: $e');
      }));
      
      // Listen for completion
      _subscriptions.add(_player!.onPlayerComplete.listen((_) {
        // Reset position to beginning
        _player?.seek(Duration.zero);
        _isPlaying = false;
        notifyListeners();
      }, onError: (e) {
        debugPrint('Player complete error: $e');
      }));
    } catch (e) {
      debugPrint('Error setting up listeners: $e');
    }
  }
  
  void _cancelSubscriptions() {
    for (var subscription in _subscriptions) {
      subscription?.cancel();
    }
    _subscriptions = [];
  }
  
  // Load a file for playback
  Future<void> loadFile(String filePath) async {
    // Reset error state
    _hasError = false;
    _errorMessage = '';
    
    try {
      if (!File(filePath).existsSync()) {
        _setError('File does not exist: $filePath');
        return;
      }
      
      // On Windows, recreate the player for each file to avoid threading issues
      if (Platform.isWindows) {
        _initializePlayer();
      }
      
      try {
        if (_player == null) {
          _initializePlayer();
        }
        
        // Wrap in a try-catch to handle potential PlatformExceptions
        try {
          // For audioplayers, we use setSource with a DeviceFileSource
          await _player!.setSource(DeviceFileSource(filePath));
          _isLoaded = true;
          _currentFilePath = filePath;
          notifyListeners();
        } on PlatformException catch (e) {
          debugPrint('Platform exception loading file: $e');
          // Try one more time with a recreated player
          _initializePlayer();
          await Future.delayed(const Duration(milliseconds: 500));
          await _player!.setSource(DeviceFileSource(filePath));
          _isLoaded = true;
          _currentFilePath = filePath;
          notifyListeners();
        }
      } catch (e) {
        _setError('Error loading audio: $e');
      }
    } catch (e) {
      _setError('Error loading audio file: $e');
    }
  }
  
  // Play or pause the current track
  Future<void> togglePlay() async {
    if (!_isLoaded || _player == null) return;
    
    try {
      if (_isPlaying) {
        await _player!.pause();
      } else {
        // For Windows, add a safety check
        if (Platform.isWindows && _currentFilePath != null && !_isPlaying) {
          // Check if we need to reload the file
          if (_position == Duration.zero && _duration == Duration.zero) {
            await loadFile(_currentFilePath!);
          }
        }
        await _player!.resume();
      }
    } catch (e) {
      _setError('Error toggling playback: $e');
    }
  }
  
  // Seek to a specific position
  Future<void> seekTo(Duration position) async {
    if (!_isLoaded || _player == null) return;
    
    try {
      await _player!.seek(position);
    } catch (e) {
      debugPrint('Error seeking: $e');
    }
  }
  
  // Seek by percentage (0.0 to 1.0)
  Future<void> seekByPercentage(double percentage) async {
    if (!_isLoaded || _duration == Duration.zero || _player == null) return;
    
    final newPosition = Duration(
      milliseconds: (percentage * _duration.inMilliseconds).round(),
    );
    await seekTo(newPosition);
  }
  
  // Set error state
  void _setError(String message) {
    _hasError = true;
    _errorMessage = message;
    _isLoaded = false;
    debugPrint('AudioPlayer error: $message');
    notifyListeners();
  }
  
  // Attempt to fix player issues
  Future<void> tryRepairPlayer() async {
    _initializePlayer();
    if (_currentFilePath != null) {
      await Future.delayed(const Duration(milliseconds: 500));
      await loadFile(_currentFilePath!);
    }
  }
  
  void _disposeCurrentPlayer() {
    _cancelSubscriptions();
    _player?.dispose();
    _player = null;
  }
  
  // Clean up resources
  @override
  void dispose() {
    _disposeCurrentPlayer();
    super.dispose();
  }
}