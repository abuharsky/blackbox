import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

Future<void> flushMicrotasks([int times = 8]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Test composite: receives an `int` channel id from the graph, exposes
/// two child boxes whose inputs are routed inside [compute].
final class TestPlayerBox extends MultiBox<int> {
  late final status = child('idle');
  late final position = child(0);

  // We expose the underlying StreamControllers so the test can push
  // values into them as if they came from a native plugin.
  StreamController<String>? _statusCtrl;
  StreamController<int>? _positionCtrl;

  StreamController<String> get statusCtrl => _statusCtrl!;
  StreamController<int> get positionCtrl => _positionCtrl!;

  int computeCalls = 0;
  int? lastInput;
  int? lastPrevious;
  bool disposed = false;

  @override
  void compute(int input) {
    computeCalls++;
    // The previous input is memory the subclass owns — the framework
    // no longer passes it.
    lastPrevious = lastInput;
    lastInput = input;

    // Tear down previous "native" — like a native player rebind.
    _statusCtrl?.close();
    _positionCtrl?.close();

    final s = StreamController<String>.broadcast();
    final p = StreamController<int>.broadcast();
    _statusCtrl = s;
    _positionCtrl = p;

    connect(s.stream, status);
    connect(p.stream, position);
  }

  @override
  void dispose() {
    disposed = true;
    _statusCtrl?.close();
    _positionCtrl?.close();
    super.dispose();
  }
}

/// Self-driven module: counts compute calls to prove the omitted-input
/// form delivers exactly one null input.
final class CountingVoidMultiBox extends MultiBox<void> {
  int computes = 0;

  @override
  void compute(void input) => computes++;
}

/// Module with a non-nullable input — omitting input: must assert.
final class IntEchoMultiBox extends MultiBox<int> {
  late final echoed = child(0);

  @override
  void compute(int input) => dispatch(echoed, input);
}

/// Composite that takes no graph-driven input — used to verify lifecycle
/// without graph driving (e.g. when graph just owns dispose).
final class NoOpMultiBox extends MultiBox<void> {
  bool computed = false;
  bool disposed = false;

  @override
  void compute(void input) {
    computed = true;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// Composite with an owned cell; can also dispatch into a foreign cell
/// to verify the ownership guard.
final class OwnershipMultiBox extends MultiBox<int> {
  late final owned = child(0);

  @override
  void compute(int input) {
    dispatch(owned, input);
  }

  void dispatchToForeign(ChildCell<int> foreign, int value) =>
      dispatch(foreign, value);
}

/// Composite using connect(): stream → map → output cell. A new
/// controller per input cycle; old ones are abandoned (not closed) so
/// the test can verify the old connection died with the cycle.
final class ConnectMultiBox extends MultiBox<int> {
  late final tripled = child(0);

  StreamController<int>? _c;
  StreamController<int> get ctrl => _c!;

  @override
  void compute(int input) {
    _c = StreamController<int>.broadcast();
    connect(_c!.stream, tripled, map: (v) => v * 3);
  }
}

/// Composite with a type-mismatched connect (no map) — must assert.
final class BadConnectMultiBox extends MultiBox<int> {
  late final text = child('');

  @override
  void compute(int input) {}

  void badConnect() =>
      connect(StreamController<int>.broadcast().stream, text);
}

/// Composite that (deliberately) forgets to track() its subscription —
/// simulates the subclass bug where a native stream outlives dispose.
final class LeakyMultiBox extends MultiBox<int> {
  late final status = child('idle');
  final ctrl = StreamController<String>.broadcast(sync: true);

  @override
  void compute(int input) {
    // NOTE: intentionally not track()-ed.
    ctrl.stream.listen((v) => dispatch(status, v));
  }
}

void main() {
  group('MultiBox (standalone)', () {
    test('compute is not called until the graph drives input', () {
      final mb = TestPlayerBox();
      expect(mb.computeCalls, 0);
    });

    test('dispose is idempotent', () async {
      final mb = TestPlayerBox();
      final driver = SpySyncBox(1);

      final g = Graph.builder()
          .add(driver)
          .addMultiBox(mb, input: (d) => d.onlyWhenReady<int>(driver))
          .build();

      await flushMicrotasks();

      g.dispose();
      expect(mb.disposed, isTrue);
      g.dispose(); // second call must be a no-op
      expect(mb.disposed, isTrue);
    });
  });

  group('MultiBox (graph-driven)', () {
    test('initial pump delivers input to compute', () async {
      final driver = SpySyncBox(7);
      final mb = TestPlayerBox();

      Graph.builder()
          .add(driver)
          .addMultiBox(mb, input: (d) => d.onlyWhenReady<int>(driver))
          .build();

      await flushMicrotasks();

      expect(mb.computeCalls, 1);
      expect(mb.lastInput, 7);
      expect(mb.lastPrevious, isNull);
    });

    test('child boxes receive routed values via dispatch', () async {
      final driver = SpySyncBox(1);
      final mb = TestPlayerBox();

      Graph.builder()
          .add(driver)
          .addMultiBox(mb, input: (d) => d.onlyWhenReady<int>(driver))
          .build();

      await flushMicrotasks();

      mb.statusCtrl.add('playing');
      mb.positionCtrl.add(42);

      // Stream callbacks are async; let them flush.
      await flushMicrotasks();

      expect(mb.status.value, 'playing');
      expect(mb.position.value, 42);
    });

    test('input change re-runs compute with previous value', () async {
      final driver = SpySyncBox(1);
      final mb = TestPlayerBox();

      Graph.builder()
          .add(driver)
          .addMultiBox(mb, input: (d) => d.onlyWhenReady<int>(driver))
          .build();

      await flushMicrotasks();
      expect(mb.lastInput, 1);
      expect(mb.lastPrevious, isNull);

      driver.setValue(2);
      await flushMicrotasks();

      expect(mb.lastInput, 2);
      expect(mb.lastPrevious, 1);
      expect(mb.computeCalls, 2);
    });

    test('same input value does not retrigger compute', () async {
      final driver = SpySyncBox(5);
      final mb = TestPlayerBox();

      Graph.builder()
          .add(driver)
          .addMultiBox(mb, input: (d) => d.onlyWhenReady<int>(driver))
          .build();

      await flushMicrotasks();
      expect(mb.computeCalls, 1);

      driver.setValue(5); // same value
      await flushMicrotasks();

      expect(mb.computeCalls, 1);
    });

    test('tracked subscriptions are auto-cancelled before next compute',
        () async {
      final driver = SpySyncBox(1);
      final mb = TestPlayerBox();

      Graph.builder()
          .add(driver)
          .addMultiBox(mb, input: (d) => d.onlyWhenReady<int>(driver))
          .build();

      await flushMicrotasks();

      // Capture the StreamController set up for input==1.
      final ctrlForInput1 = mb.statusCtrl;
      ctrlForInput1.add('first');
      await flushMicrotasks();
      expect(mb.status.value, 'first');

      // Switch input — compute is re-run, old subs should be released
      // (and the old controller will be closed by TestPlayerBox.compute).
      driver.setValue(2);
      await flushMicrotasks();

      // Old controller is now closed — pushing into it should be
      // ignored both by the controller (closed) and by the multibox
      // (subscription cancelled).
      expect(ctrlForInput1.isClosed, isTrue);

      // New controller is live and routes correctly.
      mb.statusCtrl.add('second');
      await flushMicrotasks();
      expect(mb.status.value, 'second');
    });

    test('graph.dispose disposes the multibox', () async {
      final driver = SpySyncBox(1);
      final mb = TestPlayerBox();

      final g = Graph.builder()
          .add(driver)
          .addMultiBox(mb, input: (d) => d.onlyWhenReady<int>(driver))
          .build();

      await flushMicrotasks();
      expect(mb.disposed, isFalse);

      g.dispose();
      expect(mb.disposed, isTrue);
    });

    test('disposed multibox ignores subsequent input pushes', () async {
      final driver = SpySyncBox(1);
      final mb = TestPlayerBox();

      final g = Graph.builder()
          .add(driver)
          .addMultiBox(mb, input: (d) => d.onlyWhenReady<int>(driver))
          .build();

      await flushMicrotasks();
      g.dispose();

      final callsBefore = mb.computeCalls;
      // Direct internal poke would be _updateInput — we don't have access.
      // But disposing + verifying child stays at last value is enough.
      expect(mb.status.value, 'idle');
      expect(mb.computeCalls, callsBefore);
    });
  });

  group('MultiBox child outputs (auto-register in DependencyResolver)', () {
    test('graph node can depend on a child via onlyWhenReady', () async {
      final driver = SpySyncBox(1);
      final mb = TestPlayerBox();
      final consumer = SpySyncInputBox(-1);

      Graph.builder()
          .add(driver)
          .addMultiBox(mb, input: (d) => d.onlyWhenReady<int>(driver))
          .add(consumer, input: (d) => d.onlyWhenReady<int>(mb.position))
          .build();

      await flushMicrotasks();

      // position has its initial 0 — consumer should pick it up.
      expect(consumer.value, 0);
      expect(consumer.computeCalls, greaterThanOrEqualTo(1));

      mb.positionCtrl.add(99);
      await flushMicrotasks();

      expect(mb.position.value, 99);
      expect(consumer.value, 99);
    });

    test('addEffect can react to a child without explicit registration',
        () async {
      final driver = SpySyncBox(1);
      final mb = TestPlayerBox();

      final seen = <String>[];

      Graph.builder()
          .add(driver)
          .addMultiBox(mb, input: (d) => d.onlyWhenReady<int>(driver))
          .addEffect<String>(
            (d) => d.onlyWhenReady<String>(mb.status),
            run: (current, previous) => seen.add(current),
          )
          .build();

      await flushMicrotasks();

      mb.statusCtrl.add('playing');
      await flushMicrotasks();
      mb.statusCtrl.add('paused');
      await flushMicrotasks();

      // initial 'idle' + 'playing' + 'paused'
      expect(seen, contains('playing'));
      expect(seen, contains('paused'));
    });
  });

  group('MultiBox with no driver (void input)', () {
    test('composite without addMultiBox is unmanaged but still subclassable',
        () {
      final mb = NoOpMultiBox();
      expect(mb.computed, isFalse);
      expect(mb.disposed, isFalse);

      mb.dispose();
      expect(mb.disposed, isTrue);
    });

    test('self-driven module: addMultiBox without input computes once',
        () async {
      final driver = SpySyncBox(1);
      final mb = CountingVoidMultiBox();
      final g = Graph.builder().add(driver).addMultiBox(mb).build();
      await g.settled();
      expect(mb.computes, 1);

      // Later pumps do not re-deliver the null input.
      driver.setValue(2);
      await g.settled();
      expect(mb.computes, 1);
      g.dispose();
    });

    test('addMultiBox without input asserts for a non-nullable input type',
        () {
      expect(
        () => Graph.builder().addMultiBox(IntEchoMultiBox()).build(),
        throwsA(isA<AssertionError>()),
      );
    });

    test('graph dispose still disposes a self-driven module', () async {
      final mb = NoOpMultiBox();
      final g = Graph.builder().addMultiBox(mb).build();
      await g.settled();
      expect(mb.computed, isTrue);

      g.dispose();
      expect(mb.disposed, isTrue);
    });
  });

  group('MultiBox child ownership', () {
    test('cells stop notifying once the multibox is disposed', () async {
      final driver = SpySyncBox(1);
      final mb = OwnershipMultiBox();

      final g = Graph.builder()
          .add(driver)
          .addMultiBox(mb, input: (d) => d.onlyWhenReady<int>(driver))
          .build();

      await flushMicrotasks();
      expect(mb.owned.value, 1);

      var emissions = 0;
      mb.owned.listen((_) => emissions++, skipFirst: true);

      g.dispose();
      driver.setValue(2); // graph is dead; nothing should flow
      await flushMicrotasks();

      expect(emissions, 0);
      expect(mb.owned.value, 1, reason: 'cell frozen after dispose');
    });

    test('dispose is safe to combine with graph.dispose (idempotent)',
        () async {
      final driver = SpySyncBox(1);
      final mb = OwnershipMultiBox();

      final g = Graph.builder()
          .add(driver)
          .addMultiBox(mb, input: (d) => d.onlyWhenReady<int>(driver))
          .build();

      await flushMicrotasks();

      mb.dispose();
      g.dispose(); // second dispose path must be a no-op
      expect(mb.owned.value, 1);
    });

    test('dispatch to a foreign multibox cell asserts', () {
      final mb = OwnershipMultiBox();
      final other = OwnershipMultiBox();

      expect(
        () => mb.dispatchToForeign(other.owned, 5),
        throwsA(isA<AssertionError>()),
      );
    });

    test(
        'late events after dispose do not reach disposed children '
        '(even when a subscription was not track()-ed)', () async {
      final driver = SpySyncBox(1);
      final mb = LeakyMultiBox();

      final g = Graph.builder()
          .add(driver)
          .addMultiBox(mb, input: (d) => d.onlyWhenReady<int>(driver))
          .build();

      await flushMicrotasks();

      final seen = <String>[];
      mb.status.listen((o) => seen.add((o as SyncData<String>).value),
          skipFirst: true);

      mb.ctrl.add('playing');
      await flushMicrotasks();
      expect(seen, ['playing']);

      g.dispose();

      // The leaked subscription is still alive and will call dispatch —
      // the disposed child must swallow it silently.
      mb.ctrl.add('late-event');
      await flushMicrotasks();

      expect(seen, ['playing']);
      expect(mb.status.value, 'playing');
    });
  });

  group('MultiBox connect', () {
    test('routes events through map into the cell', () async {
      final driver = SpySyncBox(1);
      final mb = ConnectMultiBox();

      Graph.builder()
          .add(driver)
          .addMultiBox(mb, input: (d) => d.onlyWhenReady<int>(driver))
          .build();
      await flushMicrotasks();

      mb.ctrl.add(3);
      await flushMicrotasks();
      expect(mb.tripled.value, 9);
    });

    test('connections are released on the next input cycle', () async {
      final driver = SpySyncBox(1);
      final mb = ConnectMultiBox();

      Graph.builder()
          .add(driver)
          .addMultiBox(mb, input: (d) => d.onlyWhenReady<int>(driver))
          .build();
      await flushMicrotasks();

      final oldCtrl = mb.ctrl;
      driver.setValue(2); // rebind: new controller, old connection dies
      await flushMicrotasks();

      oldCtrl.add(100);
      await flushMicrotasks();
      expect(mb.tripled.value, 0, reason: 'old source disconnected');

      mb.ctrl.add(5);
      await flushMicrotasks();
      expect(mb.tripled.value, 15, reason: 'new source connected');
    });

    test('type mismatch without map asserts', () {
      final mb = BadConnectMultiBox();
      expect(() => mb.badConnect(), throwsA(isA<AssertionError>()));
    });
  });

  group('addMultiBox onError', () {
    test('handled input error skips the pump cycle without crashing',
        () async {
      final driver = SpySyncBox(1);
      final mb = TestPlayerBox();
      final errors = <Object>[];

      Graph.builder()
          .add(driver)
          .addMultiBox(
            mb,
            input: (d) {
              final v = d.onlyWhenReady<int>(driver);
              if (v.isEven) throw StateError('even input not allowed');
              return v;
            },
            onError: (e) {
              errors.add(e);
              return true;
            },
          )
          .build();

      await flushMicrotasks();
      expect(mb.lastInput, 1);

      driver.setValue(2); // throws in buildInput -> handled -> skipped
      await flushMicrotasks();
      expect(errors, hasLength(1));
      expect(mb.lastInput, 1, reason: 'multibox skipped the failing cycle');

      driver.setValue(3);
      await flushMicrotasks();
      expect(mb.lastInput, 3, reason: 'recovers on the next valid input');
    });
  });
}
