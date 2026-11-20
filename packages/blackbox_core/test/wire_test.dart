import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

/// `Wire<I>` names the type of an `input:` function, so a box can declare
/// how it reads its input next to the input type, and the graph says only
/// what plugs into what.

final class StationBox extends NoInputBox<String?> {
  late final _v = state<String?>('jazz');
  @override
  String? compute() => _v.value;
  void set(String? v) => _v.value = v;
}

final class StatusBox extends NoInputBox<bool> {
  late final _v = state(false);
  @override
  bool compute() => _v.value;
  void set(bool v) => _v.value = v;
}

typedef NowPlayingInput = ({String? station, bool playing});

final class NowPlayingBox extends Box<NowPlayingInput, String> {
  NowPlayingBox.late() : super.late();

  static Wire<NowPlayingInput> wire({
    required OutputSource<String?> station,
    required OutputSource<bool> playing,
  }) =>
      (d) => (
            station: d.onlyWhenReady(station),
            playing: d.onlyWhenReady(playing),
          );

  @override
  String compute(NowPlayingInput i) => '${i.station} ${i.playing}';
}

final class EchoMultiBox extends MultiBox<String?> {
  late final last = child<String?>(null);
  @override
  void compute(String? station) => dispatch(last, station);
}

final class LogEffect {
  final seen = <String>[];
  Wire<String> input(OutputSource<String> source) =>
      (d) => d.onlyWhenReady(source);
  void apply(String now, String? was) => seen.add(now);
}

final class AppContext {}

void main() {
  test('a Wire plugs into add, addMultiBox and addEffect of a graph with '
      'a context', () async {
    final station = StationBox();
    final status = StatusBox();
    final nowPlaying = NowPlayingBox.late();
    final echo = EchoMultiBox();
    final log = LogEffect();
    final graph = Graph.builder<AppContext>(context: AppContext())
        .add(station)
        .add(status)
        .add(nowPlaying,
            input: NowPlayingBox.wire(station: station, playing: status))
        .addMultiBox(echo, input: (d) => d.onlyWhenReady(station))
        .addEffect(log.input(nowPlaying), name: 'log', run: log.apply)
        .build();
    await graph.settled();

    status.set(true);
    station.set('rock');
    await graph.settled();

    expect(nowPlaying.value, 'rock true');
    expect(echo.last.value, 'rock');
    expect(log.seen, ['jazz false', 'rock true']);
    graph.dispose();
  });
}
