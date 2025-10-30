import 'package:flutter/foundation.dart';
import '../models/audio_file.dart';
import '../models/audio_segment.dart';
import '../models/extraction_result.dart';
import '../services/audio_extractor_service.dart';

class AudioExtractorVM extends ChangeNotifier {
  AudioFile _audioFile = AudioFile();
  List<AudioSegment> _segments = [];
  ExtractionResult _extractionResult = ExtractionResult.initial();

  // Getters
  AudioFile get audioFile => _audioFile;
  List<AudioSegment> get segments => List.unmodifiable(_segments);
  ExtractionResult get extractionResult => _extractionResult;
  
  // Computed properties
  double get totalDuration {
    return _segments.fold(0.0, (sum, segment) => 
      sum + segment.duration + segment.silenceDuration);
  }
  
  int get segmentCount => _segments.length;

  void setAudioFile({
    required String path,
    required String name,
    required double duration,
  }) {
    _audioFile = AudioFile(path: path, name: name, duration: duration);
    // Clear segments when new file is loaded
    _segments = [];
    _extractionResult = ExtractionResult(
      status: ExtractionStatus.none,
      message: 'File selected: $name',
    );
    notifyListeners();
  }
  
  void addSegment(AudioSegment segment) {
    _segments.add(segment);
    notifyListeners();
  }
  
  void updateSegment(int index, AudioSegment segment) {
    if (index >= 0 && index < _segments.length) {
      _segments[index] = segment;
      notifyListeners();
    }
  }
  
  void removeSegment(int index) {
    if (index >= 0 && index < _segments.length) {
      _segments.removeAt(index);
      notifyListeners();
    }
  }
  
  void clearSegments() {
    _segments.clear();
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
    
    if (_segments.isEmpty) {
      _extractionResult = ExtractionResult.error(
        'Please add at least one segment to extract',
      );
      notifyListeners();
      return;
    }

    try {
      startProcessing();

      final result = await AudioExtractorService.extractAudioSegments(
        inputPath: _audioFile.path!,
        outputPath: outputPath,
        segments: _segments,
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