import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:blackbox/map.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

/// A graph hears only what its wires read: a borrowed source (another
/// graph's box, a cell, a clock moment) no wire reads any more is let
/// go; declared boxes are always heard. The clock lets go of moments
/// nobody listens to.

final class ValueBox<T> extends NoInputBox<T> {
  ValueBox(T initial) : _initial = initial;
  final T _initial;
  late final _v = state<T>(_initial);
  @override
  T compute() => _v.value;
  void set(T v) => _v.value = v;
}

final class EchoBox<T> extends Box<T, T> {
  EchoBox.late() : super.late();
  @override
  T compute(T input) => input;
}

final class GateBox extends AsyncBox<int, int> {
  GateBox.late() : super.late();
  Completer<int> next = Completer();
  @override
  Future<int> compute(int n) => next.future;
}

void main() {
  // Condition 1 and 3 from the field: a conditional wire lets go of the
  // branch it no longer takes, and on coming back reads the source's
  // current output — never a snapshot from before it let go.
  test('a branch no longer read is let go; coming back reads it fresh',
      () async {
    final useX = ValueBox(true);
    final x = ValueBox(1); // borrowed: declared on no graph
    final y = ValueBox(100);
    final echo = EchoBox<int>.late();
    final traces = <PumpTrace>[];
    final graph = Graph.builder()
        .add(useX)
        .add(echo,
            input: (d) =>
                d.onlyWhenReady(useX) ? d.onlyWhenReady(x) : d.onlyWhenReady(y))
        .build(onTrace: traces.add);
    await graph.settled();
    expect(echo.value, 1);

    useX.set(false);
    await graph.settled();
    expect(echo.value, 100);

    final pumps = traces.length;
    x.set(5); // nobody reads x now: no pump
    x.set(7);
    await graph.settled();
    expect(traces.length, pumps, reason: 'the graph let go of x');

    useX.set(true);
    await graph.settled();
    expect(echo.value, 7, reason: 'x read fresh, not the 1 seen before');

    y.set(200); // y is the branch not taken now
    await graph.settled();
    x.set(8);
    await graph.settled();
    expect(echo.value, 8, reason: 'x is heard again');
    graph.dispose();
  });

  // Condition 2: a wire stopped half-way (a source not ready) keeps what
  // it read in its last complete run — those reads did not happen this
  // time, they did not stop mattering.
  test('a wire waiting on a source keeps its earlier subscriptions',
      () async {
    final n = ValueBox(1);
    final gate = GateBox.late();
    final extra = ValueBox('a'); // borrowed, read after the gate
    final echo = EchoBox<(int, String)>.late();
    final traces = <PumpTrace>[];
    final graph = Graph.builder()
        .add(n)
        .add(gate, input: (d) => d.onlyWhenReady(n))
        .add(echo,
            input: (d) => (d.onlyWhenReady(gate), d.onlyWhenReady(extra)))
        .build(onTrace: traces.add);
    gate.next.complete(10);
    await pumpEventQueue();
    expect(echo.value, (10, 'a'));

    gate.next = Completer();
    n.set(2); // the gate reloads: echo's wire stops before reading extra
    await pumpEventQueue();
    final pumps = traces.length;
    extra.set('b');
    await pumpEventQueue();
    expect(traces.length, greaterThan(pumps),
        reason: 'extra is still heard while the wire waits');

    gate.next.complete(20);
    await pumpEventQueue();
    expect(echo.value, (20, 'b'));
    graph.dispose();
  });

  test('declared boxes are always heard, even when no wire reads them',
      () async {
    final lonely = ValueBox(0);
    final traces = <PumpTrace>[];
    final graph = Graph.builder().add(lonely).build(onTrace: traces.add);
    await graph.settled();
    final pumps = traces.length;
    lonely.set(1);
    await graph.settled();
    expect(traces.length, greaterThan(pumps));
    graph.dispose();
  });

  group('ClockBox lets go of moments nobody reads', () {
    test('a wire asking for ever-new moments does not pile them up', () {
      fakeAsync((async) {
        final start = DateTime(2026, 1, 1, 12);
        final clock = ClockBox(now: () => async.getClock(start).now());
        final request = ValueBox(0);
        final fresh = EchoBox<bool>.late();
        final graph = Graph.builder()
            .addMultiBox(clock)
            .add(request)
            // A new "stale at" moment for every request — the field leak.
            .add(fresh,
                input: (d) => !d.onlyWhenReady(clock.at(
                    start.add(Duration(minutes: 5 + d.onlyWhenReady(request))),
                    name: 'cache too old')))
            .build();
        async.flushMicrotasks();

        for (var i = 1; i <= 50; i++) {
          request.set(i);
          async.flushMicrotasks();
        }
        expect(clock.children.length, lessThanOrEqualTo(2));
        expect(async.pendingTimers.length, lessThanOrEqualTo(2),
            reason: 'timers of forgotten moments are cancelled');
        expect(fresh.value, isTrue);

        async.elapse(const Duration(hours: 1));
        expect(fresh.value, isFalse, reason: 'the moment still read fires');

        // On the map, forgotten moments stay under their own clock, and
        // moments named alike are one line however many were asked.
        final m = graphMap({'banners': graph});
        expect(m, isNot(contains('(outside)')));
        expect(m, isNot(contains('Outside these graphs (')));
        expect('cell `ClockBox.cache too old`'.allMatches(m), hasLength(1));
        expect(m, isNot(contains('cache too old #')));
        graph.dispose();
        clock.dispose();
      });
    });

    test('a metronome nobody listens to stops ticking', () {
      fakeAsync((async) {
        final clock = ClockBox(now: () => async.getClock(DateTime(2026)).now());
        final cancel = clock.every(const Duration(seconds: 1)).listen((_) {});
        expect(async.periodicTimerCount, 1);
        cancel();
        async.flushMicrotasks();
        expect(async.periodicTimerCount, 0);
        expect(clock.children, isEmpty);
        clock.dispose();
      });
    });

    test('a reader re-subscribing in the same turn keeps the cell', () {
      fakeAsync((async) {
        final clock = ClockBox(now: () => async.getClock(DateTime(2026)).now());
        final tick = clock.every(const Duration(seconds: 1));
        final cancel = tick.listen((_) {});
        cancel(); // a UI rebuild: unsubscribe…
        final again = clock.every(const Duration(seconds: 1))
          ..listen((_) {}); // …and subscribe again, same turn
        async.flushMicrotasks();
        expect(again, same(tick));
        expect(async.periodicTimerCount, 1);
        clock.dispose();
      });
    });

    test('a forgotten moment asked again gives the same answer', () {
      fakeAsync((async) {
        final start = DateTime(2026, 1, 1, 12);
        final clock = ClockBox(now: () => async.getClock(start).now());
        final moment = start.add(const Duration(minutes: 1));
        final cancel = clock.at(moment).listen((_) {});
        async.elapse(const Duration(minutes: 2));
        cancel();
        async.flushMicrotasks();
        expect(clock.children, isEmpty);
        expect(clock.at(moment).output, const SyncData(true),
            reason: 'a past moment is true from birth');
        clock.dispose();
      });
    });
  });
}
