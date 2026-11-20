import 'dart:async';
import 'dart:io';

import 'package:blackbox/blackbox.dart';
import 'package:blackbox/map.dart';
import 'package:test/test.dart';

// A small app in three graphs: purchases drives premium; player reads it
// across graphs; catalog has effects that press boxes (the legal ring)
// and two boxes that read foreign boxes inside compute (hidden links).

final class PremiumBox extends NoInputBox<bool> {
  late final _on = state(false);
  @override
  bool compute() => _on.value;
  void buy() => _on.value = true;
}

final class SelectionBox extends NoInputBox<String?> {
  late final _id = state<String?>(null);
  @override
  String? compute() => _id.value;
  void select(String id) => _id.value = id;
  void clear() => _id.value = null;
}

final class StreamUrlBox
    extends Box<({String? station, bool premium}), String?> {
  StreamUrlBox.late() : super.late();
  @override
  String? compute(i) =>
      i.station == null ? null : '${i.station}?hq=${i.premium}';
}

final class PlayerBox extends MultiBox<String?> {
  late final status = child('idle', name: 'status');
  late final buffered = child(0); // unnamed on purpose
  @override
  void compute(String? url) =>
      dispatch(status, url == null ? 'idle' : 'playing');
}

final class TitleBox extends Box<String, String> {
  TitleBox.late() : super.late();
  @override
  String compute(String status) => status.toUpperCase();
}

final class RegionBox extends NoInputBox<String> {
  late final _r = state('eu');
  @override
  String compute() => _r.value;
  void set(String r) => _r.value = r;
}

final class SearchQueryBox extends NoInputBox<String> {
  late final _region = state('');
  @override
  String compute() => _region.value;
  void setRegion(String r) => _region.value = r;
}

final class CounterBox extends NoInputBox<int> {
  late final _n = state(0);
  @override
  int compute() => _n.value;
  void bump() => _n.update((n) => n + 1);
}

/// Reads premium inside compute through a captured box — hidden.
final class LabelBox extends Box<String, String> {
  LabelBox.late(this._premium) : super.late();
  final PremiumBox _premium;
  @override
  String compute(String title) => _premium.value ? '$title ★' : title;
}

/// Reads the region through a closure after an await — hidden too.
final class PopularBox extends AsyncBox<int, List<String>> {
  PopularBox.late(this._region) : super.late();
  final String Function() _region;
  @override
  Future<List<String>> compute(int _) async {
    await Future<void>.delayed(Duration.zero);
    return ['top of ${_region()}'];
  }
}

/// A deliberate snapshot: not a hidden link.
final class SnapshotBox extends Box<String, String> {
  SnapshotBox.late(this._region) : super.late();
  final RegionBox _region;
  @override
  String compute(String t) =>
      '$t@${BoxHooks.untracked(() => _region.value)}';
}

