import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../services/audio_extractor_service.dart';
import '../services/json_data_service.dart';
import '../models/audio_segment.dart';
import '../models/comment.dart';
import '../viewmodels/audio_extractor_vm.dart';
import '../viewmodels/audio_player_vm.dart';
import '../constants.dart';
import 'widgets/add_segment_dialog.dart';
import '../utils/time_format_util.dart'; // NEW util for parse/format
import '../utils/path_util.dart'; // NEW util for filename sanitization

// Restrictive but user-friendly time input filter
class TimeTextInputFormatter extends TextInputFormatter {
  final _valid = RegExp(r'^[0-9:.\s]*$');
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text.length > newValue.text.length) {
      return newValue; // allow deletes
    }
    if (!_valid.hasMatch(newValue.text)) return oldValue;
    return newValue;
  }
}

class AudioExtractorView extends StatefulWidget {
  const AudioExtractorView({super.key});

  @override
  State<AudioExtractorView> createState() => _AudioExtractorViewState();
}

class _AudioExtractorViewState extends State<AudioExtractorView> {
  late final ScrollController _segmentsScrollController;

  @override
  void initState() {
    super.initState();
    _segmentsScrollController = ScrollController();
  }

  @override
  void dispose() {
    _segmentsScrollController.dispose();
    super.dispose();
  }

