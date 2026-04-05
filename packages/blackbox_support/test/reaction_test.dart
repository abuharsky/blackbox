import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:blackbox_support/blackbox_support.dart';
import 'package:test/test.dart';

final class _CounterBox extends NoInputBox<int> {
  _CounterBox(this._value) : super(initialValue: _value);

  int _value;

  void setValue(int value) {
    action(() {
      _value = value;
    });
  }

  @override
  int compute(int? previous) => _value;
}

final class _LateinitBox extends Box<int, int> {
  _LateinitBox() : super.lateinit();

  @override
  int compute(int input, int? previous) => input;
}

final class _QueueScheduler implements ReactionScheduler {
  final List<ReactionTask> queue = <ReactionTask>[];

  @override
  void schedule(ReactionTask task) {
    queue.add(task);
  }

  void flush() {
    while (queue.isNotEmpty) {
      queue.removeAt(0)();
    }
  }
}

void main() {
  test('Reaction tracks reads and invalidates once per scheduled flush', () {
    final source = _CounterBox(1);
    final scheduler = _QueueScheduler();
    var invalidations = 0;
    final reaction = Reaction(
      invalidate: () => invalidations++,
      scheduler: scheduler,
    );

    reaction.track(() {
      expect(source.value, 1);
      expect(source.value, 1);
    });

    source.setValue(2);
    source.setValue(3);

    expect(invalidations, 0);
    expect(scheduler.queue, hasLength(1));

    scheduler.flush();

    expect(invalidations, 1);

    reaction.dispose();
  });

  test('Reaction clears stale dependencies between track calls', () {
    final left = _CounterBox(1);
    final right = _CounterBox(10);
    final scheduler = _QueueScheduler();
    var invalidations = 0;
    final reaction = Reaction(
      invalidate: () => invalidations++,
      scheduler: scheduler,
    );

    reaction.track(() => left.value);
    reaction.track(() => right.value);

    left.setValue(2);
    scheduler.flush();
    expect(invalidations, 0);

    right.setValue(11);
    scheduler.flush();
    expect(invalidations, 1);

    reaction.dispose();
  });

  test('Reaction schedules rebuild when lateinit box is not ready yet', () {
    final box = _LateinitBox();
    final scheduler = _QueueScheduler();
    var invalidations = 0;
    final reaction = Reaction(
      invalidate: () => invalidations++,
      scheduler: scheduler,
    );

    // First track: box is not initialized, listen() throws.
    // Reaction should catch and schedule invalidation.
    reaction.track(() {
      try {
        box.value;
      } catch (_) {
        // Builder handles the error (renders fallback, etc.)
      }
    });

    // Reaction scheduled a rebuild because of the deferred source.
    expect(scheduler.queue, hasLength(1));

    // Now initialize the box (simulating graph pump).
    updateInputForTest(box, 42);

    // Flush the scheduled invalidation.
    scheduler.flush();
    expect(invalidations, 1);

    // Second track: box is now ready, subscription succeeds.
    reaction.track(() => box.value);

    // Mutate — Reaction should be subscribed now.
    updateInputForTest(box, 99);
    scheduler.flush();
    expect(invalidations, 2);

    reaction.dispose();
  });

  test('MicrotaskReactionScheduler runs queued invalidation asynchronously',
      () async {
    final source = _CounterBox(1);
    final completer = Completer<void>();
    final reaction = Reaction(
      invalidate: completer.complete,
      scheduler: const MicrotaskReactionScheduler(),
    );

    reaction.track(() => source.value);
    source.setValue(2);

    await completer.future;
    reaction.dispose();
  });
}
