import 'package:blackbox/blackbox.dart';

import '../fake_native_player.dart';

/// Holds the current channel selection. Plain sync box, mutates via
/// [select] (action). Drives the [PlayerBox] downstream.
class ChannelSelectorBox extends NoInputBox<Channel> {
  static const _channels = <Channel>[
    Channel(
      name: 'Synthwave FM',
      url: 'https://stream.example/synthwave',
      playlist: [
        'The Midnight – Sunset',
        'FM-84 – Running In The Night',
        'Timecop1983 – On The Run',
        'Gunship – Tech Noir',
      ],
    ),
    Channel(
      name: 'Lo-Fi Beats',
      url: 'https://stream.example/lofi',
      playlist: [
        'Idealism – Snow',
        'j\'san – Snowfall',
        'Yasumu – Floating',
        'Aiale – Hidden Garden',
      ],
    ),
    Channel(
      name: 'Jazz Cafe',
      url: 'https://stream.example/jazz',
      playlist: [
        'Bill Evans – Peace Piece',
        'Miles Davis – Blue in Green',
        'Chet Baker – Almost Blue',
        'Stan Getz – Desafinado',
      ],
    ),
  ];

  Channel _current = _channels.first;

  ChannelSelectorBox();

  List<Channel> get channels => _channels;

  @override
  Channel compute(Channel? previous) => _current;

  void select(Channel ch) {
    if (ch == _current) return;
    action(() => _current = ch);
  }
}
