import '../utils/time_format_util.dart';

class AudioSegment {
  final double startPosition;
  final double endPosition;
  final double silenceDuration; // Duration of silence to add after this segment

  AudioSegment({
    required this.startPosition,
    required this.endPosition,
    this.silenceDuration = 0.0,
  });

  // Duration of this segment in seconds
  double get duration =>
      TimeFormatUtil.normalizeToTenths(endPosition - startPosition);

  // Copy with method for easy updates
  AudioSegment copyWith({
    double? startPosition,
    double? endPosition,
    double? silenceDuration,
  }) {
    return AudioSegment(
      startPosition: startPosition ?? this.startPosition,
      endPosition: endPosition ?? this.endPosition,
      silenceDuration: silenceDuration ?? this.silenceDuration,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'startPosition': startPosition,
      'endPosition': endPosition,
      'silenceDuration': silenceDuration,
    };
  }

  factory AudioSegment.fromMap(Map<String, dynamic> map) {
    return AudioSegment(
      startPosition: map['startPosition'] as double,
      endPosition: map['endPosition'] as double,
      silenceDuration: map['silenceDuration'] as double? ?? 0.0,
    );
  }
}
