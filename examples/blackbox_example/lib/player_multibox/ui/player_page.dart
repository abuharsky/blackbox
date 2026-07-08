import 'package:blackbox/blackbox.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/material.dart';

import '../boxes/album_art_box.dart';
import '../boxes/channel_selector.dart';
import '../boxes/player_box.dart';

/// Demonstrates that each MultiBox child is observed independently —
/// switching channel rebuilds the channel name once, the play/pause
/// button only on `status` changes, the progress bar 5 times/second
/// on `position` ticks, etc. There is no shared "player state" object
/// to invalidate everything at once.
class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    // The composite arrives through BoxProvider like any other box —
    // a MultiBox is a ProvidableBox. Children are read off it; no
    // second delivery mechanism needed.
    final player = context.box<PlayerBox>();
    final selector = context.box<ChannelSelectorBox>();
    final albumArt = context.box<AlbumArtBox>();

    return Scaffold(
      appBar: AppBar(title: const Text('Player (MultiBox)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ChannelPicker(selector: selector),
            const SizedBox(height: 24),
            _NowPlaying(player: player, albumArt: albumArt),
            const SizedBox(height: 16),
            _ProgressBar(player: player),
            const SizedBox(height: 16),
            _PlayPauseButton(player: player),
            const Spacer(),
            _DiagnosticsPanel(player: player),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Channel picker — listens only to ChannelSelectorBox.
// Rebuilds when the user picks a different channel.
class _ChannelPicker extends StatelessWidget {
  const _ChannelPicker({required this.selector});
  final ChannelSelectorBox selector;

  @override
  Widget build(BuildContext context) {
    return BoxObserver(
      builder: (_) {
        final current = selector.value;
        return Wrap(
          spacing: 8,
          children: [
            for (final ch in selector.channels)
              ChoiceChip(
                label: Text(ch.name),
                selected: ch == current,
                onSelected: (_) => selector.select(ch),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Now-playing card. Rebuilds on:
// - player.channelName  → channel label
// - player.trackTitle   → title text
// - albumArt            → emoji art (async)
//
// Notice it does NOT rebuild on position ticks, even though those fire
// 5 times per second — the position widget is in a separate subtree.
class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.player, required this.albumArt});
  final PlayerBox player;
  final AlbumArtBox albumArt;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            BoxObserver(
              builder: (_) {
                final art = switch (albumArt.output) {
                  AsyncData<String>(:final value) => value,
                  AsyncLoading<String>() => '⏳',
                  AsyncError<String>() => '⚠️',
                };
                return Text(art, style: const TextStyle(fontSize: 48));
              },
            ),
            const SizedBox(width: 16),
            Expanded(
              child: BoxObserver(
                builder: (_) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.channelName.value,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      player.trackTitle.value.isEmpty
                          ? '— no track —'
                          : player.trackTitle.value,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Progress bar — listens ONLY to player.position.
// Rebuilds 5 times per second when playing; never on status/track changes.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.player});
  final PlayerBox player;

  @override
  Widget build(BuildContext context) {
    return BoxObserver(
      builder: (_) {
        final pos = player.position.value;
        // No total duration in fake native — show a "wraparound" 6s bar.
        final secs = pos.inMilliseconds / 1000.0;
        final progress = (secs % 6) / 6.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 4),
            Text(
              '${secs.toStringAsFixed(1)} s',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Play/pause button — listens ONLY to player.status.
// Rebuilds only when status changes (idle → playing → paused → …).
class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.player});
  final PlayerBox player;

  @override
  Widget build(BuildContext context) {
    return BoxObserver(
      builder: (_) {
        final status = player.status.value;
        final isPlaying = status == PlayerStatus.playing;
        return FilledButton.icon(
          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
          label: Text(isPlaying ? 'Pause' : 'Play'),
          onPressed: switch (status) {
            PlayerStatus.idle ||
            PlayerStatus.loading ||
            PlayerStatus.error =>
              null,
            PlayerStatus.playing => player.pause,
            PlayerStatus.paused => player.play,
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Diagnostics — shows per-field rebuild counts, makes the granularity
// of subscriptions visible to the eye.
class _DiagnosticsPanel extends StatelessWidget {
  const _DiagnosticsPanel({required this.player});
  final PlayerBox player;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Each row rebuilds independently (BoxObserver tracks only the field it reads):',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _Row(label: 'status', child: _StatusText(player: player)),
            _Row(label: 'position', child: _PositionText(player: player)),
            _Row(label: 'trackTitle', child: _TrackText(player: player)),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(fontFamily: 'monospace'))),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.player});
  final PlayerBox player;
  @override
  Widget build(BuildContext context) =>
      BoxObserver(builder: (_) => Text(player.status.value.name));
}

class _PositionText extends StatelessWidget {
  const _PositionText({required this.player});
  final PlayerBox player;
  @override
  Widget build(BuildContext context) =>
      BoxObserver(builder: (_) => Text('${player.position.value.inMilliseconds} ms'));
}

class _TrackText extends StatelessWidget {
  const _TrackText({required this.player});
  final PlayerBox player;
  @override
  Widget build(BuildContext context) =>
      BoxObserver(builder: (_) => Text(player.trackTitle.value));
}
