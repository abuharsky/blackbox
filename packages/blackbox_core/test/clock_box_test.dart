import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

final class _Counter extends NoInputBox<int> {
  late final _count = state(0);

  @override
  int compute() => _count.value;

  void inc() => _count.value++;
}

void main() {
  group('ClockBox.at', () {
    test('false before the moment, true after — one notification', () async {
      final clock = ClockBox();
      final alarm =
          clock.at(DateTime.now().add(const Duration(milliseconds: 30)));

      final events = <bool>[];
      alarm.listen((o) => events.add((o as SyncData<bool>).value));
      expect(events, [false]);

      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(events, [false, true]);

      clock.dispose();
    });

    test('a past moment is true from birth', () {
      final clock = ClockBox();
      final alarm =
          clock.at(DateTime.now().subtract(const Duration(seconds: 1)));

      final events = <bool>[];
      alarm.listen((o) => events.add((o as SyncData<bool>).value));
      expect(events, [true]);

      clock.dispose();
    });

    test('memoized by moment — ask twice, get the same cell', () {
      final clock = ClockBox();
      final moment = DateTime.now().add(const Duration(seconds: 1));
      expect(identical(clock.at(moment), clock.at(moment)), isTrue);
      clock.dispose();
    });

    test('dispose cancels pending alarms', () async {
      final clock = ClockBox();
      final alarm =
          clock.at(DateTime.now().add(const Duration(milliseconds: 30)));

      final events = <bool>[];
      alarm.listen((o) => events.add((o as SyncData<bool>).value));
      clock.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(events, [false]);
    });
  });

  group('ClockBox.every', () {
    test('born with the current time, then one notification per tick',
        () async {
      final clock = ClockBox();
      final ticks = clock.every(const Duration(milliseconds: 20));

      var count = 0;
      ticks.listen((_) => count++);
      expect(count, 1); // the initial value, delivered on listen

      await Future<void>.delayed(const Duration(milliseconds: 110));
      expect(count, greaterThanOrEqualTo(4));

      clock.dispose();
    });

    test('memoized by period', () {
      final clock = ClockBox();
      const period = Duration(milliseconds: 500);
      expect(identical(clock.every(period), clock.every(period)), isTrue);
      clock.dispose();
    });

    test('rejects a non-positive period', () {
      final clock = ClockBox();
      expect(() => clock.every(Duration.zero), throwsArgumentError);
      expect(() => clock.every(const Duration(seconds: -1)),
          throwsArgumentError);
      clock.dispose();
    });
  });

  group('in a graph', () {
    test('an effect wired to at() runs once at the boundary', () async {
      final clock = ClockBox();
      final deadline = DateTime.now().add(const Duration(milliseconds: 30));

      final fired = <bool>[];
      final graph = Graph.builder<void>()
          .addMultiBox(clock)
          .addEffect<bool>(
            (d) => d.onlyWhenReady(clock.at(deadline)),
            run: (cur, prev) => fired.add(cur),
          )
          .build(start: true);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fired, [false]); // the initial pump

      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(fired, [false, true]); // exactly one boundary crossing

      graph.dispose();
    });

    test('ticks wake only the readers that asked for them', () async {
      final clock = ClockBox();
      final counter = _Counter();

      var tickerRuns = 0;
      var counterRuns = 0;
      final graph = Graph.builder<void>()
          .addMultiBox(clock)
          .add(counter)
          .addEffect<DateTime>(
            (d) => d.onlyWhenReady(clock.every(const Duration(milliseconds: 20))),
            run: (cur, prev) => tickerRuns++,
          )
          .addEffect<int>(
            (d) => d.onlyWhenReady(counter),
            run: (cur, prev) => counterRuns++,
          )
          .build(start: true);

      await Future<void>.delayed(const Duration(milliseconds: 110));
      expect(tickerRuns, greaterThanOrEqualTo(4)); // pays per tick — its choice
      expect(counterRuns, 1); // input never changed: dedup absorbs the ticks

      graph.dispose();
    });

    test('a UI-style listener on every() needs no graph at all', () async {
      final clock = ClockBox();

      var rebuilds = 0;
      final cancel =
          clock.every(const Duration(milliseconds: 20)).listen((_) {
        rebuilds++;
      });

      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(rebuilds, greaterThanOrEqualTo(3));

      cancel();
      clock.dispose();
    });
  });
}
