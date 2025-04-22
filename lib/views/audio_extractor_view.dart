import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/audio_extractor_viewmodel.dart';
import '../models/extraction_result.dart';

class AudioExtractorView extends StatelessWidget {
  const AudioExtractorView({Key? key}) : super(key: key);

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
                  onPressed: viewModel.pickMP3File,
                  child: const Text('Select MP3 File'),
                ),
                const SizedBox(height: 16),
                if (viewModel.audioFile.isSelected) ...[
                  Text(
                    'Selected File: ${viewModel.audioFile.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Text('Start Position (seconds): ${viewModel.startPosition.toStringAsFixed(1)}'),
                  Slider(
                    value: viewModel.startPosition,
                    min: 0,
                    max: viewModel.endPosition > 0 ? viewModel.endPosition : viewModel.audioFile.duration,
                    divisions: 100,
                    onChanged: (value) {
                      viewModel.startPosition = value;
                    },
                  ),
                  Text('End Position (seconds): ${viewModel.endPosition.toStringAsFixed(1)}'),
                  Slider(
                    value: viewModel.endPosition,
                    min: viewModel.startPosition,
                    max: viewModel.audioFile.duration,
                    divisions: 100,
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
}