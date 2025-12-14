// lib/views/audio_extractor_view.dart
import 'dart:io';

import 'package:flutter/material.dart';
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
import '../utils/time_format_util.dart';
import '../utils/path_util.dart';

class AudioExtractorView extends StatefulWidget {
  const AudioExtractorView({super.key});

  @override
  State<AudioExtractorView> createState() =>
      _AudioExtractorViewState();
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

  // ────────────────────────────────────────────────────────────────────────────
  // File picking helpers
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _pickMP3File({
    required BuildContext context,
    required AudioExtractorVM audioExtractorVM,
  }) async {
    try {
      final FilePickerResult? filePickerSelection = await FilePicker
          .platform
          .pickFiles(
            type: FileType.custom,
            allowedExtensions: const ['mp3'],
          );

      if (filePickerSelection == null ||
          filePickerSelection.files.single.path == null) {
        return;
      }

      final String path = filePickerSelection.files.single.path!;
      final String name = filePickerSelection.files.single.name;

      final double duration =
          await AudioExtractorService.getAudioDuration(
            filePath: path,
          );

      audioExtractorVM.setAudioFile(
        path: path,
        name: name,
        duration: duration,
      );
    } catch (e) {
      audioExtractorVM.setError('Error selecting file: $e');
    }
  }

  Future<void> _loadSegmentsFromCommentFile({
    required BuildContext context,
    required AudioExtractorVM audioExtractorVM,
  }) async {
    try {
      final FilePickerResult? filePickerResultFilePickerSelection =
          await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: const ['json'],
          );

      if (filePickerResultFilePickerSelection == null ||
          filePickerResultFilePickerSelection.files.single.path ==
              null) {
        return;
      }

      final String jsonPath =
          filePickerResultFilePickerSelection.files.single.path!;
      final List<Comment> comments =
          JsonDataService.loadListFromFile<Comment>(
            jsonPathFileName: jsonPath,
            type: Comment,
          );

      if (comments.isEmpty) {
        if (!context.mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No comments found in the selected file'),
            backgroundColor: Colors.orange,
          ),
        );

        return;
      }

      int added = 0;
      int skipped = 0;

      for (int i = 0; i < comments.length; i++) {
        final Comment comment = comments[i];
        final double start =
            comment.commentStartPositionInTenthOfSeconds / 10.0;
        final double end =
            comment.commentEndPositionInTenthOfSeconds / 10.0;

        if (start >= 0 &&
            end > start &&
            audioExtractorVM.audioFile.duration > 0 &&
            end <= audioExtractorVM.audioFile.duration) {
          final silence =
              (i < comments.length - 1)
                  ? kDefaultSilenceDuration
                  : 0.0;
          audioExtractorVM.addSegment(
            AudioSegment(
              startPosition: start,
              endPosition: end,
              silenceDuration: silence,
              title: comment.title,
            ),
          );
          added++;
        } else {
          skipped++;
        }
      }

      if (!context.mounted) {
        return;
      }

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
    final AudioExtractorVM audioExtractorVM =
        context.read<AudioExtractorVM>();
    final AudioPlayerVM audioPlayerVM = context.read<AudioPlayerVM>();

    if (audioExtractorVM.multiInputs.isEmpty) {
      if (audioExtractorVM.audioFile.path == null) {
        audioExtractorVM.setError('Please select an MP3 file first');

        return;
      }

      if (audioExtractorVM.segments.isEmpty) {
        audioExtractorVM.setError('Please add at least one segment');

        return;
      }
    }

