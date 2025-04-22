import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../viewmodels/audio_extractor_viewmodel.dart';
import '../viewmodels/audio_player_viewmodel.dart';

class AudioExtractorView extends StatelessWidget {
  const AudioExtractorView({super.key});

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
      // Create suggested filename
      final String baseFileName =
          viewModel.audioFile.name?.split('.').first ?? 'extract';
      final String suggestedFileName =
          '${baseFileName}_${viewModel.startPosition.toInt()}_${viewModel.endPosition.toInt()}.mp3';

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

  // Load and play extracted MP3
  Future<void> _playExtractedFile(BuildContext context, AudioPlayerViewModel playerViewModel, String filePath,) async {
    await playerViewModel.loadFile(filePath);
    await playerViewModel.togglePlay();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MP3 Extractor')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Consumer2<AudioExtractorViewModel, AudioPlayerViewModel>(
          builder: (context, viewModel, playerViewModel, child) {
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
                    'Duration: ${_formatDuration(viewModel.audioFile.duration)}',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Start Position: '),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '0.0',
                            suffixText: 's',
                          ),
                          controller: TextEditingController(
                            text: viewModel.startPosition.toStringAsFixed(1),
                          ),
                          onChanged: (value) {
                            final newValue = double.tryParse(value);
                            if (newValue != null &&
                                newValue >= 0 &&
                                newValue < viewModel.endPosition) {
                              viewModel.startPosition = newValue;
                            }
                          },
                        ),
                      ),
                      const Spacer(),
                      Text(_formatDuration(viewModel.startPosition)),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('End Position: '),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '60.0',
                            suffixText: 's',
                          ),
                          controller: TextEditingController(
                            text: viewModel.endPosition.toStringAsFixed(1),
                          ),
                          onChanged: (value) {
                            final newValue = double.tryParse(value);
                            if (newValue != null &&
                                newValue > viewModel.startPosition &&
                                newValue <= viewModel.audioFile.duration) {
                              viewModel.endPosition = newValue;
                            }
                          },
                        ),
                      ),
                      const Spacer(),
                      Text(_formatDuration(viewModel.endPosition)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed:
                        viewModel.extractionResult.isProcessing
                            ? null
                            : () => _extractMP3(context),
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
                    style: TextStyle(
                      fontSize: 18, 
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Play/Pause Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: playerViewModel.isLoaded
                            ? () => playerViewModel.togglePlay()
                            : () => _playExtractedFile(
                                context, 
                                playerViewModel,
                                viewModel.extractionResult.outputPath!,
                              ),
                        icon: Icon(
                          playerViewModel.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                        label: Text(
                          playerViewModel.isPlaying ? 'Pause' : 'Play',
                        ),
                      ),
                    ],
                  ),
                  
                  // Player progress bar (only visible when file is loaded)
                  if (playerViewModel.isLoaded) ...[
                    const SizedBox(height: 8),
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                        ),
                      ),
                      child: Slider(
                        value: playerViewModel.progressPercent.clamp(0.0, 1.0),
                        onChanged: (value) {
                          playerViewModel.seekByPercentage(value);
                        },
                      ),
                    ),
                    
                    // Time display
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDurationFromDuration(
                              playerViewModel.position)),
                          Text(_formatDurationFromDuration(
                              playerViewModel.duration)),
                        ],
                      ),
                    ),
                    
                    // File name display
                    const SizedBox(height: 8),
                    Text(
                      'Playing: ${_getFileName(viewModel.extractionResult.outputPath!)}',
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  String _formatDuration(double seconds) {
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int secs = seconds.toInt() % 60;
    final String hoursStr = hours > 0 ? '$hours:' : '';
    final String minutesStr =
        minutes < 10 && hours > 0 ? '0$minutes:' : '$minutes:';
    final String secondsStr = secs < 10 ? '0$secs' : '$secs';
    return '$hoursStr$minutesStr$secondsStr';
  }
  
  String _formatDurationFromDuration(Duration duration) {
    final int minutes = duration.inMinutes;
    final int seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
  
  String _getFileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }
}