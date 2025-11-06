import 'dart:io';

class PathUtil {
  static final RegExp _illegal = RegExp(r'[<>:"/\\|?*\x00-\x1F]');
  static final RegExp _dots = RegExp(r'[. ]+$');

  static String sanitizeFileName(String name) {
    // Replace illegal chars with '-'
    String n = name.replaceAll(_illegal, '-');
    // Collapse multiple spaces/dashes
    n = n.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'-{2,}'), '-').trim();
    // Remove trailing dots/spaces (Windows)
    n = n.replaceAll(_dots, '');
    // Guard empty
    if (n.isEmpty) n = 'output.mp3';
    // Ensure extension for mp3
    if (!n.toLowerCase().endsWith('.mp3')) n = '$n.mp3';
    // Extra: limit length for Windows MAX_PATH (optional)
    if (Platform.isWindows && n.length > 180) {
      final ext = '.mp3';
      n = '${n.substring(0, 180 - ext.length)}$ext';
    }
    return n;
  }

  static String fileName(String fullPath) {
    final sep = Platform.pathSeparator;
    return fullPath.split(sep).last;
  }
}