    try {
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

      final String base = PathUtil.removeExtension(
        audioExtractorVM.audioFile.name ?? 'extract',
      );

      String extractedMp3FileName;

      if (audioExtractorVM.multiInputs.isNotEmpty) {
        final totalSegs = audioExtractorVM.multiInputs.fold<int>(
          0,
          (n, i) => n + i.segments.length,
        );
        extractedMp3FileName =
            '${base}_multi_${totalSegs}_segments.mp3';
      } else if (audioExtractorVM.segments.length == 1) {
        extractedMp3FileName =
            '$base from ${TimeFormatUtil.formatSeconds(audioExtractorVM.segments[0].startPosition)} '
            'to ${TimeFormatUtil.formatSeconds(audioExtractorVM.segments[0].endPosition)}.mp3';
      } else {
        extractedMp3FileName =
            '${base}_${audioExtractorVM.segments.length}_segments.mp3';
      }

      extractedMp3FileName = PathUtil.sanitizeFileName(
        extractedMp3FileName,
      );

      final String? extractedMp3DestinationDir =
          await FilePicker.platform.getDirectoryPath();
      if (extractedMp3DestinationDir == null) {
        audioExtractorVM.setError('Save location selection canceled');

        return;
      }

      final String outputPath =
          '$extractedMp3DestinationDir${Platform.pathSeparator}$extractedMp3FileName';

      if (audioExtractorVM.multiInputs.isNotEmpty) {
        await audioExtractorVM.extractMP3Multi(outputPath);
      } else {
        await audioExtractorVM.extractMP3(outputPath);
      }
    } catch (e) {
      audioExtractorVM.setError('Error selecting save location: $e');
    }
  }

  Future<void> _playExtractedFile(
    BuildContext context,
    String filePath,
  ) async {
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

  // ────────────────────────────────────────────────────────────────────────────
  // Multi-input UI helpers
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _addSource(BuildContext context) async {
    final vm = context.read<AudioExtractorVM>();
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp3'],
      );
      if (res == null || res.files.single.path == null) return;

      final inputPath = res.files.single.path!;
      vm.addMultiInput(
        inputPath: inputPath,
        segments: const [],
        gainDb: 0.0,
      );
    } catch (e) {
      vm.setError('Error selecting source: $e');
    }
  }

  Future<void> _loadAndPickCommentsForSource(
    BuildContext context,
    int index,
  ) async {
    final vm = context.read<AudioExtractorVM>();
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (res == null || res.files.single.path == null) return;

      final jsonPath = res.files.single.path!;
      final comments = JsonDataService.loadListFromFile<Comment>(
        jsonPathFileName: jsonPath,
        type: Comment,
      );
      if (comments.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No comments found'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final picked = await showDialog<List<Comment>>(
        context: context,
        builder:
            (_) => _MultiSelectCommentsDialog(comments: comments),
      );
      if (picked == null || picked.isEmpty) return;

      final segments = <AudioSegment>[];
      for (int i = 0; i < picked.length; i++) {
        final c = picked[i];
        final start = c.commentStartPositionInTenthOfSeconds / 10.0;
        final end = c.commentEndPositionInTenthOfSeconds / 10.0;
        if (end > start) {
          final isLast = (i == picked.length - 1);
          segments.add(
            AudioSegment(
              startPosition: start,
              endPosition: end,
              silenceDuration: isLast ? 0.0 : kDefaultSilenceDuration,
              title: c.title,
            ),
          );
        }
      }
      vm.updateMultiInputSegments(index, segments);
    } catch (e) {
      vm.setError('Error picking comments: $e');
    }
  }

  // ────────────────────────────────────────────────────────────────────────────

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
          builder: (context, audioExtractorVM, audioPlayerVM, _) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Multi-sources section ───────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Sources (multi-files)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _addSource(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add MP3 file'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Consumer<AudioExtractorVM>(
                    builder: (context, vm, _) {
                      if (vm.multiInputs.isEmpty) {
                        return const Text(
                          'No extra sources. Use “Add MP3 Source” and adjust per-source volume if needed.\n'
                          'If you keep only one source (or none here), the single-file section below stays active.',
                          style: TextStyle(color: Colors.grey),
                        );
                      }
                      return Column(
                        children: [
                          for (
                            int i = 0;
                            i < vm.multiInputs.length;
                            i++
                          )
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: _SourceRow(
                                  index: i,
                                  input: vm.multiInputs[i],
                                  totalSegments:
                                      vm
                                          .multiInputs[i]
                                          .segments
                                          .length,
                                  onRemove:
                                      () => vm.removeMultiInput(i),
                                  onLoadComments:
                                      () =>
                                          _loadAndPickCommentsForSource(
                                            context,
                                            i,
                                          ),
                                  onGainChanged:
                                      (gainDb) =>
                                          vm.updateMultiInputGain(
                                            i,
                                            gainDb,
                                          ),
                                ),
                              ),
                            ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'Total (multi): ${TimeFormatUtil.formatSeconds(vm.totalDurationMulti)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Divider(height: 24),
                        ],
                      );
                    },
                  ),

                  // ── Single-file section (unchanged) ────────────────────────
                  ElevatedButton(
                    onPressed:
                        () => _pickMP3File(
                          context: context,
                          audioExtractorVM: audioExtractorVM,
                        ),
                    child: const Text('Select MP3 file'),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Segments (${audioExtractorVM.segmentCount})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Column(
                        children: [
                          ElevatedButton.icon(
                            onPressed:
                                audioExtractorVM.audioFile.path ==
                                        null
                                    ? null
                                    : () =>
                                        _loadSegmentsFromCommentFile(
                                          context: context,
                                          audioExtractorVM:
                                              audioExtractorVM,
                                        ),
                            icon: const Icon(
                              Icons.file_open,
                              size: 18,
                            ),
                            label: const Text('Load from comments'),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed:
                                audioExtractorVM.audioFile.path ==
                                        null
                                    ? null
                                    : () async {
                                      // After pressing 'Add manually' text button
                                      final segment =
                                          await showDialog<
                                            AudioSegment
                                          >(
                                            context: context,
                                            builder:
                                                (
                                                  _,
                                                ) => AddSegmentDialog(
                                                  maxDuration:
                                                      audioExtractorVM
                                                          .audioFile
                                                          .duration,
                                                ),
                                          );
                                      if (segment != null) {
                                        audioExtractorVM.addSegment(
                                          segment,
                                        );
                                      }
                                    },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add manually'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  (audioExtractorVM.segments.isEmpty)
                      ? Container(
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
                      : Container(
                        constraints: const BoxConstraints(
                          maxHeight: 240,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Scrollbar(
                          controller: _segmentsScrollController,
                          thumbVisibility: true,
                          child: ListView.builder(
                            controller: _segmentsScrollController,
                            primary: false,
                            shrinkWrap: true,
                            itemCount:
                                audioExtractorVM.segments.length,
                            itemBuilder: (context, index) {
                              final s =
                                  audioExtractorVM.segments[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    child: Text('${index + 1}'),
                                  ),
                                  title: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.title,
                                        maxLines: 4,
                                        overflow:
                                            TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${TimeFormatUtil.formatSeconds(s.startPosition)} → '
                                        '${TimeFormatUtil.formatSeconds(s.endPosition)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    'Duration: ${TimeFormatUtil.formatSeconds(s.duration)}'
                                    '${s.silenceDuration > 0 ? ' + ${TimeFormatUtil.formatSeconds(s.silenceDuration)} silence' : ''}',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.edit,
                                          size: 20,
                                        ),
                                        onPressed: () async {
                                          // After pressing 'Edit' icon button
                                          final updated = await showDialog<
                                            AudioSegment
                                          >(
                                            context: context,
                                            builder:
                                                (
                                                  _,
                                                ) => AddSegmentDialog(
                                                  maxDuration:
                                                      audioExtractorVM
                                                          .audioFile
                                                          .duration,
                                                  existingSegment: s,
                                                ),
                                          );
                                          if (updated != null) {
                                            audioExtractorVM
                                                .updateSegment(
                                                  index,
                                                  updated,
                                                );
                                          }
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          size: 20,
                                          color: Colors.red,
                                        ),
                                        onPressed:
                                            () =>
                                                _confirmDeleteSegment(
                                                  context,
                                                  audioExtractorVM,
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

                  if (audioExtractorVM.segments.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total: ${TimeFormatUtil.formatSeconds(audioExtractorVM.totalDuration)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed:
                              () => _confirmClearSegments(
                                context,
                                audioExtractorVM,
                              ),
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
                        audioExtractorVM.extractionResult.isProcessing
                            ? null
                            : () => _extractMP3(context: context),
                    child: const Text('Extract MP3'),
                  ),

                  const SizedBox(height: 16),
                  if (audioExtractorVM.extractionResult.isProcessing)
                    const Center(child: CircularProgressIndicator()),

                  if (audioExtractorVM.extractionResult.hasMessage)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Text(
                        audioExtractorVM.extractionResult.message,
                        style: TextStyle(
                          color:
                              audioExtractorVM
                                      .extractionResult
                                      .isError
                                  ? Colors.red
                                  : audioExtractorVM
                                      .extractionResult
                                      .isSuccess
                                  ? Colors.green[700]
                                  : Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                  if (audioExtractorVM.extractionResult.isSuccess &&
                      audioExtractorVM.extractionResult.outputPath !=
                          null) ...[
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
                      audioExtractorVM: audioExtractorVM,
                      audioPlayerVM: audioPlayerVM,
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
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: 8,
              ),
            ),
            child: Slider(
              value: audioPlayerVM.progressPercent.clamp(0.0, 1.0),
              onChanged:
                  (value) => audioPlayerVM.seekByPercentage(
                    percentage: value,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  TimeFormatUtil.formatDuration(
                    audioPlayerVM.position,
                  ),
                ),
                Text(
                  TimeFormatUtil.formatDuration(
                    audioPlayerVM.duration,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Playing: ${PathUtil.fileName(audioExtractorVM.extractionResult.outputPath!)}',
            style: const TextStyle(
              fontStyle: FontStyle.italic,
              fontSize: 12,
            ),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
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

  void _confirmClearSegments(
    BuildContext context,
    AudioExtractorVM vm,
  ) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Clear All Segments'),
            content: const Text(
              'Are you sure you want to clear all segments?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
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

  void _showSettingsDialog({required BuildContext context}) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('MP3 Extractor $kApplicationVersion'),
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

// ── Small row widget for a multi-input item (with per-input gain) ────────────
class _SourceRow extends StatelessWidget {
  final int index;
  final VoidCallback onRemove;
  final VoidCallback onLoadComments;
  final InputSegments input;
  final int totalSegments;
  final ValueChanged<double> onGainChanged;

  const _SourceRow({
    required this.index,
    required this.onRemove,
    required this.onLoadComments,
    required this.input,
    required this.totalSegments,
    required this.onGainChanged,
  });

  @override
  Widget build(BuildContext context) {
    final gainDb = input.gainDb.clamp(-12.0, 12.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                PathUtil.fileName(input.inputPath),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: onLoadComments,
              icon: const Icon(Icons.file_open),
              label: const Text('Load & pick comments'),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: onRemove,
            ),
          ],
        ),
        Row(
          children: [
            Text('Segments: $totalSegments'),
            const SizedBox(width: 16),
            Text('Gain: ${gainDb.toStringAsFixed(1)} dB'),
          ],
        ),
        // Per-input gain slider: -12 dB .. +12 dB
        Slider(
          value: gainDb,
          min: -12.0,
          max: 12.0,
          divisions: 48, // 0.5 dB steps
          label: '${gainDb.toStringAsFixed(1)} dB',
          onChanged:
              (v) =>
                  onGainChanged(double.parse(v.toStringAsFixed(1))),
        ),
      ],
    );
  }
}

// ── Dialog to pick a subset of comments (unchanged) ──────────────────────────
class _MultiSelectCommentsDialog extends StatefulWidget {
  final List<Comment> comments;
  const _MultiSelectCommentsDialog({required this.comments});

  @override
  State<_MultiSelectCommentsDialog> createState() =>
      _MultiSelectCommentsDialogState();
}

class _MultiSelectCommentsDialogState
    extends State<_MultiSelectCommentsDialog> {
  late final List<bool> _checked;

  @override
  void initState() {
    super.initState();
    _checked = List<bool>.filled(
      widget.comments.length,
      true,
    ); // all checked by default
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select comments'),
      content: SizedBox(
        width: 420,
        height: 360,
        child: ListView.builder(
          itemCount: widget.comments.length,
          itemBuilder: (_, i) {
            final c = widget.comments[i];
            final start =
                (c.commentStartPositionInTenthOfSeconds / 10.0);
            final end = (c.commentEndPositionInTenthOfSeconds / 10.0);
            return CheckboxListTile(
              value: _checked[i],
              onChanged:
                  (v) => setState(() => _checked[i] = v ?? false),
              title: Text(
                c.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${TimeFormatUtil.formatSeconds(start)} → ${TimeFormatUtil.formatSeconds(end)}',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final picked = <Comment>[];
            for (int i = 0; i < widget.comments.length; i++) {
              if (_checked[i]) picked.add(widget.comments[i]);
            }
            Navigator.pop(context, picked);
          },
          child: const Text('Use selected'),
        ),
      ],
    );
  }
}
