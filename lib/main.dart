import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' show Platform, Directory, Process, ProcessResult;
import 'package:permission_handler/permission_handler.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MP3 Extractor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MP3ExtractorScreen(),
    );
  }
}

class MP3ExtractorScreen extends StatefulWidget {
  const MP3ExtractorScreen({Key? key}) : super(key: key);

  @override
  State<MP3ExtractorScreen> createState() => _MP3ExtractorScreenState();
}

class _MP3ExtractorScreenState extends State<MP3ExtractorScreen> {
  String? _selectedFilePath;
  String? _fileName;
  double _startPosition = 0.0;
  double _endPosition = 60.0;
  bool _isProcessing = false;
  String _statusMessage = '';
  double _totalDuration = 60.0; // Default assumption

  Future<void> _pickMP3File() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowedExtensions: ['mp3'],
      );

      if (result != null) {
        setState(() {
          _selectedFilePath = result.files.single.path;
          _fileName = result.files.single.name;
          // Reset positions when a new file is selected
          _startPosition = 0.0;
          // Get the duration (would need media_info plugin for accurate duration)
          // For simplicity, we're using a default duration
          _endPosition = _totalDuration;
          _statusMessage = 'File selected: $_fileName';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error selecting file: $e';
      });
    }
  }

  Future<void> _extractMP3() async {
    if (_selectedFilePath == null) {
      setState(() {
        _statusMessage = 'Please select an MP3 file first';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Processing...';
    });

    try {
      // Get a directory that works cross-platform
      Directory directory;
      if (Platform.isAndroid) {
        // Request storage permission for Android
        var status = await Permission.storage.request();
        if (!status.isGranted) {
          setState(() {
            _isProcessing = false;
            _statusMessage = 'Storage permission denied';
          });
          return;
        }
        // Try to get external storage for Android
        directory = (await getExternalStorageDirectory())!;
      } else if (Platform.isIOS) {
        // Use documents directory for iOS
        directory = await getApplicationDocumentsDirectory();
      } else {
        // For other platforms (Windows, macOS, Linux) use application documents directory
        directory = await getApplicationDocumentsDirectory();
      }

      // Create output filename with original file name as base
      final String baseFileName = _fileName?.split('.').first ?? 'extract';
      final String outputFileName = '${baseFileName}_${_startPosition.toInt()}_${_endPosition.toInt()}.mp3';
      final String outputPath = '${directory.path}/$outputFileName';

      // For Windows, use the system's FFmpeg directly
      if (Platform.isWindows) {
        try {
          // Different approach - reencode instead of stream copy
          // This solves the "Could not write header" error
          final List<String> arguments = [
            '-i', _selectedFilePath!,
            '-ss', _startPosition.toString(),
            '-to', _endPosition.toString(),
            '-acodec', 'libmp3lame',  // Use MP3 encoder instead of copy
            '-b:a', '192k',           // Set bitrate
            outputPath,
            '-y'  // Overwrite output files without asking
          ];

          // Print the command for debugging
          print('FFmpeg command: ffmpeg ${arguments.join(' ')}');

          // Execute FFmpeg as a process
          final ProcessResult result = await Process.run('ffmpeg', arguments);
          
          if (result.exitCode == 0) {
            setState(() {
              _isProcessing = false;
              _statusMessage = 'Success! Extracted MP3 saved to: $outputPath';
            });
          } else {
            setState(() {
              _isProcessing = false;
              _statusMessage = 'Error processing file: ${result.stderr}';
              print('FFmpeg stderr: ${result.stderr}');
              print('FFmpeg stdout: ${result.stdout}');
            });
          }
        } catch (e) {
          setState(() {
            _isProcessing = false;
            _statusMessage = 'FFmpeg error: $e\n\nMake sure FFmpeg is installed and in your PATH.';
          });
        }
      } else {
        // For mobile platforms, also change to reencode
        final String command = '-i "$_selectedFilePath" -ss $_startPosition -to $_endPosition -acodec libmp3lame -b:a 192k "$outputPath" -y';
        
        await FFmpegKit.executeAsync(
          command,
          (session) async {
            final returnCode = await session.getReturnCode();
            
            if (ReturnCode.isSuccess(returnCode)) {
              setState(() {
                _isProcessing = false;
                _statusMessage = 'Success! Extracted MP3 saved to: $outputPath';
              });
            } else {
              setState(() {
                _isProcessing = false;
                _statusMessage = 'Error processing file: ${returnCode?.getValue() ?? "Unknown error"}';
              });
            }
          },
          (log) {
            print("FFmpeg Log: $log");
          },
          (statistics) {
            // Process statistics updates if needed
          },
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error during extraction: $e';
      });
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _pickMP3File,
              child: const Text('Select MP3 File'),
            ),
            const SizedBox(height: 16),
            if (_selectedFilePath != null) ...[
              Text(
                'Selected File: $_fileName',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text('Start Position (seconds): ${_startPosition.toStringAsFixed(1)}'),
              Slider(
                value: _startPosition,
                min: 0,
                max: _endPosition > 0 ? _endPosition : _totalDuration,
                divisions: 100,
                onChanged: (value) {
                  setState(() {
                    _startPosition = value;
                  });
                },
              ),
              Text('End Position (seconds): ${_endPosition.toStringAsFixed(1)}'),
              Slider(
                value: _endPosition,
                min: _startPosition,
                max: _totalDuration,
                divisions: 100,
                onChanged: (value) {
                  setState(() {
                    _endPosition = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isProcessing ? null : _extractMP3,
                child: const Text('Extract MP3'),
              ),
            ],
            const SizedBox(height: 16),
            if (_isProcessing)
              const Center(child: CircularProgressIndicator()),
            if (_statusMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    color: _statusMessage.startsWith('Error') || _statusMessage.startsWith('Please')
                        ? Colors.red
                        : _statusMessage.startsWith('Success')
                            ? Colors.green
                            : Colors.black,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}