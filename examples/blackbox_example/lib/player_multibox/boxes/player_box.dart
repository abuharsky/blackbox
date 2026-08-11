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
/// `child(initial)` output cells — no Box subclass per field, no compute
/// methods. `child(...)` is the outward twin of `state(...)`: the world
/// reads and subscribes, only this multibox writes (via [dispatch]).
///
/// The cells are distinct by default: native streams re-emit identical
/// statuses/titles constantly — equal values are absorbed here and never
/// wake up the UI or the graph.
class PlayerBox extends MultiBox<Channel> {
  // ── outputs ────────────────────────────────────────────────────────
  // Each is a public OutputSource the UI/graph can subscribe to.
  // No setters, no public input — only this multibox can write them,
  // via [dispatch] inside [compute] below.
  late final status = child(PlayerStatus.idle);
  late final position = child(Duration.zero);
  late final trackTitle = child('');
  late final channelName = child('');

  // ── private "native" handle ────────────────────────────────────────
  FakeNativePlayer? _native;

  // ── commands (called by UI) ───────────────────────────────────────
  void play() => _native?.play();
  void pause() => _native?.pause();

  // ── compute: the heart of the composite ────────────────────────────
  // Called whenever the graph delivers a new Channel. MultiBox auto-
  // cancels every connect()-ed subscription before this runs, so we only
  // need to release the native handle (a non-tracked resource) and wire
  // fresh routes. compute reads as a routing table: source → output.
  @override
  void compute(Channel current) {
    _native?.release();
    _native = FakeNativePlayer()..setSource(current.url, current.playlist);

    connect(_native!.onStateChanged, status, map: _mapStatus);
    connect(_native!.onPositionChanged, position);
    connect(_native!.onTrackChanged, trackTitle);

    // No native event for "channel name" — set it directly.
    dispatch(channelName, current.name);
  }

  @override
  void dispose() {
    _native?.release();
    super.dispose();
  }
}
