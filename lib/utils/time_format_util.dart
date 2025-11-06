class TimeFormatUtil {
  /// Format seconds into h:mm:ss.t (tenths truncated, not rounded to avoid rollover).
  static String formatSeconds(double seconds) {
    if (seconds.isNaN || seconds.isInfinite || seconds < 0) seconds = 0;
    final int whole = seconds.floor();
    final int hours = whole ~/ 3600;
    final int minutes = (whole % 3600) ~/ 60;
    final int secs = whole % 60;

    // Truncate to one decimal place (tenths)
    final int tenths = ((seconds - whole) * 10).floor().clamp(0, 9);

    final String mm = hours > 0 ? minutes.toString().padLeft(2, '0') : '$minutes';
    final String ss = secs.toString().padLeft(2, '0');
    final String h = hours > 0 ? '$hours:' : '';
    return '$h$mm:$ss.$tenths';
  }

  /// Format a Dart Duration the same way (h:mm:ss.t).
  static String formatDuration(Duration d) {
    final double sec = d.inMilliseconds / 1000.0;
    return formatSeconds(sec);
  }

  /// Parse flexible inputs: supports "h:mm:ss.t", "mm:ss.t", "ss.t" or raw "123.4".
  static double parseFlexible(String input) {
    final s = input.trim();
    if (s.isEmpty) return 0.0;

    if (!s.contains(':')) {
      return double.tryParse(s) ?? 0.0;
    }

    try {
      double total = 0.0;
      final parts = s.split('.');
      final main = parts[0];
      double frac = 0.0;
      if (parts.length > 1 && parts[1].isNotEmpty) {
        // Accept any number of decimals; we keep full precision but callers may trunc.
        frac = double.tryParse('0.${parts[1].replaceAll(RegExp(r'[^0-9]'), '')}') ?? 0.0;
      }

      final mmss = main.split(':');
      if (mmss.length == 3) {
        final h = int.tryParse(mmss[0]) ?? 0;
        final m = int.tryParse(mmss[1]) ?? 0;
        final sec = int.tryParse(mmss[2]) ?? 0;
        total = h * 3600 + m * 60 + sec + frac;
      } else if (mmss.length == 2) {
        final m = int.tryParse(mmss[0]) ?? 0;
        final sec = int.tryParse(mmss[1]) ?? 0;
        total = m * 60 + sec + frac;
      } else if (mmss.length == 1) {
        final sec = int.tryParse(mmss[0]) ?? 0;
        total = sec + frac;
      }
      return total;
    } catch (_) {
      return 0.0;
    }
  }
}