void main() {
  late PremiumBox premium;
  late SelectionBox selection;
  late StreamUrlBox url;
  late PlayerBox player;
  late TitleBox title;
  late ClockBox clock;
  late RegionBox region;
  late SearchQueryBox query;
  late CounterBox sleep;
  late CounterBox stats;
  late LabelBox label;
  late PopularBox popular;
  late SnapshotBox snapshot;
  late Graph<void> purchases;
  late Graph<void> playback;
  late Graph<void> catalog;
  late List<String> printed;

  final expires = DateTime(2030);

  Future<void> build() async {
    premium = PremiumBox();
    selection = SelectionBox();
    url = StreamUrlBox.late();
    player = PlayerBox();
    title = TitleBox.late();
    clock = ClockBox();
    region = RegionBox();
    query = SearchQueryBox();
    sleep = CounterBox();
    stats = CounterBox();
    label = LabelBox.late(premium);
    popular = PopularBox.late(() => region.value);
    snapshot = SnapshotBox.late(region);

    purchases = Graph.builder().add(premium).build();
    playback = Graph.builder()
        .add(selection)
        .add(url, input: (d) {
          final station = d.onlyWhenReady(selection);
          // Conditional wire: premium is read only once a station exists.
          if (station == null) return (station: null, premium: false);
          return (station: station, premium: d.onlyWhenReady(premium));
        })
        .addMultiBox(player, input: (d) => d.onlyWhenReady(url))
        .add(title, input: (d) => d.onlyWhenReady(player.status))
        .addEffect<(String, bool)>(
          (d) => (
            d.onlyWhenReady(title),
            d.onlyWhenReady(clock.at(expires, name: 'banner expires')),
          ),
          name: 'now-playing',
          run: (_, __) {},
        )
        // Unnamed; presses from a timer it started.
        .addEffect<String>((d) => d.onlyWhenReady(title),
            run: (_, __) => Timer(Duration.zero, sleep.bump))
        .build();
    catalog = Graph.builder()
        .add(query)
        .add(sleep)
        .add(stats)
        .add(label, input: (d) => d.onlyWhenReady(title))
        .add(popular, input: (d) => 0)
        .add(snapshot, input: (d) => d.onlyWhenReady(title))
        .addEffect<String>((d) => d.onlyWhenReady(region),
            name: 'region', run: (r, _) => query.setRegion(r))
        .addEffect<String>((d) => d.onlyWhenReady(title), name: 'stats',
            run: (_, __) async {
          await Future<void>.delayed(Duration.zero);
          stats.bump(); // after an await: still this effect's press
        })
        .build();
    await pumpEventQueue();
  }

  setUp(() async {
    printed = [];
    await runZoned(build,
        zoneSpecification: ZoneSpecification(
            print: (_, __, ___, line) => printed.add(line)));
  });

  tearDown(() {
    catalog.dispose();
    playback.dispose();
    purchases.dispose();
    clock.dispose();
  });

  String map() => graphMap(
      {'purchases': purchases, 'player': playback, 'catalog': catalog});

  Future<void> selectStation() async {
    selection.select('jazz');
    await pumpEventQueue();
  }

  test('a conditional wire appears once taken, and stays', () async {
    expect(map(), isNot(contains('← `PremiumBox` (`purchases`), `SelectionBox`')));
    await selectStation();
    expect(map(), contains('← `PremiumBox` (`purchases`), `SelectionBox`'));
    selection.clear(); // the branch is no longer taken
    await pumpEventQueue();
    expect(map(), contains('← `PremiumBox` (`purchases`), `SelectionBox`'));
  });

  test('effects: presses from run, from a timer, after an await', () async {
    await selectStation();
    final m = map();
    expect(m, contains('- **effect `region`**\n  - ← `RegionBox` (outside)\n'
        '  - ⇒ presses `SearchQueryBox`'));
    expect(m, contains('⇒ presses `CounterBox #1` (`catalog`)'),
        reason: 'the timer it started pressed sleep');
    expect(m, contains('- **effect `stats`**'));
    expect(m, contains('⇒ presses `CounterBox #2`'),
        reason: 'pressed after an await');
    expect(m, contains('- **`SearchQueryBox`**\n  - ← no input wires\n'
        '  - ⇐ pressed by effect `region`'));
  });

  test('the pump is not attributed to an effect', () async {
    await selectStation();
    // The player's own compute dispatches cells during pumps that effects'
    // presses scheduled; that must not read as an effect pressing it.
    expect(map(), isNot(contains('presses `PlayerBox`')));
  });

  test('hidden links (touches) are on the map', () async {
    await selectStation();
    final m = map();
    expect(m, contains('⚠ touches: `PremiumBox` (`purchases`)'));
    expect(m, contains('⚠ touches: `RegionBox` (outside)'),
        reason: 'a closure read after an await in compute');
    expect(m, contains('⚠ Hidden links (2)'));
    expect(m, isNot(contains('`SnapshotBox`\n  - ← `TitleBox`\n  - ⚠')),
        reason: 'BoxHooks.untracked is a deliberate snapshot');
    // The console warning (once per pair of types, per process) is
    // covered in hidden_links_test.dart.
  });

  test('names: unnamed effects flagged, cells and clock moments named',
      () async {
    await selectStation();
    final m = map();
    expect(m, contains('- **effect `effect_2`** · unnamed'));
    expect(m, contains('effect `effect_2` (`player`, unnamed)'));
    expect(m, contains('Effects: 4, unnamed: 1'));
    expect(m, contains('cell `PlayerBox.status` → `TitleBox`'));
    expect(m, contains('cell `ClockBox.banner expires` → effect `now-playing`'));
  });

  test('overview: graphs, outside boxes, a picture of how they connect',
      () async {
    await selectStation();
    final m = map();
    expect(m, contains('| `player` | 4 | 2 | `ClockBox` 1, `purchases` 1 '
        '| `catalog` 1 |'));
    expect(m, contains('Outside these graphs (read here, driven elsewhere): '
        '`ClockBox`, `RegionBox`.'));
    expect(m, contains('graph_purchases -->|1| graph_player'));
    expect(m, contains('graph_player ==>|⇒ 1| graph_catalog'));
    expect(m, contains('graph_catalog -.->|⚠ 1| graph_purchases'));
  });

  test('"no graph reads it" instead of "nobody"; unnamed cell by type',
      () async {
    await selectStation();
    player.buffered; // a lazy cell is on the map once something touched it
    final m = map();
    expect(m, contains('- **`SearchQueryBox`**\n  - ← no input wires\n'
        '  - ⇐ pressed by effect `region`\n'
        '  - → no graph reads it (UI or `listen` may)'));
    expect(m, contains('cell `PlayerBox.cell<int>` → no graph reads it '
        '(UI or `listen` may)'));
  });

  // The recipe an app uses for doc/MAP.md: render after a scenario,
  // compare with the committed file, regenerate with one command.
  test('golden: the committed map is current', () async {
    await selectStation();
    final file = File('test/goldens/graph_map.md');
    if (Platform.environment['UPDATE_GOLDENS'] == '1') {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(map());
    }
    expect(map(), file.readAsStringSync(),
        reason: 'Map changed. Regenerate: UPDATE_GOLDENS=1 dart test '
            'test/graph_map_test.dart');
  });
}
