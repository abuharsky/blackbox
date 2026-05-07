import 'dart:async';

/// Channel descriptor — a "URL" plus a small playlist of tracks.
class Channel {
  final String name;
  final String url;
  final List<String> playlist;

  const Channel({
    required this.name,
    required this.url,
    required this.playlist,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Channel && other.name == name && other.url == url;

  @override
  int get hashCode => Object.hash(name, url);

  @override
  String toString() => 'Channel($name)';
}

/// Native player playback states. Stand-in for what a platform plugin
/// would emit (e.g. ExoPlayer / AVPlayer state machine).
enum NativeState { idle, loading, playing, paused, error }

/// Fake "native" player. Mimics the shape of a real native plugin:
/// you call setUrl/play/pause, you subscribe to state/position/track
/// streams. Used to demonstrate how a [MultiBox] subclass wires
/// transient native callbacks into its child boxes.
class FakeNativePlayer {
  final _stateCtrl = StreamController<NativeState>.broadcast();
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _trackCtrl = StreamController<String>.broadcast();

  String? _url;
  List<String> _playlist = const [];
  int _trackIndex = 0;
  Duration _position = Duration.zero;
  Timer? _ticker;
  bool _disposed = false;

  Stream<NativeState> get onStateChanged => _stateCtrl.stream;
  Stream<Duration> get onPositionChanged => _positionCtrl.stream;
  Stream<String> get onTrackChanged => _trackCtrl.stream;

  void setSource(String url, List<String> playlist) {
    _url = url;
    _playlist = playlist;
    _trackIndex = 0;
    _position = Duration.zero;
    _emitState(NativeState.loading);
    Timer(const Duration(milliseconds: 250), () {
      if (_disposed) return;
      _emitState(NativeState.paused);
      if (_playlist.isNotEmpty) _trackCtrl.add(_playlist.first);
    });
  }

  void play() {
    if (_url == null || _disposed) return;
    _emitState(NativeState.playing);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _position += const Duration(milliseconds: 200);
      _positionCtrl.add(_position);
      // Auto-advance every ~6 seconds to demo trackTitle changes.
      if (_position.inMilliseconds % 6000 == 0 && _playlist.isNotEmpty) {
        _trackIndex = (_trackIndex + 1) % _playlist.length;
        _trackCtrl.add(_playlist[_trackIndex]);
        _position = Duration.zero;
        _positionCtrl.add(_position);
      }
    });
  }

  void pause() {
    _ticker?.cancel();
    _ticker = null;
    if (_disposed) return;
    _emitState(NativeState.paused);
  }

  void release() {
    if (_disposed) return;
    _disposed = true;
    _ticker?.cancel();
    _ticker = null;
    _stateCtrl.close();
    _positionCtrl.close();
    _trackCtrl.close();
  }

  void _emitState(NativeState s) {
    if (_disposed) return;
    _stateCtrl.add(s);
  }
}
