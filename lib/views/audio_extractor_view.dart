import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import '../viewmodels/audio_extractor_viewmodel.dart';
import '../models/extraction_result.dart';

class AudioExtractorView extends StatelessWidget {
  const AudioExtractorView({Key? key}) : super(key: key);

  Future<void> _pickMP3File(BuildContext context) async {
    final viewModel = Provider.of<AudioExtractorViewModel>(context, listen: false);
    
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
  
  Future<double> _getMP3Duration(String filePath) async {
    try {
      if (Platform.isWindows) {
        // For Windows, use direct FFmpeg command
        final List<String> arguments = [
          '-i', filePath,
          '-v', 'quiet',
          '-show_entries', 'format=duration',
          '-of', 'default=noprint_wrappers=1:nokey=1',
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
      } else {
        // For mobile, use FFmpegKit
        final session = await FFmpegKit.execute(
          '-i "$filePath" -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1'
        );
        
        final returnCode = await session.getReturnCode();
        
        if (ReturnCode.isSuccess(returnCode)) {
          final output = await session.getOutput();
          if (output != null && output.isNotEmpty) {
            // Try to parse the output as a double (duration in seconds)
            return double.tryParse(output.trim()) ?? 60.0;
          }
        }
        return 60.0; // Default fallback
      }
    } catch (e) {
      debugPrint('Error getting duration: $e');
      return 60.0; // Default duration if we can't determine it
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MP3 Extractor'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Consumer<AudioExtractorViewModel>(
          builder: (context, viewModel, child) {
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
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '0.0',
                            suffixText: 's',
                          ),
                          controller: TextEditingController(text: viewModel.startPosition.toStringAsFixed(1)),
                          onChanged: (value) {
                            final newValue = double.tryParse(value);
                            if (newValue != null && newValue >= 0 && newValue < viewModel.endPosition) {
                              viewModel.startPosition = newValue;
                            }
                          },
                        ),
                      ),
                      const Spacer(),
                      Text(_formatDuration(viewModel.startPosition)),
                    ],
                  ),
                  Slider(
                    value: viewModel.startPosition,
                    min: 0,
                    max: viewModel.endPosition > 0 ? viewModel.endPosition : viewModel.audioFile.duration,
                    divisions: (viewModel.audioFile.duration * 10).toInt(), // Divisions for tenths of seconds
                    onChanged: (value) {
                      viewModel.startPosition = value;
                    },
                  ),
                  Row(
                    children: [
                      const Text('End Position: '),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '60.0',
                            suffixText: 's',
                          ),
                          controller: TextEditingController(text: viewModel.endPosition.toStringAsFixed(1)),
                          onChanged: (value) {
                            final newValue = double.tryParse(value);
                            if (newValue != null && newValue > viewModel.startPosition && newValue <= viewModel.audioFile.duration) {
                              viewModel.endPosition = newValue;
                            }
                          },
                        ),
                      ),
                      const Spacer(),
                      Text(_formatDuration(viewModel.endPosition)),
                    ],
                  ),
                  Slider(
                    value: viewModel.endPosition,
                    min: viewModel.startPosition,
                    max: viewModel.audioFile.duration,
                    divisions: (viewModel.audioFile.duration * 10).toInt(), // Divisions for tenths of seconds
                    onChanged: (value) {
                      viewModel.endPosition = value;
                    },
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: viewModel.extractionResult.isProcessing ? null : viewModel.extractMP3,
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
                        color: viewModel.extractionResult.isError
                            ? Colors.red
                            : viewModel.extractionResult.isSuccess
                                ? Colors.green
                                : Colors.black,
                      ),
                    ),
                  ),
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
    final String minutesStr = minutes < 10 && hours > 0 ? '0$minutes:' : '$minutes:';
    final String secondsStr = secs < 10 ? '0$secs' : '$secs';
    return '$hoursStr$minutesStr$secondsStr';
  }
}