class AudioFile {
  final String? path;
  final String? name;
  final double duration;

  AudioFile({
    this.path,
    this.name,
    this.duration = 60.0, // Default duration
  });

  bool get isSelected => path != null && name != null;
}