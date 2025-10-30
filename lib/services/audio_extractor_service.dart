import 'dart:io';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

import '../models/audio_segment.dart';

class AudioExtractorService {
  static const MethodChannel _channel = MethodChannel('audio_extractor');
  static const MethodChannel _durationChannel = MethodChannel('audio_duration');
  static final Logger logger = Logger();

  /// Get audio duration in seconds
  static Future<double> getAudioDuration({required String filePath}) async {
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
      return await _getMP3Duration(filePath: filePath);
    }
  }

  static Future<double> _getMP3Duration({required String filePath}) async {
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

  /// Extract multiple audio segments and combine them
  static Future<Map<String, dynamic>> extractAudioSegments({
    required String inputPath,
    required String outputPath,
    required List<AudioSegment> segments,
  }) async {
    if (Platform.isAndroid) {
      return await _extractSegmentsOnAndroid(
        inputPath: inputPath,
        outputPath: outputPath,
        segments: segments,
      );
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return await _extractSegmentsWithFFmpeg(
        inputPath: inputPath,
        outputPath: outputPath,
        segments: segments,
      );
    } else {
      throw UnsupportedError('Platform not supported');
    }
  }

  /// Android implementation for multiple segments
  static Future<Map<String, dynamic>> _extractSegmentsOnAndroid({
    required String inputPath,
    required String outputPath,
    required List<AudioSegment> segments,
  }) async {
    try {
      final segmentsList = segments.map((s) => s.toMap()).toList();

      final result = await _channel.invokeMethod('extractAudioSegments', {
        'inputPath': inputPath,
        'outputPath': outputPath,
        'segments': segmentsList,
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

  /// Desktop implementation for multiple segments using FFmpeg
  static Future<Map<String, dynamic>> _extractSegmentsWithFFmpeg({
    required String inputPath,
    required String outputPath,
    required List<AudioSegment> segments,
  }) async {
    try {
      // Create a temp directory for segment files
      final tempDir = Directory.systemTemp.createTempSync('mp3_extract_');
      final segmentFiles = <String>[];

      try {
        // Extract each segment
        for (int i = 0; i < segments.length; i++) {
          final segment = segments[i];
          final segmentPath =
              '${tempDir.path}${Platform.pathSeparator}segment_$i.mp3';

          final arguments = [
            '-i',
            inputPath,
            '-ss',
            segment.startPosition.toString(),
            '-to',
            segment.endPosition.toString(),
            '-acodec',
            'libmp3lame',
            '-b:a',
            '192k',
            segmentPath,
            '-y',
          ];

          final result = await Process.run('ffmpeg', arguments);
          if (result.exitCode != 0) {
            logger.e('Failed to extract segment $i: ${result.stderr}');
            return {
              'success': false,
              'message': 'Failed to extract segment ${i + 1}: ${result.stderr}',
              'outputPath': null,
            };
          }

          segmentFiles.add(segmentPath);

          // Add silence if needed
          if (segment.silenceDuration > 0) {
            final silencePath =
                '${tempDir.path}${Platform.pathSeparator}silence_$i.mp3';

            final silenceArgs = [
              '-f',
              'lavfi',
              '-i',
              'anullsrc=r=44100:cl=stereo',
              '-t',
              segment.silenceDuration.toString(),
              '-acodec',
              'libmp3lame',
              '-b:a',
              '192k',
              silencePath,
              '-y',
            ];

            final silenceResult = await Process.run('ffmpeg', silenceArgs);
            if (silenceResult.exitCode == 0) {
              segmentFiles.add(silencePath);
            }
          }
        }

        // Create concat file with proper path formatting for Windows
        final concatFilePath =
            '${tempDir.path}${Platform.pathSeparator}concat.txt';
        final concatFile = File(concatFilePath);
        
        // FIXED: Properly format paths for FFmpeg on Windows
        // FFmpeg concat requires forward slashes and proper escaping
        final concatContent = segmentFiles.map((f) {
          // Convert Windows backslashes to forward slashes
          String path = f.replaceAll('\\', '/');
          // Escape single quotes in the path
          path = path.replaceAll("'", "'\\''");
          return "file '$path'";
        }).join('\n');
        
        logger.i('Concat file content:\n$concatContent');
        await concatFile.writeAsString(concatContent);

        // Concatenate all segments
        // FIXED: Convert BOTH concat file path AND output path to forward slashes
        String concatFilePathForFFmpeg = concatFilePath.replaceAll('\\', '/');
        String outputPathForFFmpeg = outputPath.replaceAll('\\', '/');
        
        final concatArgs = [
          '-f',
          'concat',
          '-safe',
          '0',
          '-i',
          concatFilePathForFFmpeg,
          '-acodec',
          'copy',
          outputPathForFFmpeg,  // ← Now using converted output path!
          '-y',
        ];

        logger.i('Running FFmpeg concat with args: $concatArgs');
        final concatResult = await Process.run('ffmpeg', concatArgs);

        if (concatResult.exitCode == 0) {
          logger.i('Extraction successful!');
          return {
            'success': true,
            'message': 'Extraction successful',
            'outputPath': outputPath,
          };
        } else {
          logger.e('FFmpeg concat stderr: ${concatResult.stderr}');
          
          // Check for specific error types
          String errorStderr = concatResult.stderr.toString();
          String errorMessage = 'Failed to concatenate segments';
          
          if (errorStderr.contains('Permission denied')) {
            errorMessage = 'Permission denied. The file may be in use by another program (like the audio player). Please stop playback and try again.';
          } else if (errorStderr.contains('No such file or directory')) {
            errorMessage = 'File not found. Please check that the input file still exists.';
          }
          
          return {
            'success': false,
            'message': '$errorMessage\n\nDetails: ${concatResult.stderr}',
            'outputPath': null,
          };
        }
      } finally {
        // Clean up temp directory
        try {
          tempDir.deleteSync(recursive: true);
          logger.i('Temp directory cleaned up');
        } catch (e) {
          logger.i('Failed to clean up temp directory: $e');
        }
      }
    } catch (e) {
      logger.e('Exception during extraction: $e');
      return {
        'success': false,
        'message': 'FFmpeg error: $e',
        'outputPath': null,
      };
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