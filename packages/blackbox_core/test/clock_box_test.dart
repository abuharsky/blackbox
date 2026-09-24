import 'package:blackbox/blackbox.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

final class _Counter extends NoInputBox<int> {
  late final _count = state(0);

  @override
  int compute() => _count.value;

  void inc() => _count.value++;
}

final class _Due extends Box<bool, String> {
  _Due.late() : super.late();

  @override
  String compute(bool fired) => fired ? 'due' : 'pending';
}

final _start = DateTime(2026, 1, 1, 12);

/// The virtual-time recipe: the clock (and the graph that uses it) is
/// created *inside* `fakeAsync`, with `now:` read from the fake clock.
/// Timers created in the zone are virtual; the pump rides microtasks,
/// which the zone owns too — `elapse` fires timers *and* runs pumps.
ClockBox _clock(FakeAsync async) =>
    ClockBox(now: () => async.getClock(_start).now());

List<bool> _record(OutputSource<bool> cell) {
  final events = <bool>[];
  cell.listen((o) => events.add((o as SyncData<bool>).value));
  return events;
}

void main() {
  group('ClockBox.at', () {
    test('false before the moment, true after — one notification', () {
      fakeAsync((async) {
        final clock = _clock(async);
        final alarm = clock.at(_start.add(const Duration(seconds: 30)));

        final events = _record(alarm);
        expect(events, [false]);

        async.elapse(const Duration(seconds: 29));
        expect(events, [false]);

        async.elapse(const Duration(seconds: 1));
        expect(events, [false, true]);

        async.elapse(const Duration(hours: 1));
        expect(events, [false, true]); // stays fired, no second notification

        clock.dispose();
      });
    });

    test('a past moment is true from birth', () {
      fakeAsync((async) {
        final clock = _clock(async);
        final alarm = clock.at(_start.subtract(const Duration(seconds: 1)));
        expect(_record(alarm), [true]);
        clock.dispose();
      });
    });

    test('memoized by moment — ask twice, get the same cell', () {
      fakeAsync((async) {
        final clock = _clock(async);
        final moment = _start.add(const Duration(seconds: 1));
        expect(identical(clock.at(moment), clock.at(moment)), isTrue);
        clock.dispose();
      });
    });

    test('dispose cancels pending alarms', () {
      fakeAsync((async) {
        final clock = _clock(async);
        final alarm = clock.at(_start.add(const Duration(seconds: 30)));

        final events = _record(alarm);
        clock.dispose();

        async.elapse(const Duration(minutes: 1));
        expect(events, [false]);
      });
    });
  });

  group('ClockBox.every', () {
    test('born with the current time, then one notification per tick', () {
      fakeAsync((async) {
        final clock = _clock(async);
        final ticks = clock.every(const Duration(seconds: 1));

        final seen = <DateTime>[];
        ticks.listen((o) => seen.add((o as SyncData<DateTime>).value));
        expect(seen, [_start]); // the initial value, delivered on listen

        async.elapse(const Duration(seconds: 5));
        expect(seen.length, 6);
        expect(seen.last, _start.add(const Duration(seconds: 5)));

        clock.dispose();
      });
    });

    test('memoized by period', () {
      fakeAsync((async) {
        final clock = _clock(async);
        const period = Duration(seconds: 1);
        expect(identical(clock.every(period), clock.every(period)), isTrue);
        clock.dispose();
      });
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
    test('an effect wired to at() runs once at the boundary', () {
      fakeAsync((async) {
        final clock = _clock(async);
        final deadline = _start.add(const Duration(minutes: 5));

        final fired = <bool>[];
        final graph = Graph.builder<void>()
            .addMultiBox(clock)
            .addEffect<bool>(
              (d) => d.onlyWhenReady(clock.at(deadline)),
              name: 'alarm',
              run: (cur, prev) => fired.add(cur),
            )
            .build(start: true);

        async.flushMicrotasks(); // the initial pump
        expect(fired, [false]);

        async.elapse(const Duration(minutes: 4, seconds: 59));
        expect(fired, [false]);

        async.elapse(const Duration(seconds: 1));
        expect(fired, [false, true]); // exactly one boundary crossing

        async.elapse(const Duration(hours: 1));
        expect(fired, [false, true]);

        graph.dispose();
      });
    });

    test('ticks wake only the readers that asked for them', () {
      fakeAsync((async) {
        final clock = _clock(async);
        final counter = _Counter();

        var tickerRuns = 0;
        var counterRuns = 0;
        final graph = Graph.builder<void>()
            .addMultiBox(clock)
            .add(counter)
            .addEffect<DateTime>(
              (d) => d.onlyWhenReady(clock.every(const Duration(seconds: 1))),
              run: (cur, prev) => tickerRuns++,
            )
            .addEffect<int>(
              (d) => d.onlyWhenReady(counter),
              run: (cur, prev) => counterRuns++,
            )
            .build(start: true);

        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        expect(tickerRuns, 6); // initial + 5 ticks: pays per tick — its choice
        expect(counterRuns, 1); // input never changed: dedup absorbs the ticks

        graph.dispose();
      });
    });

    test('a UI-style listener on every() needs no graph at all', () {
      fakeAsync((async) {
        final clock = _clock(async);

        var rebuilds = 0;
        final cancel =
            clock.every(const Duration(seconds: 1)).listen((_) => rebuilds++);

        async.elapse(const Duration(seconds: 3));
        expect(rebuilds, 4); // initial + 3 ticks

        cancel();
        clock.dispose();
      });
    });

    test('the whole graph runs on virtual time — pumps included', () {
      // The moment is asked for lazily, inside a wire, during a pump: the
      // pump is a microtask in the fake zone, so the timer it creates is
      // virtual too. Nothing here waits on the wall clock.
      fakeAsync((async) {
        final clock = _clock(async);
        final deadline = _start.add(const Duration(days: 1));
        final due = _Due.late();

        final graph = Graph.builder<void>()
            .addMultiBox(clock)
            .add(due, input: (d) => d.onlyWhenReady(clock.at(deadline)))
            .build(start: true);

        async.flushMicrotasks();
        expect(due.value, 'pending');

        async.elapse(const Duration(hours: 23));
        expect(due.value, 'pending');

        async.elapse(const Duration(hours: 1));
        expect(due.value, 'due');

        graph.dispose();
      });
    });
  });
}
