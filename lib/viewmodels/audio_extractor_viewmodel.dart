import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
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
    _audioFile = AudioFile(
      path: path,
      name: name,
      duration: duration,
    );
    
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
      _extractionResult = ExtractionResult.error('Please select an MP3 file first');
      notifyListeners();
      return;
    }

    try {
      // For Windows, use the system's FFmpeg directly
      if (Platform.isWindows) {
        try {
          // Different approach - reencode instead of stream copy
          final List<String> arguments = [
            '-i', _audioFile.path!,
            '-ss', _startPosition.toString(),
            '-to', _endPosition.toString(),
            '-acodec', 'libmp3lame',  // Use MP3 encoder instead of copy
            '-b:a', '192k',           // Set bitrate
            outputPath,
            '-y'  // Overwrite output files without asking
          ];

          // Print the command for debugging
          debugPrint('FFmpeg command: ffmpeg ${arguments.join(' ')}');

          // Execute FFmpeg as a process
          final ProcessResult result = await Process.run('ffmpeg', arguments);
          
          if (result.exitCode == 0) {
            _extractionResult = ExtractionResult.success(outputPath);
          } else {
            _extractionResult = ExtractionResult.error('Error processing file: ${result.stderr}');
            debugPrint('FFmpeg stderr: ${result.stderr}');
            debugPrint('FFmpeg stdout: ${result.stdout}');
          }
          notifyListeners();
        } catch (e) {
          _extractionResult = ExtractionResult.error(
            'FFmpeg error: $e\n\nMake sure FFmpeg is installed and in your PATH.'
          );
          notifyListeners();
        }
      } else {
        // For mobile platforms, also change to reencode
        final String command = '-i "${_audioFile.path}" -ss $_startPosition -to $_endPosition -acodec libmp3lame -b:a 192k "$outputPath" -y';
        
        await FFmpegKit.executeAsync(
          command,
          (session) async {
            final returnCode = await session.getReturnCode();
            
            if (ReturnCode.isSuccess(returnCode)) {
              _extractionResult = ExtractionResult.success(outputPath);
            } else {
              _extractionResult = ExtractionResult.error(
                'Error processing file: ${returnCode?.getValue() ?? "Unknown error"}'
              );
            }
            notifyListeners();
          },
          (log) {
            debugPrint("FFmpeg Log: $log");
          },
          (statistics) {
            // Process statistics updates if needed
          },
        );
      }
    } catch (e) {
      _extractionResult = ExtractionResult.error('Error during extraction: $e');
      notifyListeners();
    }
  }
}
