import 'dart:io';
import 'package:flutter/services.dart';

class AudioExtractorService {
  static const MethodChannel _channel = MethodChannel('audio_extractor');
  static const MethodChannel _durationChannel = MethodChannel('audio_duration');

  /// Get audio duration in seconds
  static Future<double> getAudioDuration(String filePath) async {
    if (Platform.isAndroid) {
      try {
        final result = await _durationChannel.invokeMethod('getDuration', {
          'filePath': filePath,
        });
        return (result as num).toDouble();
      } catch (e) {
        print('Error getting duration: $e');
        return 60.0; // Default fallback
      }
    } else {
      // For desktop, we can try to use FFprobe or just return a default
      return 60.0;
    }
  }

  /// Extract audio segment using platform-specific implementation
  static Future<Map<String, dynamic>> extractAudio({
    required String inputPath,
    required String outputPath,
    required double startTime,
    required double endTime,
  }) async {
    if (Platform.isAndroid) {
      return await _extractOnAndroid(
        inputPath: inputPath,
        outputPath: outputPath,
        startTime: startTime,
        endTime: endTime,
      );
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return await _extractWithFFmpeg(
        inputPath: inputPath,
        outputPath: outputPath,
        startTime: startTime,
        endTime: endTime,
      );
    } else {
      throw UnsupportedError('Platform not supported');
    }
  }

  /// Android implementation using MediaCodec
  static Future<Map<String, dynamic>> _extractOnAndroid({
    required String inputPath,
    required String outputPath,
    required double startTime,
    required double endTime,
  }) async {
    try {
      final result = await _channel.invokeMethod('extractAudio', {
        'inputPath': inputPath,
        'outputPath': outputPath,
        'startTime': startTime,
        'endTime': endTime,
      });

      return {
        'success': result['success'] as bool,
        'message': result['message'] as String,
        'outputPath': result['outputPath'] as String?,
      };
    } on PlatformException catch (e) {
      return {
        'success': false,
        'message': 'Android extraction error: ${e.message}',
        'outputPath': null,
      };
    }
  }

  /// Desktop implementation using FFmpeg
  static Future<Map<String, dynamic>> _extractWithFFmpeg({
    required String inputPath,
    required String outputPath,
    required double startTime,
    required double endTime,
  }) async {
    try {
      final List<String> arguments = [
        '-i',
        inputPath,
        '-ss',
        startTime.toString(),
        '-to',
        endTime.toString(),
        '-acodec',
        'libmp3lame',
        '-b:a',
        '192k',
        outputPath,
        '-y',
      ];

      final ProcessResult result = await Process.run('ffmpeg', arguments);

      if (result.exitCode == 0) {
        return {
          'success': true,
          'message': 'Extraction successful',
          'outputPath': outputPath,
        };
      } else {
        return {
          'success': false,
          'message': 'FFmpeg error: ${result.stderr}',
          'outputPath': null,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'FFmpeg error: $e\n\nMake sure FFmpeg is installed.',
        'outputPath': null,
      };
    }
  }
}
