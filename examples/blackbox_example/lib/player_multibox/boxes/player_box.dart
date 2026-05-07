import 'package:blackbox/blackbox.dart';

import '../fake_native_player.dart';

enum PlayerStatus { idle, loading, playing, paused, error }

PlayerStatus _mapStatus(NativeState s) => switch (s) {
      NativeState.idle => PlayerStatus.idle,
      NativeState.loading => PlayerStatus.loading,
      NativeState.playing => PlayerStatus.playing,
      NativeState.paused => PlayerStatus.paused,
      NativeState.error => PlayerStatus.error,
    };

/// Player composite. Single graph-driven input — the current [Channel]
/// — and N independently-observable child boxes (status, position,
/// trackTitle). On every channel change the multibox tears down the
/// previous "native" player and rebinds new stream subscriptions.
///
/// Notice how the four children are declared as one-line
/// [valueBox<T>(initial)] cells — no separate Box subclass per field,
/// no boilerplate compute methods. Identity compute is exactly what
/// these leaf cells need.
class PlayerBox extends MultiBox<Channel> {
  // ── outputs ────────────────────────────────────────────────────────
  // Each is a public OutputSource the UI/graph can subscribe to.
  // No setters, no public input — only the graph and this multibox can
  // drive them, via [dispatch] inside [compute] below.
  final status = valueBox<PlayerStatus>(PlayerStatus.idle);
  final position = valueBox<Duration>(Duration.zero);
  final trackTitle = valueBox<String>('');
  final channelName = valueBox<String>('');

  // ── private "native" handle ────────────────────────────────────────
  FakeNativePlayer? _native;

  // ── commands (called by UI) ───────────────────────────────────────
  void play() => _native?.play();
  void pause() => _native?.pause();

  // ── compute: the heart of the composite ────────────────────────────
  // Called whenever the graph delivers a new Channel. MultiBox auto-
  // cancels everything tracked for the previous input before this runs,
  // so we only need to release the native handle (a non-tracked
  // resource) and rebind fresh subscriptions.
  @override
  void compute(Channel current, Channel? previous) {
    _native?.release();
    _native = FakeNativePlayer()..setSource(current.url, current.playlist);

    // Dispatch transformed values into the identity-compute children.
    track(_native!.onStateChanged
        .listen((s) => dispatch(status, _mapStatus(s)))
        .cancel);
    track(_native!.onPositionChanged
        .listen((p) => dispatch(position, p))
        .cancel);
    track(_native!.onTrackChanged
        .listen((t) => dispatch(trackTitle, t))
        .cancel);

    // No native event for "channel name" — set it directly.
    dispatch(channelName, current.name);
  }

  @override
  void dispose() {
    _native?.release();
    super.dispose();
  }
}
