import 'dart:io';
import 'package:path/path.dart' as p;

/// Utility class for file path and name handling, cross-platform.
class PathUtil {
  /// Returns the file name (with extension) from a full path.
  static String fileName(String fullPath) {
    return p.basename(fullPath);
  }

  static String getPathFromPathFileName({
    required String pathFileName,
  }) {
    return p.dirname(pathFileName);
  }

  /// Returns the file name **without extension** from a full path or name.
  ///
  /// Examples:
  /// ```
  /// PathUtil.fileNameWithoutExtension("C:/music/song.mp3"); // → "song"
  /// PathUtil.fileNameWithoutExtension("song.mp3");          // → "song"
  /// PathUtil.fileNameWithoutExtension("archive.tar.gz");    // → "archive.tar"
  /// ```
  static String fileNameWithoutExtension(String pathOrName) {
    return p.basenameWithoutExtension(pathOrName);
  }

  /// Joins multiple path components safely across all platforms.
  ///
  /// Examples:
  /// ```
  /// PathUtil.joinPath("/home/user", "music", "file.mp3");
  /// PathUtil.joinPath("C:\\data", "audio", "clip.mp3");
  /// ```
  static String joinPath(String part1, [String? part2, String? part3]) {
    final parts = [
      part1,
      if (part2 != null && part2.isNotEmpty) part2,
      if (part3 != null && part3.isNotEmpty) part3,
    ];
    return p.joinAll(parts);
  }

  /// Sanitizes a file name by replacing forbidden characters (for example `:/\?*<>|`)
  /// and trimming spaces.
  static String sanitizeFileName(String name) {
    const forbidden = r'<>:"/\|?*';
    final sanitized = name
        .replaceAll(RegExp('[$forbidden]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return sanitized;
  }

  /// Returns the directory of a given file path.
  static String directoryOf(String fullPath) {
    return p.dirname(fullPath);
  }

  /// Ensures that a directory exists (creates it if missing).
  static Future<void> ensureDirExists(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }
}
