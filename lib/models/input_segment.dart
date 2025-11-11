// Represents one input file and the list of segments to extract from it.
import 'audio_segment.dart';

class InputSegments {
  final String inputPath;
  final List<AudioSegment> segments;
  const InputSegments({required this.inputPath, required this.segments});
}
