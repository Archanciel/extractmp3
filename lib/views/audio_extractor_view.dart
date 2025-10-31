import 'dart:io';
import 'package:extractmp3/services/audio_extractor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../models/audio_segment.dart';
import '../models/comment.dart';
import '../services/json_data_service.dart';
import '../constants.dart';
import '../viewmodels/audio_extractor_vm.dart';
import '../viewmodels/audio_player_vm.dart';
import 'widgets/add_segment_dialog.dart';

// Custom text formatter for time input
class TimeTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Allow deleting characters
    if (oldValue.text.length > newValue.text.length) {
      return newValue;
    }

    // Simple validation - allow digits, colons, and dots
    final RegExp validChars = RegExp(r'[0-9:.]');
    String filtered = newValue.text
        .split('')
        .where((char) => validChars.hasMatch(char))
        .join('');

    // If text was invalid, reject the change
    if (filtered != newValue.text) {
      return oldValue;
    }

    return newValue;
  }
}

class AudioExtractorView extends StatefulWidget {
  const AudioExtractorView({super.key});

  @override
  State<AudioExtractorView> createState() => _AudioExtractorViewState();
}

class _AudioExtractorViewState extends State<AudioExtractorView> {
  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _pickMP3File({
    required BuildContext context,
    required AudioExtractorVM audioExtractorVM,
  }) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3'],
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final name = result.files.single.name;

        double duration = await AudioExtractorService.getAudioDuration(
          filePath: path,
        );

