import 'package:flutter/foundation.dart';
import '../models/audio_file.dart';
import '../models/extraction_result.dart';
import '../services/audio_extractor_service.dart';

class AudioExtractorVM extends ChangeNotifier {
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

  void setAudioFile({
    required String path,
    required String name,
    required double duration,
  }) {
    _audioFile = AudioFile(path: path, name: name, duration: duration);
    _startPosition = 0.0;
    _endPosition = duration;
    _extractionResult = ExtractionResult(
      status: ExtractionStatus.none,
      message: 'File selected: $name',
    );
    notifyListeners();
  }

  void setError(String errorMessage) {
    _extractionResult = ExtractionResult.error(errorMessage);
    notifyListeners();
  }

  void startProcessing() {
    _extractionResult = ExtractionResult.processing();
    notifyListeners();
  }

  Future<void> extractMP3(String outputPath) async {
    if (_audioFile.path == null) {
      _extractionResult = ExtractionResult.error(
        'Please select an MP3 file first',
      );
      notifyListeners();
      return;
    }

    try {
      startProcessing();

      final result = await AudioExtractorService.extractAudio(
        inputPath: _audioFile.path!,
        outputPath: outputPath,
        startTime: _startPosition,
        endTime: _endPosition,
      );

      if (result['success'] == true) {
        _extractionResult = ExtractionResult.success(result['outputPath']!);
      } else {
        _extractionResult = ExtractionResult.error(result['message']);
      }
      notifyListeners();
    } catch (e) {
      _extractionResult = ExtractionResult.error('Error during extraction: $e');
      notifyListeners();
    }
  }

  void resetExtractionResult() {
    _extractionResult = ExtractionResult.initial();
    notifyListeners();
  }
}
