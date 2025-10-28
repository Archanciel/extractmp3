import 'dart:io';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

class AudioExtractorService {
  static const MethodChannel _channel = MethodChannel('audio_extractor');
  static const MethodChannel _durationChannel = MethodChannel('audio_duration');
  static final Logger logger = Logger();

  /// Get audio duration in seconds
  static Future<double> getAudioDuration(String filePath) async {
    if (Platform.isAndroid || Platform.isIOS) {
      // Use native method for mobile
      try {
        final result = await _durationChannel.invokeMethod('getDuration', {
          'filePath': filePath,
        });
        return (result as num).toDouble();
      } catch (e) {
        logger.i('Error getting duration: $e');
        return 60.0; // Default fallback
      }
    } else {
      // Use FFmpeg for desktop
      return await getMP3Duration(filePath);
    }
  }
  
  static Future<double> getMP3Duration(String filePath) async {
    try {
      // For Windows, use direct FFmpeg command
      final List<String> arguments = [
        '-i',
        filePath,
        '-v',
        'quiet',
        '-show_entries',
        'format=duration',
        '-of',
        'default=noprint_wrappers=1:nokey=1',
        '-sexagesimal',
      ];

      final ProcessResult result = await Process.run('ffprobe', arguments);
      if (result.exitCode == 0) {
        // Parse the duration string (HH:MM:SS.MS format)
        String durationStr = (result.stdout as String).trim();

        // Simple parsing for HH:MM:SS.MS format
        List<String> parts = durationStr.split(':');
        if (parts.length == 3) {
          int hours = int.parse(parts[0]);
          int minutes = int.parse(parts[1]);
          double seconds = double.parse(parts[2]);
          return (hours * 3600) + (minutes * 60) + seconds;
        }

        // Fallback - try direct parsing as seconds
        return double.tryParse(durationStr) ?? 60.0;
      }
      return 60.0; // Default fallback
    } catch (e) {
      logger.i('Error getting duration: $e');
      return 60.0; // Default duration if we can't determine it
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
        '-i', inputPath,
        '-ss', startTime.toString(),
        '-to', endTime.toString(),
        '-acodec', 'libmp3lame',
        '-b:a', '192k',
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