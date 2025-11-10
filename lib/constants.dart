const String kApplicationVersion = '1.1.7';
const double kDefaultSilenceDuration = 1.0; // in seconds
const String kCommentDirName = 'comments';
const double kAudioDefaultPlaySpeed = 1.0;
const double kAudioDefaultPlayVolume = 0.5;

// true makes sense if audio are played in
// Smart AudioBook app
const bool kAudioFileNamePrefixIncludeTime = true;

// Number of seconds to consider that the audio was fully listened:
// If its current position is greater or equal to its total duration
// minus fullyListenedBufferSeconds seconds, then the audio is considered
// as being fully listened.
const int kFullyListenedBufferSeconds = 10;
