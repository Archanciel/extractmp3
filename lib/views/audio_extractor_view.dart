import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../constants.dart';
import '../viewmodels/audio_extractor_vm.dart';
import '../viewmodels/audio_player_vm.dart';

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
  // Controllers for the text fields - creating them once in the state
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();
  bool _startFieldInitialized = false;
  bool _endFieldInitialized = false;

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  Future<void> _pickMP3File(
    BuildContext context,
    AudioExtractorVM audioExtractorVM,
  ) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowedExtensions: ['mp3'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final name = result.files.single.name;

        // Get the actual duration using FFmpeg
        double duration = await _getMP3Duration(path);

        // Update the ViewModel with the file info and actual duration
        audioExtractorVM.setAudioFile(path, name, duration);

        // Reset initialized flags to update the text fields with new values
        setState(() {
          _startFieldInitialized = false;
          _endFieldInitialized = false;
        });
      }
    } catch (e) {
      audioExtractorVM.setError('Error selecting file: $e');
    }
  }

  Future<void> _extractMP3(BuildContext context) async {
    final audioExtractorVM = Provider.of<AudioExtractorVM>(
      context,
      listen: false,
    );

    if (audioExtractorVM.audioFile.path == null) {
      audioExtractorVM.setError('Please select an MP3 file first');
      return;
    }

    // Set processing state
    audioExtractorVM.startProcessing();

    try {
      // Create suggested filename with improved formatting
      final String baseFileName =
          audioExtractorVM.audioFile.name?.split('.').first ?? 'extract';

      // Format start and end positions for filename
      final String startFormatted = formatTimePosition(
        audioExtractorVM.startPosition,
      ).replaceAll(':', '-');
      final String endFormatted = formatTimePosition(
        audioExtractorVM.endPosition,
      ).replaceAll(':', '-');

      final String suggestedFileName =
          '$baseFileName from $startFormatted to $endFormatted.mp3';

      // Show file picker to choose save location
      String? outputPath;

      // For desktop platforms, use FilePicker to select save location
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory == null) {
        // User canceled the picker
        audioExtractorVM.setError('Save location selection canceled');
        return;
      }

      outputPath =
          '$selectedDirectory${Platform.pathSeparator}$suggestedFileName';

      await audioExtractorVM.extractMP3(outputPath);
    } catch (e) {
      audioExtractorVM.setError('Error selecting save location: $e');
    }
  }

  Future<double> _getMP3Duration(String filePath) async {
    try {
      // For Windows, use direct FFmpeg command
      final List<String> arguments = [
        '-i',
        filePath,
        '-v',
        'quiet',
        '-show_entries',
        'format=duration',
        '-of',
        'default=noprint_wrappers=1:nokey=1',
        '-sexagesimal',
      ];

      final ProcessResult result = await Process.run('ffprobe', arguments);
      if (result.exitCode == 0) {
        // Parse the duration string (HH:MM:SS.MS format)
        String durationStr = (result.stdout as String).trim();

        // Simple parsing for HH:MM:SS.MS format
        List<String> parts = durationStr.split(':');
        if (parts.length == 3) {
          int hours = int.parse(parts[0]);
          int minutes = int.parse(parts[1]);
          double seconds = double.parse(parts[2]);
          return (hours * 3600) + (minutes * 60) + seconds;
        }

        // Fallback - try direct parsing as seconds
        return double.tryParse(durationStr) ?? 60.0;
      }
      return 60.0; // Default fallback
    } catch (e) {
      debugPrint('Error getting duration: $e');
      return 60.0; // Default duration if we can't determine it
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

  // Safely update text controller with formatted time
  void _safeUpdateController(TextEditingController controller, String newText) {
    if (controller.text != newText) {
      final currentSelection = controller.selection;
      controller.text = newText;

      // Try to restore cursor position if possible
      if (currentSelection.start <= newText.length) {
        controller.selection = currentSelection;
      }
    }
  }

  // Process the input and update the view model
  void _processTimeInput(
    TextEditingController controller,
    bool isStart,
    AudioExtractorVM audioExtractorVM,
  ) {
    final newValueSeconds = parseTimeInput(controller.text);

    if (isStart) {
      // For start position
      if (newValueSeconds >= 0 &&
          newValueSeconds < audioExtractorVM.endPosition &&
          newValueSeconds <= audioExtractorVM.audioFile.duration) {
        audioExtractorVM.startPosition = newValueSeconds;
      }

      // Update the display with the model's value (which may have been validated)
      _safeUpdateController(
        controller,
        formatTimePosition(audioExtractorVM.startPosition),
      );
    } else {
      // For end position
      if (newValueSeconds > audioExtractorVM.startPosition &&
          newValueSeconds <= audioExtractorVM.audioFile.duration) {
        audioExtractorVM.endPosition = newValueSeconds;
      }

      // Update the display with the model's value (which may have been validated)
      _safeUpdateController(
        controller,
        formatTimePosition(audioExtractorVM.endPosition),
      );
    }
  }

  // Load and play extracted MP3 with error handling
  Future<void> _playExtractedFile(BuildContext context, String filePath) async {
    final audioPlayerVM = Provider.of<AudioPlayerVM>(context, listen: false);

    // Reset any previous errors
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    try {
      await audioPlayerVM.loadFile(filePath);
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
            onPressed: () => _showSettingsDialog(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Consumer2<AudioExtractorVM, AudioPlayerVM>(
          builder: (context, audioExtractorVM, audioPlayerVM, child) {
            // Initialize controllers with current values, but only once
            if (!_startFieldInitialized &&
                audioExtractorVM.audioFile.isSelected) {
              _startController.text = formatTimePosition(
                audioExtractorVM.startPosition,
              );
              _startFieldInitialized = true;
            }

            if (!_endFieldInitialized &&
                audioExtractorVM.audioFile.isSelected) {
              _endController.text = formatTimePosition(
                audioExtractorVM.endPosition,
              );
              _endFieldInitialized = true;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  onPressed: () => _pickMP3File(context, audioExtractorVM),
                  child: const Text('Select MP3 File'),
                ),
                const SizedBox(height: 16),
                if (audioExtractorVM.audioFile.isSelected) ...[
                  Text(
                    'Selected File: ${audioExtractorVM.audioFile.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Duration: ${formatTimePosition(audioExtractorVM.audioFile.duration)}',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 16),
                  // Start position input field
                  Row(
                    children: [
                      const Text('Start Position: '),
                      SizedBox(
                        width: 100,
                        child: Focus(
                          onFocusChange: (hasFocus) {
                            if (!hasFocus) {
                              // When focus is lost, parse the value and update the model
                              _processTimeInput(
                                _startController,
                                true,
                                audioExtractorVM,
                              );
                            }
                          },
                          child: TextField(
                            controller: _startController,
                            inputFormatters: [TimeTextInputFormatter()],
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: '0:00.0',
                              helperText: 'h:mm:ss.t',
                              helperStyle: TextStyle(fontSize: 9),
                            ),
                            // Add an onChanged handler to update the model immediately
                            onChanged: (value) {
                              // Don't reformat during typing, but do update the model
                              double newValueSeconds = parseTimeInput(value);
                              if (newValueSeconds >= 0 &&
                                  newValueSeconds <
                                      audioExtractorVM.endPosition &&
                                  newValueSeconds <=
                                      audioExtractorVM.audioFile.duration) {
                                audioExtractorVM.startPosition =
                                    newValueSeconds;
                              }
                            },
                            onSubmitted: (value) {
                              _processTimeInput(
                                _startController,
                                true,
                                audioExtractorVM,
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  // End position input field
                  Row(
                    children: [
                      const Text('End Position:   '),
                      SizedBox(
                        width: 100,
                        child: Focus(
                          onFocusChange: (hasFocus) {
                            if (!hasFocus) {
                              // When focus is lost, parse the value and update the model
                              _processTimeInput(
                                _endController,
                                false,
                                audioExtractorVM,
                              );
                            }
                          },
                          child: TextField(
                            controller: _endController,
                            inputFormatters: [TimeTextInputFormatter()],
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: '0:00.0',
                              helperText: 'h:mm:ss.t',
                              helperStyle: TextStyle(fontSize: 9),
                            ),
                            // Add an onChanged handler to update the model immediately
                            onChanged: (value) {
                              // Don't reformat during typing, but do update the model
                              double newValueSeconds = parseTimeInput(value);
                              if (newValueSeconds >
                                      audioExtractorVM.startPosition &&
                                  newValueSeconds <=
                                      audioExtractorVM.audioFile.duration) {
                                audioExtractorVM.endPosition = newValueSeconds;
                              }
                            },
                            onSubmitted: (value) {
                              _processTimeInput(
                                _endController,
                                false,
                                audioExtractorVM,
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed:
                        audioExtractorVM.extractionResult.isProcessing
                            ? null
                            : () {
                              audioPlayerVM.isLoaded = false;

                              // Parse the current text field values once more before extraction
                              final startSeconds = parseTimeInput(
                                _startController.text,
                              );
                              if (startSeconds >= 0 &&
                                  startSeconds < audioExtractorVM.endPosition &&
                                  startSeconds <=
                                      audioExtractorVM.audioFile.duration) {
                                audioExtractorVM.startPosition = startSeconds;
                              }

                              final endSeconds = parseTimeInput(
                                _endController.text,
                              );
                              if (endSeconds > audioExtractorVM.startPosition &&
                                  endSeconds <=
                                      audioExtractorVM.audioFile.duration) {
                                audioExtractorVM.endPosition = endSeconds;
                              }

                              _extractMP3(context);
                            },
                    child: const Text('Extract MP3'),
                  ),
                ],
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
                    context,
                    audioExtractorVM,
                    audioPlayerVM,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // Separated audio player controls for better organization
  Widget _buildAudioPlayerControls(
    BuildContext context,
    AudioExtractorVM audioExtractorVM,
    AudioPlayerVM audioPlayerVM,
  ) {
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
                audioPlayerVM.seekByPercentage(value);
              },
            ),
          ),

          // Time display with improved formatting
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatDurationPosition(audioPlayerVM.position)),
                Text(formatDurationPosition(audioPlayerVM.duration)),
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
  String formatTimePosition(double seconds) {
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
  String formatDurationPosition(Duration duration) {
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

  void _showSettingsDialog(BuildContext context) {
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
