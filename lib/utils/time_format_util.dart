// lib/utils/time_format_util.dart
class TimeFormatUtil {
  // Nombre de décisecondes dans 1h / 1min / 1s
  static const int _dsPerHour = 36000; // 3600 * 10
  static const int _dsPerMin  = 600;   // 60 * 10
  static const int _dsPerSec  = 10;

  /// Convertit un nombre de secondes flottant en décisecondes (entier),
  /// avec arrondi correct et normalisation.
  static int _toDeciseconds(double seconds) {
    if (seconds.isNaN || seconds.isInfinite) return 0;
    // Arrondi au déciseconde et clamp minimal
    final int ds = (seconds * 10).round();
    return ds < 0 ? 0 : ds;
  }

  /// Formate un double (secondes) en "h:mm:ss.t" de façon exacte.
  static String formatSeconds(double seconds) {
    final int dsTotal = _toDeciseconds(seconds);

    final int hours   = dsTotal ~/ _dsPerHour;
    final int remH    = dsTotal %  _dsPerHour;
    final int minutes = remH    ~/ _dsPerMin;
    final int remM    = remH    %  _dsPerMin;
    final int secs    = remM    ~/ _dsPerSec;
    final int tenths  = remM    %  _dsPerSec;

    final String mm = hours > 0 ? minutes.toString().padLeft(2, '0') : '$minutes';
    final String ss = secs.toString().padLeft(2, '0');
    final String h  = hours > 0 ? '$hours:' : '';
    return '$h$mm:$ss.$tenths';
  }

  /// Formate une Duration en "h:mm:ss.t"
  static String formatDuration(Duration d) {
    return formatSeconds(d.inMilliseconds / 1000.0);
  }

  /// Parse flexible : "h:mm:ss.t", "mm:ss.t", "ss.t" ou "123.4".
  /// Retourne un double normalisé à 1 décimale (ds/10.0) pour cohérence.
  static double parseFlexible(String input) {
    final s = input.trim();
    if (s.isEmpty) return 0.0;

    int dsTotal;

    if (!s.contains(':')) {
      // Forme "ss" ou "ss.xxx"
      final val = double.tryParse(s) ?? 0.0;
      dsTotal = _toDeciseconds(val);
      return dsTotal / 10.0;
    }

    // Split fraction (après le point) en retirant tout char non numérique
    final parts = s.split('.');
    final main = parts[0];
    int fracDs = 0;
    if (parts.length > 1 && parts[1].isNotEmpty) {
      final onlyDigits = parts[1].replaceAll(RegExp(r'[^0-9]'), '');
      if (onlyDigits.isNotEmpty) {
        // On autorise plusieurs décimales : "28:56.123" → 1 déciseconde arrondi
        final frac = double.tryParse('0.$onlyDigits') ?? 0.0;
        fracDs = (frac * 10).round().clamp(0, 9);
      }
    }

    final mmss = main.split(':').map((e) => e.trim()).toList();
    int hours = 0, minutes = 0, secs = 0;

    if (mmss.length == 3) {
      hours   = int.tryParse(mmss[0]) ?? 0;
      minutes = int.tryParse(mmss[1]) ?? 0;
      secs    = int.tryParse(mmss[2]) ?? 0;
    } else if (mmss.length == 2) {
      minutes = int.tryParse(mmss[0]) ?? 0;
      secs    = int.tryParse(mmss[1]) ?? 0;
    } else if (mmss.length == 1) {
      secs    = int.tryParse(mmss[0]) ?? 0;
    }

    // Normalisation en décisecondes
    dsTotal  = hours   * _dsPerHour
             + minutes * _dsPerMin
             + secs    * _dsPerSec
             + fracDs;

    if (dsTotal < 0) dsTotal = 0;
    return dsTotal / 10.0;
  }
}
