// lib/models/audio_segment.dart
class AudioSegment {
  final String title;                // ← required
  final double startPosition;
  final double endPosition;
  final double silenceDuration;

  AudioSegment({
    required this.title,             // ← required
    required this.startPosition,
    required this.endPosition,
    this.silenceDuration = 0.0,
  });

  double get duration => endPosition - startPosition;

  AudioSegment copyWith({
    String? title,
    double? startPosition,
    double? endPosition,
    double? silenceDuration,
  }) {
    return AudioSegment(
      title: title ?? this.title,
      startPosition: startPosition ?? this.startPosition,
      endPosition: endPosition ?? this.endPosition,
      silenceDuration: silenceDuration ?? this.silenceDuration,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'startPosition': startPosition,
        'endPosition': endPosition,
        'silenceDuration': silenceDuration,
      };

  factory AudioSegment.fromMap(Map<String, dynamic> map) {
    return AudioSegment(
      title: (map['title'] as String).trim(),
      startPosition: (map['startPosition'] as num).toDouble(),
      endPosition: (map['endPosition'] as num).toDouble(),
      silenceDuration: (map['silenceDuration'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
