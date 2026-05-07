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
///                                ├─► status      (ValueStateBox)
///                                ├─► position    (ValueStateBox)
///                                ├─► trackTitle  (ValueStateBox)  ──►  AlbumArtBox
///                                └─► channelName (ValueStateBox)
/// ```
///
/// AlbumArtBox depends on `player.trackTitle` — a child of the
/// MultiBox. We don't have to register it explicitly anywhere; the
/// first reference via `d.whenReady(player.trackTitle)` lazily
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
        .addMultiBox(player, input: (d) => d.whenReady<Channel>(selector))
        .add(albumArt, input: (d) => d.whenReady<String>(player.trackTitle))
        .build(start: true);
  }

  @override
  void dispose() {
    graph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BoxProvider.multi(
      boxes: [selector, player.channelName, player.status, player.position,
              player.trackTitle, albumArt],
      child: PlayerPage(player: player, selector: selector, albumArt: albumArt),
    );
  }
}