        // Then set the audio file
        audioExtractorVM.setAudioFile(
          path: path,
          name: name,
          duration: duration,
        );
      }
    } catch (e) {
      audioExtractorVM.setError('Error selecting file: $e');
    }
  }

  /// NEW METHOD: Load segments from a comment JSON file
  Future<void> _loadSegmentsFromCommentFile({
    required BuildContext context,
    required AudioExtractorVM audioExtractorVM,
  }) async {
    try {
      // Check if an audio file is loaded first
      if (audioExtractorVM.audioFile.path == null) {
        audioExtractorVM.setError('Please select an MP3 file first');
        return;
      }

      // Pick a JSON file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final commentFilePath = result.files.single.path!;

        // Load comments from the file
        List<Comment> comments = JsonDataService.loadListFromFile<Comment>(
          jsonPathFileName: commentFilePath,
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

        // Convert comments to segments
        int segmentsAdded = 0;
        int segmentsSkipped = 0;

        for (Comment comment in comments) {
          // Convert tenths of seconds to seconds
          double startPosition = comment.commentStartPositionInTenthOfSeconds / 10.0;
          double endPosition = comment.commentEndPositionInTenthOfSeconds / 10.0;

          // Validate positions
          if (startPosition >= 0 && 
              endPosition > startPosition && 
              endPosition <= audioExtractorVM.audioFile.duration) {
            
            AudioSegment segment = AudioSegment(
              startPosition: startPosition,
              endPosition: endPosition,
              silenceDuration: 0.0, // User can edit this later
            );

            audioExtractorVM.addSegment(segment);
            segmentsAdded++;
          } else {
            segmentsSkipped++;
            debugPrint(
              'Skipped comment "${comment.title}": Invalid positions '
              '($startPosition - $endPosition)',
            );
          }
        }

        // Show feedback to user
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Loaded $segmentsAdded segment(s) from comments'
              '${segmentsSkipped > 0 ? ' ($segmentsSkipped skipped due to invalid positions)' : ''}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
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
    final audioExtractorVM = Provider.of<AudioExtractorVM>(
      context,
      listen: false,
    );
    
    final audioPlayerVM = Provider.of<AudioPlayerVM>(
      context,
      listen: false,
    );

    if (audioExtractorVM.audioFile.path == null) {
      audioExtractorVM.setError('Please select an MP3 file first');
      return;
    }

    if (audioExtractorVM.segments.isEmpty) {
      audioExtractorVM.setError('Please add at least one segment');
      return;
    }

    try {
      // ========== CRITICAL FIX FOR WINDOWS FILE LOCKING ==========
      // Release any file locks BEFORE extraction to prevent "Permission denied"
      if (Platform.isWindows && audioPlayerVM.isLoaded) {
        debugPrint('🔓 Releasing audio player file locks before extraction...');
        
        // Show user feedback
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preparing extraction...'),
            duration: Duration(seconds: 1),
          ),
        );
        
        // Release the file
        await audioPlayerVM.releaseCurrentFile();
        
        // Give Windows extra time to fully release file handles
        await Future.delayed(const Duration(milliseconds: 500));
        
        debugPrint('✅ File locks released');
      }
      // ===========================================================

      // Create suggested filename
      final String baseFileName =
          audioExtractorVM.audioFile.name?.split('.').first ?? 'extract';

      final String suggestedFileName =
          audioExtractorVM.segments.length == 1
              ? '$baseFileName from ${_formatTimePosition(seconds: audioExtractorVM.segments[0].startPosition)} to ${_formatTimePosition(seconds: audioExtractorVM.segments[0].endPosition)}.mp3'
                  .replaceAll(':', '-')
              : '${baseFileName}_${audioExtractorVM.segments.length}_segments.mp3';

      // Show file picker to choose save location
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory == null) {
        audioExtractorVM.setError('Save location selection canceled');
        return;
      }

      final String outputPath =
          '$selectedDirectory${Platform.pathSeparator}$suggestedFileName';

      await audioExtractorVM.extractMP3(outputPath);
    } catch (e) {
      audioExtractorVM.setError('Error selecting save location: $e');
    }
  }

  // Function to parse formatted time input and convert to seconds
  double parseTimeInput(String input) {
    // Handle empty input
    if (input.isEmpty) {
      return 0.0;
    }

    // If the input is already a decimal number (no colons), try to parse it directly
    if (!input.contains(':')) {
      return double.tryParse(input) ?? 0.0;
    }

    try {
      double totalSeconds = 0.0;

      // Split by decimal point to handle tenths of seconds
      List<String> mainAndFraction = input.split('.');
      String mainPart = mainAndFraction[0];
      double fractionPart = 0.0;

      // Parse the fractional part if it exists
      if (mainAndFraction.length > 1 && mainAndFraction[1].isNotEmpty) {
        // Handle case where user might input something like ".5"
        fractionPart = double.tryParse('0.${mainAndFraction[1]}') ?? 0.0;
      }

      // Split the main part by colon to get hours, minutes, seconds
      List<String> parts = mainPart.split(':');

      if (parts.length == 3) {
        // Format: hours:minutes:seconds
        int hours = int.tryParse(parts[0]) ?? 0;
        int minutes = int.tryParse(parts[1]) ?? 0;
        int seconds = int.tryParse(parts[2]) ?? 0;

        totalSeconds = (hours * 3600) + (minutes * 60) + seconds + fractionPart;
      } else if (parts.length == 2) {
        // Format: minutes:seconds
        int minutes = int.tryParse(parts[0]) ?? 0;
        int seconds = int.tryParse(parts[1]) ?? 0;

        totalSeconds = (minutes * 60) + seconds + fractionPart;
      } else if (parts.length == 1) {
        // Just seconds
        int seconds = int.tryParse(parts[0]) ?? 0;
        totalSeconds = seconds + fractionPart;
      }

      return totalSeconds;
    } catch (e) {
      // Return 0 if there's any parsing error
      return 0.0;
    }
  }

  // Load and play extracted MP3 with error handling
  Future<void> _playExtractedFile(BuildContext context, String filePath) async {
    final audioPlayerVM = Provider.of<AudioPlayerVM>(context, listen: false);

    // Reset any previous errors
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
          onPressed: () {
            final audioPlayerVM = Provider.of<AudioPlayerVM>(
              context,
              listen: false,
            );
            audioPlayerVM.tryRepairPlayer();
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
      builder:
          (context) => AddSegmentDialog(maxDuration: vm.audioFile.duration),
    );

    if (segment != null) {
      vm.addSegment(segment);
    }
  }

  Future<void> _showEditSegmentDialog(
    BuildContext context,
    AudioExtractorVM vm,
    int index,
    AudioSegment segment,
  ) async {
    final updatedSegment = await showDialog<AudioSegment>(
      context: context,
      builder:
          (context) => AddSegmentDialog(
            maxDuration: vm.audioFile.duration,
            existingSegment: segment,
          ),
    );

    if (updatedSegment != null) {
      vm.updateSegment(index, updatedSegment);
    }
  }

  void _confirmDeleteSegment(
    BuildContext context,
    AudioExtractorVM vm,
    int index,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
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
                onPressed: () {
                  vm.removeSegment(index);
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
          (context) => AlertDialog(
            title: const Text('Clear All Segments'),
            content: const Text('Are you sure you want to clear all segments?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  vm.clearSegments();
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () => _showSettingsDialog(context: context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Consumer2<AudioExtractorVM, AudioPlayerVM>(
          builder: (context, audioExtractorVM, audioPlayerVM, child) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    onPressed:
                        () => _pickMP3File(
                          context: context,
                          audioExtractorVM: audioExtractorVM,
                        ),
                    child: const Text('Select MP3 File'),
                  ),
                  const SizedBox(height: 16),
                  
                  // Segments section header with TWO buttons
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
                      // NEW: Two buttons side by side
                      Column(
                        children: [
                          // Load from Comment File button
                          ElevatedButton.icon(
                            onPressed: audioExtractorVM.audioFile.path == null
                                ? null
                                : () => _loadSegmentsFromCommentFile(
                                      context: context,
                                      audioExtractorVM: audioExtractorVM,
                                    ),
                            icon: const Icon(Icons.file_open, size: 18),
                            label: const Text('Load from Comments'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Manual Add Segment button
                          ElevatedButton.icon(
                            onPressed: audioExtractorVM.audioFile.path == null
                                ? null
                                : () => _showAddSegmentDialog(
                                      context,
                                      audioExtractorVM,
                                    ),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Manually'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
              
                  if (audioExtractorVM.segments.isEmpty)
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
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: audioExtractorVM.segments.length,
                        itemBuilder: (context, index) {
                          final segment = audioExtractorVM.segments[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: ListTile(
                              leading: CircleAvatar(child: Text('${index + 1}')),
                              title: Text(
                                '${_formatTimePosition(seconds: segment.startPosition)} → ${_formatTimePosition(seconds: segment.endPosition)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                'Duration: ${_formatTimePosition(seconds: segment.duration)}'
                                '${segment.silenceDuration > 0 ? ' + ${_formatTimePosition(seconds: segment.silenceDuration)} silence' : ''}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 20),
                                    onPressed:
                                        () => _showEditSegmentDialog(
                                          context,
                                          audioExtractorVM,
                                          index,
                                          segment,
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
              
                  if (audioExtractorVM.segments.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total: ${_formatTimePosition(seconds: audioExtractorVM.totalDuration)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
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
                        audioExtractorVM.extractionResult.isProcessing ||
                                audioExtractorVM.segments.isEmpty
                            ? null
                            : () {
                              _extractMP3(context: context);
                            },
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
                              audioExtractorVM.extractionResult.isError
                                  ? Colors.red
                                  : audioExtractorVM.extractionResult.isSuccess
                                  ? Colors.green[700]
                                  : Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
              
                  // Audio Player Section - Only visible when extraction is successful
                  if (audioExtractorVM.extractionResult.isSuccess &&
                      audioExtractorVM.extractionResult.outputPath != null) ...[
                    const Divider(height: 32),
                    const Text(
                      'Audio Player',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
              
                    // Show player UI
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

  // Separated audio player controls for better organization
  Widget _buildAudioPlayerControls({
    required BuildContext context,
    required AudioExtractorVM audioExtractorVM,
    required AudioPlayerVM audioPlayerVM,
  }) {
    return Column(
      children: [
        // Play/Pause Button
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

        // Player progress bar (only visible when file is loaded and no errors)
        if (audioPlayerVM.isLoaded && !audioPlayerVM.hasError) ...[
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: audioPlayerVM.progressPercent.clamp(0.0, 1.0),
              onChanged: (value) {
                audioPlayerVM.seekByPercentage(percentage: value);
              },
            ),
          ),

          // Time display with improved formatting
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDurationPosition(duration: audioPlayerVM.position)),
                Text(_formatDurationPosition(duration: audioPlayerVM.duration)),
              ],
            ),
          ),

          // File name display
          const SizedBox(height: 8),
          Text(
            'Playing: ${_getFileName(audioExtractorVM.extractionResult.outputPath!)}',
            style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],

        // Error message (if any)
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

  // Improved format function for displaying seconds as time
  String _formatTimePosition({required double seconds}) {
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int secs = seconds.toInt() % 60;
    final int tenthsOfSeconds = ((seconds - seconds.toInt()) * 10).round();

    // Format hours (only show if there are hours)
    String result = '';
    if (hours > 0) {
      result += '$hours:';
    }

    // Format minutes (if hours are shown, ensure minutes are padded with zeros)
    if (hours > 0) {
      result += '${minutes.toString().padLeft(2, '0')}:';
    } else {
      result += '$minutes:';
    }

    // Format seconds (always pad with zeros)
    result += secs.toString().padLeft(2, '0');

    // Add tenths of seconds
    result += '.${tenthsOfSeconds.toString()}';

    return result;
  }

  // Format a Duration object with the same style
  String _formatDurationPosition({required Duration duration}) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes % 60;
    final int seconds = duration.inSeconds % 60;
    final int milliseconds = duration.inMilliseconds % 1000;
    final int tenthsOfSeconds = (milliseconds / 100).round();

    // Format hours (only show if there are hours)
    String result = '';
    if (hours > 0) {
      result += '$hours:';
    }

    // Format minutes (if hours are shown, ensure minutes are padded with zeros)
    if (hours > 0) {
      result += '${minutes.toString().padLeft(2, '0')}:';
    } else {
      result += '$minutes:';
    }

    // Format seconds (always pad with zeros)
    result += seconds.toString().padLeft(2, '0');

    // Add tenths of seconds
    result += '.${tenthsOfSeconds.toString()}';

    return result;
  }

  String _getFileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  void _showSettingsDialog({required BuildContext context}) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('MP3 Extractor $kApplicationVersion'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Fermer'),
              ),
            ],
          ),
    );
  }
}