  Future<void> _pickMP3File({
    required BuildContext context,
    required AudioExtractorVM audioExtractorVM,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp3'],
      );
      if (result == null || result.files.single.path == null) return;

      final String path = result.files.single.path!;
      final String name = result.files.single.name;

      final double duration = await AudioExtractorService.getAudioDuration(
        filePath: path,
      );

      audioExtractorVM.setAudioFile(path: path, name: name, duration: duration);
    } catch (e) {
      audioExtractorVM.setError('Error selecting file: $e');
    }
  }

  Future<void> _loadSegmentsFromCommentFile({
    required BuildContext context,
    required AudioExtractorVM audioExtractorVM,
  }) async {
    try {
      if (audioExtractorVM.audioFile.path == null) {
        audioExtractorVM.setError('Please select an MP3 file first');
        return;
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (result == null || result.files.single.path == null) return;

      final String jsonPath = result.files.single.path!;
      final List<Comment> comments = JsonDataService.loadListFromFile<Comment>(
        jsonPathFileName: jsonPath,
        type: Comment,
      );

      if (comments.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No comments found in the selected file'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      int commentCount = comments.length;
      int added = 0, skipped = 0;
      for (final c in comments) {
        // Convert tenth-of-seconds → seconds
        final double start = c.commentStartPositionInTenthOfSeconds / 10.0;
        final double end = c.commentEndPositionInTenthOfSeconds / 10.0;

        if (start >= 0 &&
            end > start &&
            audioExtractorVM.audioFile.duration > 0 &&
            end <= audioExtractorVM.audioFile.duration) {
          if (added < commentCount - 1) {
            audioExtractorVM.addSegment(
              AudioSegment(
                startPosition: start,
                endPosition: end,
                silenceDuration: kDefaultSilenceDuration,
              ),
            );
          } else {
            // For the last comment, no silence added
            audioExtractorVM.addSegment(
              AudioSegment(
                startPosition: start,
                endPosition: end,
                silenceDuration: 0.0,
              ),
            );
          }
          added++;
        } else {
          skipped++;
        }
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Loaded $added segment(s)${skipped > 0 ? ' ($skipped skipped)' : ''}',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      audioExtractorVM.setError('Error loading comment file: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading comment file: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _extractMP3({required BuildContext context}) async {
    final audioExtractorVM = context.read<AudioExtractorVM>();
    final audioPlayerVM = context.read<AudioPlayerVM>();

    if (audioExtractorVM.audioFile.path == null) {
      audioExtractorVM.setError('Please select an MP3 file first');
      return;
    }
    if (audioExtractorVM.segments.isEmpty) {
      audioExtractorVM.setError('Please add at least one segment');
      return;
    }

    try {
      // Release file locks on Windows if player loaded
      if (Platform.isWindows && audioPlayerVM.isLoaded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preparing extraction...'),
            duration: Duration(seconds: 1),
          ),
        );
        await audioPlayerVM.releaseCurrentFile();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final String base =
          (audioExtractorVM.audioFile.name ?? 'extract').split('.').first;

      String suggested =
          (audioExtractorVM.segments.length == 1)
              ? '$base from ${TimeFormatUtil.formatSeconds(audioExtractorVM.segments[0].startPosition)} '
                  'to ${TimeFormatUtil.formatSeconds(audioExtractorVM.segments[0].endPosition)}.mp3'
              : '${base}_${audioExtractorVM.segments.length}_segments.mp3';

      suggested = PathUtil.sanitizeFileName(suggested);

      final String? dir = await FilePicker.platform.getDirectoryPath();
      if (dir == null) {
        audioExtractorVM.setError('Save location selection canceled');
        return;
      }

      final String outputPath = '$dir${Platform.pathSeparator}$suggested';
      await audioExtractorVM.extractMP3(outputPath);
    } catch (e) {
      audioExtractorVM.setError('Error selecting save location: $e');
    }
  }

  Future<void> _playExtractedFile(BuildContext context, String filePath) async {
    final audioPlayerVM = context.read<AudioPlayerVM>();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    try {
      await audioPlayerVM.loadFile(filePath: filePath);
      if (!audioPlayerVM.hasError) {
        await audioPlayerVM.togglePlay();
      } else {
        if (!context.mounted) return;
        _showErrorSnackBar(context, audioPlayerVM.errorMessage);
      }
    } catch (e) {
      if (!context.mounted) return;
      _showErrorSnackBar(context, 'Error playing file: $e');
    }
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Repair',
          textColor: Colors.white,
          onPressed: () async {
            final audioPlayerVM = Provider.of<AudioPlayerVM>(
              context,
              listen: false,
            );
            await audioPlayerVM.tryRepairPlayer();
          },
        ),
      ),
    );
  }

  Future<void> _showAddSegmentDialog(
    BuildContext context,
    AudioExtractorVM vm,
  ) async {
    final segment = await showDialog<AudioSegment>(
      context: context,
      builder: (_) => AddSegmentDialog(maxDuration: vm.audioFile.duration),
    );
    if (segment != null) vm.addSegment(segment);
  }

  Future<void> _showEditSegmentDialog(
    BuildContext context,
    AudioExtractorVM vm,
    int index,
    AudioSegment segment,
  ) async {
    final updated = await showDialog<AudioSegment>(
      context: context,
      builder:
          (_) => AddSegmentDialog(
            maxDuration: vm.audioFile.duration,
            existingSegment: segment,
          ),
    );
    if (updated != null) vm.updateSegment(index, updated);
  }

  void _confirmDeleteSegment(
    BuildContext context,
    AudioExtractorVM vm,
    int index,
  ) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Delete Segment'),
            content: const Text(
              'Are you sure you want to delete this segment?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  vm.removeSegment(index);
                  Navigator.of(context).pop();
                },
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }

  void _confirmClearSegments(BuildContext context, AudioExtractorVM vm) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Clear All Segments'),
            content: const Text('Are you sure you want to clear all segments?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  vm.clearSegments();
                  Navigator.of(context).pop();
                },
                child: const Text('Clear All'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MP3 Extractor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettingsDialog(context: context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Consumer2<AudioExtractorVM, AudioPlayerVM>(
          builder: (context, vm, player, _) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    onPressed:
                        () => _pickMP3File(
                          context: context,
                          audioExtractorVM: vm,
                        ),
                    child: const Text('Select MP3 File'),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Segments (${vm.segmentCount})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Column(
                        children: [
                          ElevatedButton.icon(
                            onPressed:
                                vm.audioFile.path == null
                                    ? null
                                    : () => _loadSegmentsFromCommentFile(
                                      context: context,
                                      audioExtractorVM: vm,
                                    ),
                            icon: const Icon(Icons.file_open, size: 18),
                            label: const Text('Load from Comments'),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed:
                                vm.audioFile.path == null
                                    ? null
                                    : () => _showAddSegmentDialog(context, vm),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Manually'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (vm.segments.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Text(
                          'No segments added yet.\nLoad from a comment file or add segments manually.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    Container(
                      constraints: const BoxConstraints(maxHeight: 240),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Scrollbar(
                        controller: _segmentsScrollController, // <-- important
                        thumbVisibility: true, // optionnel, utile sur desktop
                        child: ListView.builder(
                          controller:
                              _segmentsScrollController, // <-- important
                          primary:
                              false, // <-- car imbriqué dans SingleChildScrollView
                          shrinkWrap:
                              true, // <-- pour éviter contraintes infinies                       thumbVisibility: true,
                          itemCount: vm.segments.length,
                          itemBuilder: (context, index) {
                            final s = vm.segments[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text('${index + 1}'),
                                ),
                                title: Text(
                                  '${TimeFormatUtil.formatSeconds(s.startPosition)} → '
                                  '${TimeFormatUtil.formatSeconds(s.endPosition)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  'Duration: ${TimeFormatUtil.formatSeconds(s.duration)}'
                                  '${s.silenceDuration > 0 ? ' + ${TimeFormatUtil.formatSeconds(s.silenceDuration)} silence' : ''}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 20),
                                      onPressed:
                                          () => _showEditSegmentDialog(
                                            context,
                                            vm,
                                            index,
                                            s,
                                          ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        size: 20,
                                        color: Colors.red,
                                      ),
                                      onPressed:
                                          () => _confirmDeleteSegment(
                                            context,
                                            vm,
                                            index,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                  if (vm.segments.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total: ${TimeFormatUtil.formatSeconds(vm.totalDuration)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextButton.icon(
                          onPressed: () => _confirmClearSegments(context, vm),
                          icon: const Icon(Icons.clear_all, size: 18),
                          label: const Text('Clear All'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed:
                        vm.extractionResult.isProcessing || vm.segments.isEmpty
                            ? null
                            : () => _extractMP3(context: context),
                    child: const Text('Extract MP3'),
                  ),

                  const SizedBox(height: 16),
                  if (vm.extractionResult.isProcessing)
                    const Center(child: CircularProgressIndicator()),

                  if (vm.extractionResult.hasMessage)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Text(
                        vm.extractionResult.message,
                        style: TextStyle(
                          color:
                              vm.extractionResult.isError
                                  ? Colors.red
                                  : vm.extractionResult.isSuccess
                                  ? Colors.green[700]
                                  : Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                  if (vm.extractionResult.isSuccess &&
                      vm.extractionResult.outputPath != null) ...[
                    const Divider(height: 32),
                    const Text(
                      'Audio Player',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildAudioPlayerControls(
                      context: context,
                      audioExtractorVM: vm,
                      audioPlayerVM: player,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAudioPlayerControls({
    required BuildContext context,
    required AudioExtractorVM audioExtractorVM,
    required AudioPlayerVM audioPlayerVM,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed:
                  audioPlayerVM.hasError
                      ? () => audioPlayerVM.tryRepairPlayer()
                      : audioPlayerVM.isLoaded
                      ? () => audioPlayerVM.togglePlay()
                      : () => _playExtractedFile(
                        context,
                        audioExtractorVM.extractionResult.outputPath!,
                      ),
              icon: Icon(
                audioPlayerVM.hasError
                    ? Icons.refresh
                    : audioPlayerVM.isPlaying
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
              label: Text(
                audioPlayerVM.hasError
                    ? 'Retry'
                    : audioPlayerVM.isPlaying
                    ? 'Pause'
                    : 'Play',
              ),
            ),
          ],
        ),
        if (audioPlayerVM.isLoaded && !audioPlayerVM.hasError) ...[
          const SizedBox(height: 8),
          SliderTheme(
            data: const SliderThemeData(
              trackHeight: 4,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: audioPlayerVM.progressPercent.clamp(0.0, 1.0),
              onChanged:
                  (value) => audioPlayerVM.seekByPercentage(percentage: value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(TimeFormatUtil.formatDuration(audioPlayerVM.position)),
                Text(TimeFormatUtil.formatDuration(audioPlayerVM.duration)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Playing: ${PathUtil.fileName(audioExtractorVM.extractionResult.outputPath!)}',
            style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
        if (audioPlayerVM.hasError)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              audioPlayerVM.errorMessage,
              style: const TextStyle(color: Colors.red, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  void _showSettingsDialog({required BuildContext context}) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text('MP3 Extractor $kApplicationVersion'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer'),
              ),
            ],
          ),
    );
  }
}
