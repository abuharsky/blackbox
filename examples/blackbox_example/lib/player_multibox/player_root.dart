import 'package:blackbox/blackbox.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/material.dart';

import 'boxes/album_art_box.dart';
import 'boxes/channel_selector.dart';
import 'boxes/player_box.dart';
import 'fake_native_player.dart';
import 'ui/player_page.dart';

/// Wires the player graph:
///
/// ```
///   ChannelSelectorBox  ──►  PlayerBox (MultiBox<Channel>)
///                                │
///                                ├─► status      (ChildCell)
///                                ├─► position    (ChildCell)
///                                ├─► trackTitle  (ChildCell)      ──►  AlbumArtBox
///                                └─► channelName (ChildCell)
/// ```
///
/// AlbumArtBox depends on `player.trackTitle` — a child of the
/// MultiBox. We don't have to register it explicitly anywhere; the
/// first reference via `d.onlyWhenReady(player.trackTitle)` lazily
/// registers it as a graph source.
class PlayerRoot extends StatefulWidget {
  const PlayerRoot({super.key});

  @override
  State<PlayerRoot> createState() => _PlayerRootState();
}

class _PlayerRootState extends State<PlayerRoot> {
  late final ChannelSelectorBox selector;
  late final PlayerBox player;
  late final AlbumArtBox albumArt;
  late final Graph graph;

  @override
  void initState() {
    super.initState();
    selector = ChannelSelectorBox();
    player = PlayerBox();
    albumArt = AlbumArtBox('');

    graph = Graph.builder()
        .add(selector)
        .addMultiBox(player, input: (d) => d.onlyWhenReady<Channel>(selector))
        .add(albumArt, input: (d) => d.onlyWhenReady<String>(player.trackTitle))
        .build(start: true);
  }

  @override
  void dispose() {
    graph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Provide the COMPOSITE, not its cells: BoxProvider keys by
    // runtimeType, so generic cells (two ChildCell<String> here) would
    // silently collide. The page reads children off the composite.
    return BoxProvider.multi(
      boxes: [selector, player, albumArt],
      child: const PlayerPage(),
    );
  }
}
