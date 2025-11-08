// lib/services/audio_extractor_service.dart
import 'dart:io';
import 'package:logger/logger.dart';

// Android/iOS FFmpeg/FFprobe (Dart plugin)
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../models/audio_segment.dart';

class AudioExtractorService {
  static final Logger logger = Logger();

  /// Default silence (seconds) inserted between segments when user did not specify any.
  static const double defaultSilenceDuration = 1.0;

  // ─────────────────────────────────────────────────────────────────────────────
  // Duration
  // ─────────────────────────────────────────────────────────────────────────────

  /// Returns the media duration in seconds.
  static Future<double> getAudioDuration({required String filePath}) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        // Use FFprobeKit on mobile
        final session = await FFprobeKit.getMediaInformation(filePath);
        final info = session.getMediaInformation();
        final durationStr = info?.getDuration(); // seconds as string (e.g. "123.456")
        if (durationStr != null) {
          final d = double.tryParse(durationStr);
          if (d != null && d > 0) return d;
        }
        // Fallback: 60s if unknown
        logger.w('FFprobeKit returned no duration for "$filePath", fallback to 60s');
        return 60.0;
      } else {
        // Desktop: use system ffprobe
        return await _probeDurationDesktop(filePath: filePath);
      }
    } catch (e, st) {
      logger.w('Duration probe failed for "$filePath": $e\n$st');
      return 60.0;
    }
  }

  static Future<double> _probeDurationDesktop({required String filePath}) async {
    final args = [
      '-i', filePath,
      '-v', 'quiet',
      '-show_entries', 'format=duration',
      '-of', 'default=noprint_wrappers=1:nokey=1',
    ];
    final r = await Process.run('ffprobe', args);
    if (r.exitCode == 0) {
      final out = (r.stdout as String).trim();
      final d = double.tryParse(out);
      if (d != null && d > 0) return d;
    }
    return 60.0;
    // If you prefer sexagesimal, convert it; numeric is simpler and more robust.
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Single segment extract
  // ─────────────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> extractAudio({
    required String inputPath,
    required String outputPath,
    required double startTime,
    required double endTime,
    String? encoderBitrate, // e.g. "128k" (optional)
  }) async {
    if (endTime <= startTime) {
      return {
        'success': false,
        'message': 'Invalid time range: end <= start',
        'outputPath': null,
      };
    }

    if (Platform.isAndroid || Platform.isIOS) {
      return _extractOneMobile(
        inputPath: inputPath,
        outputPath: outputPath,
        startTime: startTime,
        endTime: endTime,
        encoderBitrate: encoderBitrate ?? '128k',
      );
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return _extractOneDesktop(
        inputPath: inputPath,
        outputPath: outputPath,
        startTime: startTime,
        endTime: endTime,
        encoderBitrate: encoderBitrate ?? '128k',
      );
    } else {
      return {
        'success': false,
        'message': 'Platform not supported',
        'outputPath': null,
      };
    }
  }

  static Future<Map<String, dynamic>> _extractOneMobile({
    required String inputPath,
    required String outputPath,
    required double startTime,
    required double endTime,
    required String encoderBitrate,
  }) async {
    final dur = endTime - startTime;
    final cmd = [
      '-ss', startTime.toString(),
      '-t', dur.toString(),
      '-i', _q(inputPath),
      '-c:a', 'libmp3lame',
      '-b:a', encoderBitrate,
      _q(outputPath),
      '-y'
    ].join(' ');

    final sess = await FFmpegKit.execute(cmd);
    final rc = await sess.getReturnCode();
    if (ReturnCode.isSuccess(rc)) {
      return {'success': true, 'message': 'OK', 'outputPath': outputPath};
    } else {
      final logs = await sess.getAllLogsAsString();
      return {
        'success': false,
        'message': 'FFmpeg error (mobile one-shot):\n$logs',
        'outputPath': null,
      };
    }
  }

  static Future<Map<String, dynamic>> _extractOneDesktop({
    required String inputPath,
    required String outputPath,
    required double startTime,
    required double endTime,
    required String encoderBitrate,
  }) async {
    final args = [
      '-i', inputPath,
      '-ss', startTime.toString(),
      '-to', endTime.toString(),
      '-c:a', 'libmp3lame',
      '-b:a', encoderBitrate,
      outputPath,
      '-y',
    ];
    final r = await Process.run('ffmpeg', args);
    if (r.exitCode == 0) {
      return {'success': true, 'message': 'OK', 'outputPath': outputPath};
    } else {
      return {'success': false, 'message': 'FFmpeg error: ${r.stderr}', 'outputPath': null};
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Multiple segments extract + concat
  // ─────────────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> extractAudioSegments({
    required String inputPath,
    required String outputPath,
    required List<AudioSegment> segments,
    String? encoderBitrate, // e.g. "128k" (optional)
  }) async {
    if (segments.isEmpty) {
      return {'success': false, 'message': 'No segments to extract', 'outputPath': null};
    }

    if (Platform.isAndroid || Platform.isIOS) {
      return _extractSegmentsMobile(
        inputPath: inputPath,
        outputPath: outputPath,
        segments: segments,
        encoderBitrate: encoderBitrate ?? '128k',
      );
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return _extractSegmentsDesktop(
        inputPath: inputPath,
        outputPath: outputPath,
        segments: segments,
        encoderBitrate: encoderBitrate ?? '128k',
      );
    } else {
      return {
        'success': false,
        'message': 'Platform not supported',
        'outputPath': null,
      };
    }
  }

  /// Android/iOS path using ffmpeg_kit_flutter_new (no native Kotlin required).
  static Future<Map<String, dynamic>> _extractSegmentsMobile({
    required String inputPath,
    required String outputPath,
    required List<AudioSegment> segments,
    required String encoderBitrate,
  }) async {
    try {
      final tmp = await _tempDir(); // app cache directory
      final parts = <String>[];

      // 1) Cut each segment (encode to MP3 with your chosen quality)
      for (int i = 0; i < segments.length; i++) {
        final s = segments[i];
        final segPath = '${tmp.path}/segment_$i.mp3';

        final cut = [
          '-ss', s.startPosition.toString(),
          '-to', s.endPosition.toString(),
          '-i', _q(inputPath),
          '-c:a', 'libmp3lame',
          '-b:a', encoderBitrate,
          _q(segPath),
          '-y'
        ].join(' ');

        final cutSess = await FFmpegKit.execute(cut);
        if (!ReturnCode.isSuccess(await cutSess.getReturnCode())) {
          return {
            'success': false,
            'message': 'FFmpeg cut failed @segment ${i + 1}:\n${await cutSess.getAllLogsAsString()}',
            'outputPath': null,
          };
        }
        parts.add(segPath);

        // 2) Insert silence (user-defined or default between segments)
        final silUser = s.silenceDuration;
        final needDefault = silUser <= 0 && i < segments.length - 1;
        final silDur = silUser > 0 ? silUser : (needDefault ? defaultSilenceDuration : 0.0);
        if (silDur > 0) {
          final silPath = '${tmp.path}/silence_$i.mp3';
          final silCmd = [
            '-f', 'lavfi',
            '-i', '"anullsrc=r=44100:cl=mono"',
            '-t', silDur.toString(),
            '-c:a', 'libmp3lame',
            '-b:a', encoderBitrate,
            _q(silPath),
            '-y'
          ].join(' ');
          final silSess = await FFmpegKit.execute(silCmd);
          if (!ReturnCode.isSuccess(await silSess.getReturnCode())) {
            return {
              'success': false,
              'message': 'FFmpeg silence failed:\n${await silSess.getAllLogsAsString()}',
              'outputPath': null,
            };
          }
          parts.add(silPath);
        }
      }

      // 3) Concat list file
      final listFile = File('${tmp.path}/concat.txt')
        ..writeAsStringSync(parts.map((p) => "file '${p.replaceAll("'", "'\\''")}'").join('\n'));

      // 4) Re-encode once at the end to avoid MP3 padding gaps
      final concatCmd = [
        '-f', 'concat', '-safe', '0',
        '-i', _q(listFile.path),
        '-c:a', 'libmp3lame',
        '-b:a', encoderBitrate,
        _q(outputPath),
        '-y'
      ].join(' ');

      final concatSess = await FFmpegKit.execute(concatCmd);
      if (ReturnCode.isSuccess(await concatSess.getReturnCode())) {
        return {'success': true, 'message': 'Extraction successful', 'outputPath': outputPath};
      } else {
        return {
          'success': false,
          'message': 'FFmpeg concat failed:\n${await concatSess.getAllLogsAsString()}',
          'outputPath': null,
        };
      }
    } catch (e, st) {
      logger.e('Mobile multi-extract failed: $e\n$st');
      return {'success': false, 'message': 'Plugin error: $e', 'outputPath': null};
    }
  }

  /// Desktop path using system ffmpeg.
  static Future<Map<String, dynamic>> _extractSegmentsDesktop({
    required String inputPath,
    required String outputPath,
    required List<AudioSegment> segments,
    required String encoderBitrate,
  }) async {
    try {
      final tempDir = Directory.systemTemp.createTempSync('mp3_extract_');
      final partFiles = <String>[];

      try {
        logger.i('🎬 Extract ${segments.length} segments -> ${tempDir.path}');

        // 1) Extract every segment
        for (int i = 0; i < segments.length; i++) {
          final s = segments[i];
          final segPath = '${tempDir.path}${Platform.pathSeparator}segment_$i.mp3';

          final args = [
            '-i', inputPath,
            '-ss', s.startPosition.toString(),
            '-to', s.endPosition.toString(),
            '-c:a', 'libmp3lame',
            '-b:a', encoderBitrate,
            segPath,
            '-y', '-v', 'error',
          ];
          final r = await Process.run('ffmpeg', args);
          if (r.exitCode != 0) {
            return {
              'success': false,
              'message': 'Failed to extract segment ${i + 1}: ${r.stderr}',
              'outputPath': null,
            };
          }
          partFiles.add(segPath);

          // 2) Silence if needed
          final silUser = s.silenceDuration;
          final needDefault = silUser <= 0 && i < segments.length - 1;
          final silDur = silUser > 0 ? silUser : (needDefault ? defaultSilenceDuration : 0.0);
          if (silDur > 0) {
            final silPath = '${tempDir.path}${Platform.pathSeparator}silence_$i.mp3';
            final silArgs = [
              '-f', 'lavfi',
              '-i', 'anullsrc=r=44100:cl=mono',
              '-t', silDur.toString(),
              '-c:a', 'libmp3lame',
              '-b:a', encoderBitrate,
              silPath,
              '-y', '-v', 'error',
            ];
            final rs = await Process.run('ffmpeg', silArgs);
            if (rs.exitCode != 0) {
              return {
                'success': false,
                'message': 'Failed to create silence for segment ${i + 1}: ${rs.stderr}',
                'outputPath': null,
              };
            }
            partFiles.add(silPath);
          }
        }

        // 3) Concat using list file and re-encode once
        final concatList = File('${tempDir.path}${Platform.pathSeparator}concat.txt');
        concatList.writeAsStringSync(
          partFiles.map((f) {
            String p = f.replaceAll('\\', '/').replaceAll("'", "'\\''");
            return "file '$p'";
          }).join('\n'),
        );

        final concatArgs = [
          '-f', 'concat', '-safe', '0',
          '-i', concatList.path.replaceAll('\\', '/'),
          '-c:a', 'libmp3lame',
          '-b:a', encoderBitrate,
          outputPath.replaceAll('\\', '/'),
          '-y', '-v', 'error',
        ];

        final concatResult = await Process.run('ffmpeg', concatArgs);
        if (concatResult.exitCode == 0 && File(outputPath).existsSync()) {
          return {'success': true, 'message': 'Extraction successful', 'outputPath': outputPath};
        } else {
          final stderr = concatResult.stderr?.toString() ?? 'Unknown error';
          return {'success': false, 'message': 'Concat failed: $stderr', 'outputPath': null};
        }
      } finally {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {
          // ignore cleanup errors
        }
      }
    } catch (e, st) {
      logger.e('Desktop multi-extract failed: $e\n$st');
      return {'success': false, 'message': 'FFmpeg error: $e', 'outputPath': null};
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────────

  static String _q(String path) => '"${path.replaceAll('\\', '/')}"';

  static Future<Directory> _tempDir() async {
    // A simple cross-platform temp dir selector.
    if (Platform.isAndroid || Platform.isIOS) {
      // On mobile, use the application cache directory exposed by dart:io.
      return Directory.systemTemp;
    }
    return Directory.systemTemp;
  }
}
