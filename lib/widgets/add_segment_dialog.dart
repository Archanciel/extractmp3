import 'package:flutter/material.dart';
import '../models/audio_segment.dart';
import '../views/audio_extractor_view.dart'; // For TimeTextInputFormatter

class AddSegmentDialog extends StatefulWidget {
  final double maxDuration;
  final AudioSegment? existingSegment;
  
  const AddSegmentDialog({
    super.key,
    required this.maxDuration,
    this.existingSegment,
  });

  @override
  State<AddSegmentDialog> createState() => _AddSegmentDialogState();
}

class _AddSegmentDialogState extends State<AddSegmentDialog> {
  late TextEditingController _startController;
  late TextEditingController _endController;
  late TextEditingController _silenceController;
  
  @override
  void initState() {
    super.initState();
    
    if (widget.existingSegment != null) {
      _startController = TextEditingController(
        text: _formatTime(widget.existingSegment!.startPosition),
      );
      _endController = TextEditingController(
        text: _formatTime(widget.existingSegment!.endPosition),
      );
      _silenceController = TextEditingController(
        text: _formatTime(widget.existingSegment!.silenceDuration),
      );
    } else {
      _startController = TextEditingController(text: '0:00.0');
      _endController = TextEditingController(text: '0:00.0');
      _silenceController = TextEditingController(text: '0:00.0');
    }
  }
  
  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _silenceController.dispose();
    super.dispose();
  }
  
  String _formatTime(double seconds) {
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int secs = seconds.toInt() % 60;
    final int tenths = ((seconds - seconds.toInt()) * 10).round();
    
    String result = '';
    if (hours > 0) {
      result += '$hours:';
      result += '${minutes.toString().padLeft(2, '0')}:';
    } else {
      result += '$minutes:';
    }
    result += secs.toString().padLeft(2, '0');
    result += '.$tenths';
    
    return result;
  }
  
  double _parseTime(String input) {
    if (input.isEmpty) return 0.0;
    if (!input.contains(':')) return double.tryParse(input) ?? 0.0;
    
    try {
      double totalSeconds = 0.0;
      List<String> mainAndFraction = input.split('.');
      String mainPart = mainAndFraction[0];
      double fractionPart = 0.0;
      
      if (mainAndFraction.length > 1 && mainAndFraction[1].isNotEmpty) {
        fractionPart = double.tryParse('0.${mainAndFraction[1]}') ?? 0.0;
      }
      
      List<String> parts = mainPart.split(':');
      
      if (parts.length == 3) {
        int hours = int.tryParse(parts[0]) ?? 0;
        int minutes = int.tryParse(parts[1]) ?? 0;
        int seconds = int.tryParse(parts[2]) ?? 0;
        totalSeconds = (hours * 3600) + (minutes * 60) + seconds + fractionPart;
      } else if (parts.length == 2) {
        int minutes = int.tryParse(parts[0]) ?? 0;
        int seconds = int.tryParse(parts[1]) ?? 0;
        totalSeconds = (minutes * 60) + seconds + fractionPart;
      } else if (parts.length == 1) {
        int seconds = int.tryParse(parts[0]) ?? 0;
        totalSeconds = seconds + fractionPart;
      }
      
      return totalSeconds;
    } catch (e) {
      return 0.0;
    }
  }
  
  void _saveSegment() {
    final start = _parseTime(_startController.text);
    final end = _parseTime(_endController.text);
    final silence = _parseTime(_silenceController.text);
    
    if (start < 0 || start >= widget.maxDuration) {
      _showError('Start position must be between 0 and ${_formatTime(widget.maxDuration)}');
      return;
    }
    
    if (end <= start || end > widget.maxDuration) {
      _showError('End position must be after start and not exceed ${_formatTime(widget.maxDuration)}');
      return;
    }
    
    if (silence < 0) {
      _showError('Silence duration cannot be negative');
      return;
    }
    
    final segment = AudioSegment(
      startPosition: start,
      endPosition: end,
      silenceDuration: silence,
    );
    
    Navigator.of(context).pop(segment);
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existingSegment != null ? 'Edit Segment' : 'Add Segment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Max duration: ${_formatTime(widget.maxDuration)}'),
            const SizedBox(height: 16),
            TextField(
              controller: _startController,
              inputFormatters: [TimeTextInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Start Position',
                hintText: '0:00.0',
                helperText: 'h:mm:ss.t',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _endController,
              inputFormatters: [TimeTextInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'End Position',
                hintText: '0:00.0',
                helperText: 'h:mm:ss.t',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _silenceController,
              inputFormatters: [TimeTextInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Silence Duration After',
                hintText: '0:00.0',
                helperText: 'h:mm:ss.t (padding after this segment)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveSegment,
          child: const Text('Save'),
        ),
      ],
    );
  }
}