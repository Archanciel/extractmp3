import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/audio_file.dart';
import '../models/extraction_result.dart';

class AudioExtractorViewModel extends ChangeNotifier {
  AudioFile _audioFile = AudioFile();
  double _startPosition = 0.0;
  double _endPosition = 60.0;
  ExtractionResult _extractionResult = ExtractionResult.initial();
  
  // Getters
  AudioFile get audioFile => _audioFile;
  double get startPosition => _startPosition;
  double get endPosition => _endPosition;
  ExtractionResult get extractionResult => _extractionResult;
  
  // Setters
  set startPosition(double value) {
    if (value >= 0 && value < _endPosition) {
      _startPosition = value;
      notifyListeners();
    }
  }
  
  set endPosition(double value) {
    if (value > _startPosition && value <= _audioFile.duration) {
      _endPosition = value;
      notifyListeners();
    }
  }
  
  // Set audio file from the View
  void setAudioFile(String path, String name, double duration) {
    _audioFile = AudioFile(path: path, name: name, duration: duration);
    // Reset positions when a new file is selected
    _startPosition = 0.0;
    _endPosition = duration;
    _extractionResult = ExtractionResult(
      status: ExtractionStatus.none,
      message: 'File selected: $name',
    );
    notifyListeners();
  }
  
  // Set error message
  void setError(String errorMessage) {
    _extractionResult = ExtractionResult.error(errorMessage);
    notifyListeners();
  }
  
  // Start processing
  void startProcessing() {
    _extractionResult = ExtractionResult.processing();
    notifyListeners();
  }
  
  // Extract a portion of the MP3 file
  Future<void> extractMP3(String outputPath) async {
    if (_audioFile.path == null) {
      _extractionResult = ExtractionResult.error(
        'Please select an MP3 file first',
      );
      notifyListeners();
      return;
    }
    
    try {
      // For Windows, use the system's FFmpeg directly
      try {
        // Different approach - reencode instead of stream copy
        final List<String> arguments = [
          '-i', _audioFile.path!,
          '-ss', _startPosition.toString(),
          '-to', _endPosition.toString(),
          '-acodec', 'libmp3lame', // Use MP3 encoder instead of copy
          '-b:a', '192k', // Set bitrate
          outputPath,
          '-y', // Overwrite output files without asking
        ];
        
        // Print the command for debugging
        debugPrint('FFmpeg command: ffmpeg ${arguments.join(' ')}');
        
        // Execute FFmpeg as a process
        final ProcessResult result = await Process.run('ffmpeg', arguments);
        if (result.exitCode == 0) {
          _extractionResult = ExtractionResult.success(outputPath);
        } else {
          _extractionResult = ExtractionResult.error(
            'Error processing file: ${result.stderr}',
          );
          debugPrint('FFmpeg stderr: ${result.stderr}');
          debugPrint('FFmpeg stdout: ${result.stdout}');
        }
        notifyListeners();
      } catch (e) {
        _extractionResult = ExtractionResult.error(
          'FFmpeg error: $e\n\nMake sure FFmpeg is installed and in your PATH.',
        );
        notifyListeners();
      }
    } catch (e) {
      _extractionResult = ExtractionResult.error('Error during extraction: $e');
      notifyListeners();
    }
  }
  
  // Reset extraction result
  void resetExtractionResult() {
    _extractionResult = ExtractionResult.initial();
    notifyListeners();
  }
}