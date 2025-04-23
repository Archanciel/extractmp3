import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../viewmodels/audio_extractor_viewmodel.dart';
import '../viewmodels/audio_player_viewmodel.dart';

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

  Future<void> _pickMP3File(BuildContext context) async {
    final viewModel = Provider.of<AudioExtractorViewModel>(
      context,
      listen: false,
    );

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
        viewModel.setAudioFile(path, name, duration);

        // Reset initialized flags to update the text fields with new values
        setState(() {
          _startFieldInitialized = false;
          _endFieldInitialized = false;
        });
      }
    } catch (e) {
      viewModel.setError('Error selecting file: $e');
    }
  }

  Future<void> _extractMP3(BuildContext context) async {
    final viewModel = Provider.of<AudioExtractorViewModel>(
      context,
      listen: false,
    );

    if (viewModel.audioFile.path == null) {
      viewModel.setError('Please select an MP3 file first');
      return;
    }

    // Set processing state
    viewModel.startProcessing();

    try {
      // Create suggested filename with improved formatting
      final String baseFileName =
          viewModel.audioFile.name?.split('.').first ?? 'extract';

      // Format start and end positions for filename
      final String startFormatted = formatTimePosition(
        viewModel.startPosition,
      ).replaceAll(':', '-').replaceAll('.', 'd');
      final String endFormatted = formatTimePosition(
        viewModel.endPosition,
      ).replaceAll(':', '-').replaceAll('.', 'd');

      final String suggestedFileName =
          '${baseFileName}_${startFormatted}_$endFormatted.mp3';

      // Show file picker to choose save location
      String? outputPath;

      // For desktop platforms, use FilePicker to select save location
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory == null) {
        // User canceled the picker
        viewModel.setError('Save location selection canceled');
        return;
      }

      outputPath =
          '$selectedDirectory${Platform.pathSeparator}$suggestedFileName';

      await viewModel.extractMP3(outputPath);
    } catch (e) {
      viewModel.setError('Error selecting save location: $e');
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
    AudioExtractorViewModel viewModel,
  ) {
    final newValueSeconds = parseTimeInput(controller.text);

    if (isStart) {
      // For start position
      if (newValueSeconds >= 0 &&
          newValueSeconds < viewModel.endPosition &&
          newValueSeconds <= viewModel.audioFile.duration) {
        viewModel.startPosition = newValueSeconds;
      }

      // Update the display with the model's value (which may have been validated)
      _safeUpdateController(
        controller,
        formatTimePosition(viewModel.startPosition),
      );
    } else {
      // For end position
      if (newValueSeconds > viewModel.startPosition &&
          newValueSeconds <= viewModel.audioFile.duration) {
        viewModel.endPosition = newValueSeconds;
      }

      // Update the display with the model's value (which may have been validated)
      _safeUpdateController(
        controller,
        formatTimePosition(viewModel.endPosition),
      );
    }
  }

  // Load and play extracted MP3 with error handling
  Future<void> _playExtractedFile(BuildContext context, String filePath) async {
    final playerViewModel = Provider.of<AudioPlayerViewModel>(
      context,
      listen: false,
    );

    // Reset any previous errors
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    try {
      await playerViewModel.loadFile(filePath);
      if (!playerViewModel.hasError) {
        await playerViewModel.togglePlay();
      } else {
        _showErrorSnackBar(context, playerViewModel.errorMessage);
      }
    } catch (e) {
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
            final playerViewModel = Provider.of<AudioPlayerViewModel>(
              context,
              listen: false,
            );
            playerViewModel.tryRepairPlayer();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MP3 Extractor')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Consumer2<AudioExtractorViewModel, AudioPlayerViewModel>(
          builder: (context, viewModel, playerViewModel, child) {
            // Initialize controllers with current values, but only once
            if (!_startFieldInitialized && viewModel.audioFile.isSelected) {
              _startController.text = formatTimePosition(
                viewModel.startPosition,
              );
              _startFieldInitialized = true;
            }

            if (!_endFieldInitialized && viewModel.audioFile.isSelected) {
              _endController.text = formatTimePosition(viewModel.endPosition);
              _endFieldInitialized = true;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  onPressed: () => _pickMP3File(context),
                  child: const Text('Select MP3 File'),
                ),
                const SizedBox(height: 16),
                if (viewModel.audioFile.isSelected) ...[
                  Text(
                    'Selected File: ${viewModel.audioFile.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Duration: ${formatTimePosition(viewModel.audioFile.duration)}',
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
                                viewModel,
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
                                  newValueSeconds < viewModel.endPosition &&
                                  newValueSeconds <=
                                      viewModel.audioFile.duration) {
                                viewModel.startPosition = newValueSeconds;
                              }
                            },
                            onSubmitted: (value) {
                              _processTimeInput(
                                _startController,
                                true,
                                viewModel,
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
                                viewModel,
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
                              if (newValueSeconds > viewModel.startPosition &&
                                  newValueSeconds <=
                                      viewModel.audioFile.duration) {
                                viewModel.endPosition = newValueSeconds;
                              }
                            },
                            onSubmitted: (value) {
                              _processTimeInput(
                                _endController,
                                false,
                                viewModel,
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
                        viewModel.extractionResult.isProcessing
                            ? null
                            : () {
                              playerViewModel.isLoaded = false;
                              
                              // Parse the current text field values once more before extraction
                              final startSeconds = parseTimeInput(
                                _startController.text,
                              );
                              if (startSeconds >= 0 &&
                                  startSeconds < viewModel.endPosition &&
                                  startSeconds <=
                                      viewModel.audioFile.duration) {
                                viewModel.startPosition = startSeconds;
                              }

                              final endSeconds = parseTimeInput(
                                _endController.text,
                              );
                              if (endSeconds > viewModel.startPosition &&
                                  endSeconds <= viewModel.audioFile.duration) {
                                viewModel.endPosition = endSeconds;
                              }

                              _extractMP3(context);
                            },
                    child: const Text('Extract MP3'),
                  ),
                ],
                const SizedBox(height: 16),
                if (viewModel.extractionResult.isProcessing)
                  const Center(child: CircularProgressIndicator()),
                if (viewModel.extractionResult.hasMessage)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Text(
                      viewModel.extractionResult.message,
                      style: TextStyle(
                        color:
                            viewModel.extractionResult.isError
                                ? Colors.red
                                : viewModel.extractionResult.isSuccess
                                ? Colors.green
                                : Colors.black,
                      ),
                    ),
                  ),

                // Audio Player Section - Only visible when extraction is successful
                if (viewModel.extractionResult.isSuccess &&
                    viewModel.extractionResult.outputPath != null) ...[
                  const Divider(height: 32),
                  const Text(
                    'Audio Player',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  // Show player UI
                  _buildAudioPlayerControls(
                    context,
                    viewModel,
                    playerViewModel,
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
    AudioExtractorViewModel viewModel,
    AudioPlayerViewModel playerViewModel,
  ) {
    return Column(
      children: [
        // Play/Pause Button
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed:
                  playerViewModel.hasError
                      ? () => playerViewModel.tryRepairPlayer()
                      : playerViewModel.isLoaded
                      ? () => playerViewModel.togglePlay()
                      : () => _playExtractedFile(
                        context,
                        viewModel.extractionResult.outputPath!,
                      ),
              icon: Icon(
                playerViewModel.hasError
                    ? Icons.refresh
                    : playerViewModel.isPlaying
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
              label: Text(
                playerViewModel.hasError
                    ? 'Retry'
                    : playerViewModel.isPlaying
                    ? 'Pause'
                    : 'Play',
              ),
            ),
          ],
        ),

        // Player progress bar (only visible when file is loaded and no errors)
        if (playerViewModel.isLoaded && !playerViewModel.hasError) ...[
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: playerViewModel.progressPercent.clamp(0.0, 1.0),
              onChanged: (value) {
                playerViewModel.seekByPercentage(value);
              },
            ),
          ),

          // Time display with improved formatting
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatDurationPosition(playerViewModel.position)),
                Text(formatDurationPosition(playerViewModel.duration)),
              ],
            ),
          ),

          // File name display
          const SizedBox(height: 8),
          Text(
            'Playing: ${_getFileName(viewModel.extractionResult.outputPath!)}',
            style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],

        // Error message (if any)
        if (playerViewModel.hasError)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              playerViewModel.errorMessage,
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
}
