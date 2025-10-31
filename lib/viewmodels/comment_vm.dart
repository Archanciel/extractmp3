import 'package:flutter/foundation.dart';

import '../models/comment.dart';
import '../services/json_data_service.dart';

/// This VM (View Model) class is part of the MVVM architecture.
///
/// This class manages the audio player obtained from the
class CommentVM extends ChangeNotifier {
  Duration _currentCommentStartPosition = Duration.zero;
  Duration get currentCommentStartPosition => _currentCommentStartPosition;
  set currentCommentStartPosition(Duration value) {
    _currentCommentStartPosition = value;
    notifyListeners();
  }

  Duration _currentCommentEndPosition = Duration.zero;
  Duration get currentCommentEndPosition => _currentCommentEndPosition;
  set currentCommentEndPosition(Duration value) {
    _currentCommentEndPosition = value;
    notifyListeners();
  }

  // Used to manage second line play/pause button in audio player
  // view. This button is not displayed if comment dialog was opened
  // and/or minimized.
  bool _wasCommentDialogOpened = false;
  bool get wasCommentDialogOpened => _wasCommentDialogOpened;
  set wasCommentDialogOpened(bool value) {
    _wasCommentDialogOpened = value;
    notifyListeners();
  }

  CommentVM();

  @override
  void dispose() {
    // **NEW**: Dispose the new notifier
    super.dispose();
  }

  /// If the comment file exists, the list of comments it contains is
  /// returned, else, an empty list is returned.
  List<Comment> loadCommentsFromFile({required String commentFilePathName}) {
    return JsonDataService.loadListFromFile(
      jsonPathFileName: commentFilePathName,
      type: Comment,
    );
  }
}
