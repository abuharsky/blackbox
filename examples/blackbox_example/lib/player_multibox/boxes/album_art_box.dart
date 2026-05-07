import 'package:blackbox/blackbox.dart';

/// Demonstrates that **other graph nodes can react to fields of a
/// MultiBox** — exactly the same way they'd react to any other Box.
///
/// This async box takes a track title as input and "fetches" album art
/// for it. In the graph wiring we depend on `player.trackTitle` via
/// `whenReady(player.trackTitle)` — auto-registration makes that field
/// a live graph dependency without listing it explicitly anywhere.
class AlbumArtBox extends AsyncBox<String, String> {
  AlbumArtBox(super.input);

  @override
  Future<String> compute(String trackTitle, String? previous) async {
    // Simulate a CDN lookup.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (trackTitle.isEmpty) return '🎵';
    // Pick a deterministic emoji per title for visual stability.
    const palette = ['🌅', '🌃', '🎷', '🎹', '🎸', '🥁', '🎺', '🎻'];
    final pick = trackTitle.codeUnits.fold<int>(0, (a, b) => a + b) %
        palette.length;
    return palette[pick];
  }
}
