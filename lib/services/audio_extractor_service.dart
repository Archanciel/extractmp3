import 'dart:io';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

import '../models/audio_segment.dart';

class AudioExtractorService {
  static const MethodChannel _channel = MethodChannel('audio_extractor');
  static const MethodChannel _durationChannel = MethodChannel('audio_duration');
  static final Logger logger = Logger();
  
  // Constant for default silence duration between segments (in seconds)
  static const double defaultSilenceDuration = 1.0;
  
  // Path to the 1-second silence MP3 asset
  static const String silenceAssetPath = 'assets/mp3/1-second-of-silence.mp3';

  /// Get audio duration in seconds
  static Future<double> getAudioDuration({required String filePath}) async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final result = await _durationChannel.invokeMethod('getDuration', {
          'filePath': filePath,
        });
        return (result as num).toDouble();
      } catch (e) {
        logger.i('Error getting duration: $e');
        return 60.0;
      }
    } else {
      return await _getMP3Duration(filePath: filePath);
    }
  }

  static Future<double> _getMP3Duration({required String filePath}) async {
    try {
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
        String durationStr = (result.stdout as String).trim();
        List<String> parts = durationStr.split(':');
        if (parts.length == 3) {
          int hours = int.parse(parts[0]);
          int minutes = int.parse(parts[1]);
          double seconds = double.parse(parts[2]);
          return (hours * 3600) + (minutes * 60) + seconds;
        }
        return double.tryParse(durationStr) ?? 60.0;
      }
      return 60.0;
    } catch (e) {
      logger.i('Error getting duration: $e');
      return 60.0;
    }
  }

  /// Copy the 1-second silence asset to a temporary file
  /// Returns the path to the copied silence file
  static Future<String> _copySilenceAssetToTemp(String tempDir) async {
    final silencePath = '$tempDir${Platform.pathSeparator}silence_1sec.mp3';
    final silenceFile = File(silencePath);
    
    // Only copy if it doesn't already exist
    if (!silenceFile.existsSync()) {
      logger.i('📋 Copying silence asset to temp...');
      final ByteData data = await rootBundle.load(silenceAssetPath);
      final List<int> bytes = data.buffer.asUint8List();
      await silenceFile.writeAsBytes(bytes);
      logger.i('✅ Silence asset copied - Size: ${bytes.length} bytes');
    } else {
      logger.i('✅ Using existing silence file');
    }
    
    return silencePath;
  }
  
  /// Creates silence by copying the asset file multiple times if needed
  /// For durations > 1 second, concatenates multiple copies
  static Future<String?> _createSilenceFile({
    required String outputPath,
    required double duration,
    required String silenceAssetPath,
  }) async {
    logger.i('🔇 Creating ${duration}s silence using asset file...');
    
    try {
      if (duration == 1.0) {
        // Simple case: just copy the 1-second file
        final silenceAsset = File(silenceAssetPath);
        await silenceAsset.copy(outputPath);
        logger.i('✅ Copied 1-second silence');
        return outputPath;
      } else if (duration < 1.0) {
        // For less than 1 second, we'll just use the 1-second file
        // (Could trim it with FFmpeg, but simpler to just use 1 second)
        logger.i('⚠️ Requested ${duration}s, using 1.0s instead');
        final silenceAsset = File(silenceAssetPath);
        await silenceAsset.copy(outputPath);
        return outputPath;
      } else {
        // For more than 1 second, concatenate multiple 1-second files
        final numCopies = duration.round();
        logger.i('📝 Concatenating $numCopies copies of 1-second silence...');
        
        final tempDir = File(outputPath).parent.path;
        final concatFilePath = '$tempDir${Platform.pathSeparator}silence_concat_${DateTime.now().millisecondsSinceEpoch}.txt';
        
        // Create concat file with multiple references to the same silence file
        final concatContent = List.generate(
          numCopies,
          (i) => "file '${silenceAssetPath.replaceAll('\\', '/')}'",
        ).join('\n');
        
        await File(concatFilePath).writeAsString(concatContent);
        
        // Concatenate using FFmpeg
        final args = [
          '-f',
          'concat',
          '-safe',
          '0',
          '-i',
          concatFilePath.replaceAll('\\', '/'),
          '-acodec',
          'copy',
          outputPath.replaceAll('\\', '/'),
          '-y',
          '-v',
          'error',
        ];
        
        final result = await Process.run('ffmpeg', args);
        
        // Clean up concat file
        try {
          await File(concatFilePath).delete();
        } catch (_) {}
        
        if (result.exitCode == 0 && File(outputPath).existsSync()) {
          logger.i('✅ Created ${duration}s silence');
          return outputPath;
        } else {
          logger.e('❌ Failed to create multi-second silence: ${result.stderr}');
          // Fallback: just use 1 second
          final silenceAsset = File(silenceAssetPath);
          await silenceAsset.copy(outputPath);
          logger.i('⚠️ Fallback: using 1-second silence');
          return outputPath;
        }
      }
    } catch (e) {
      logger.e('❌ Error creating silence: $e');
      return null;
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

  /// Desktop implementation for multiple segments using FFmpeg and asset silence file
  static Future<Map<String, dynamic>> _extractSegmentsWithFFmpeg({
    required String inputPath,
    required String outputPath,
    required List<AudioSegment> segments,
  }) async {
    try {
      final tempDir = Directory.systemTemp.createTempSync('mp3_extract_');
      final segmentFiles = <String>[];

      try {
        logger.i('🎬 Starting extraction of ${segments.length} segments...');
        logger.i('📂 Temp directory: ${tempDir.path}');
        
        // Copy the silence asset once for reuse
        final silenceAssetPath = await _copySilenceAssetToTemp(tempDir.path);
        
        // Extract each segment and add silence
        for (int i = 0; i < segments.length; i++) {
          final segment = segments[i];
          final segmentPath =
              '${tempDir.path}${Platform.pathSeparator}segment_$i.mp3';

          logger.i('\n📍 Segment ${i + 1}/${segments.length}:');
          logger.i('   Start: ${segment.startPosition}s');
          logger.i('   End: ${segment.endPosition}s');
          logger.i('   Duration: ${segment.duration}s');

          // Extract segment
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
            '32k',
            segmentPath,
            '-y',
            '-v',
            'error',
          ];

          logger.i('   🎬 Extracting segment...');
          final result = await Process.run('ffmpeg', arguments);
          
          if (result.exitCode != 0) {
            logger.e('❌ Failed to extract segment ${i + 1}');
            logger.e('   stderr: ${result.stderr}');
            return {
              'success': false,
              'message': 'Failed to extract segment ${i + 1}: ${result.stderr}',
              'outputPath': null,
            };
          }

          // Verify segment file
          final segmentFile = File(segmentPath);
          if (!segmentFile.existsSync()) {
            logger.e('❌ Segment file not found after extraction!');
            return {
              'success': false,
              'message': 'Segment file not created: $segmentPath',
              'outputPath': null,
            };
          }

          final segmentSize = segmentFile.lengthSync();
          segmentFiles.add(segmentPath);
          logger.i('   ✅ Segment extracted - Size: $segmentSize bytes');

          // Determine silence duration
          double silenceDurationToAdd = 0.0;
          
          if (segment.silenceDuration > 0) {
            silenceDurationToAdd = segment.silenceDuration;
            logger.i('   🔇 User-defined silence: ${silenceDurationToAdd}s');
          } else if (i < segments.length - 1) {
            silenceDurationToAdd = defaultSilenceDuration;
            logger.i('   🔇 Default silence: ${silenceDurationToAdd}s');
          } else {
            logger.i('   🔇 Last segment - no silence');
          }

          // Add silence if needed
          if (silenceDurationToAdd > 0) {
            final silencePath =
                '${tempDir.path}${Platform.pathSeparator}silence_$i.mp3';

            final createdSilencePath = await _createSilenceFile(
              outputPath: silencePath,
              duration: silenceDurationToAdd,
              silenceAssetPath: silenceAssetPath,
            );

            if (createdSilencePath != null) {
              final silenceFile = File(createdSilencePath);
              final silenceSize = silenceFile.lengthSync();
              segmentFiles.add(createdSilencePath);
              logger.i('   ✅ Silence added - Size: $silenceSize bytes');
            } else {
              logger.w('   ⚠️ Warning: Could not create silence file');
              logger.w('   Continuing without silence for this segment...');
            }
          }
        }

        logger.i('\n📝 Files to concatenate: ${segmentFiles.length}');
        
        // Verify all files
        for (int i = 0; i < segmentFiles.length; i++) {
          final file = File(segmentFiles[i]);
          if (file.existsSync()) {
            logger.i('   ✅ File $i: ${file.lengthSync()} bytes');
          } else {
            logger.e('   ❌ File $i missing!');
          }
        }

        // Create concat file
        final concatFilePath =
            '${tempDir.path}${Platform.pathSeparator}concat.txt';
        final concatFile = File(concatFilePath);
        
        final concatContent = segmentFiles.map((f) {
          String path = f.replaceAll('\\', '/');
          path = path.replaceAll("'", "'\\''");
          return "file '$path'";
        }).join('\n');
        
        logger.i('\n📋 Concat file:');
        logger.i(concatContent);
        await concatFile.writeAsString(concatContent);

        // Concatenate
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
          outputPathForFFmpeg,
          '-y',
          '-v',
          'error',
        ];

        logger.i('\n🔗 Concatenating files...');
        final concatResult = await Process.run('ffmpeg', concatArgs);

        if (concatResult.exitCode == 0) {
          final outputFile = File(outputPath);
          if (outputFile.existsSync()) {
            final outputSize = outputFile.lengthSync();
            logger.i('🎉 SUCCESS!');
            logger.i('   Output: $outputPath');
            logger.i('   Size: $outputSize bytes');
            
            return {
              'success': true,
              'message': 'Extraction successful',
              'outputPath': outputPath,
            };
          } else {
            logger.e('❌ Output file not created');
            return {
              'success': false,
              'message': 'Output file not found: $outputPath',
              'outputPath': null,
            };
          }
        } else {
          logger.e('❌ Concatenation failed');
          logger.e('   Exit code: ${concatResult.exitCode}');
          logger.e('   stderr: ${concatResult.stderr}');
          
          String errorMessage = 'Failed to concatenate segments';
          String errorStderr = concatResult.stderr.toString();
          
          if (errorStderr.contains('Permission denied')) {
            errorMessage = 'Permission denied. Stop audio playback and try again.';
          } else if (errorStderr.contains('No such file or directory')) {
            errorMessage = 'File not found during concatenation.';
          }
          
          return {
            'success': false,
            'message': '$errorMessage\n\nDetails: ${concatResult.stderr}',
            'outputPath': null,
          };
        }
      } finally {
        try {
          tempDir.deleteSync(recursive: true);
          logger.i('🧹 Temp directory cleaned up');
        } catch (e) {
          logger.w('⚠️ Could not clean up temp: $e');
        }
      }
    } catch (e) {
      logger.e('💥 Exception: $e');
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
        '32k',
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