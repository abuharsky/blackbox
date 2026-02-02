import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('StateObserver', () {
    test('sync source overrides initial immediately', () {
      final src = SpySyncBox(1);

      final flow = StateObserverBuilder<String>()
          .on<int>(src, (v) => 'v=$v')
          .build(initial: 'init');

      final seen = <String>[];
      final cancel = flow.listen(seen.add);

      expect(seen, ['v=1']);

      cancel();
    });

    test('sync output changes update flow state', () {
      final src = SpySyncBox(1);

      final flow = StateObserverBuilder<String>()
          .on<int>(src, (v) => 'v=$v')
          .build(initial: 'init');

      final seen = <String>[];
      final cancel = flow.listen(seen.add);

      src.setValue(2);
      src.setValue(3);

      expect(seen, ['v=1', 'v=2', 'v=3'],
          reason:
              'Flow listens to source and emits mapped values; includes first sync value');

      cancel();
    });

    test('mapper can return null to ignore updates', () {
      final src = SpySyncBox(1);

      final flow = StateObserverBuilder<int>()
          .on<int>(src, (v) => v.isEven ? v : null)
          .build(initial: 0);

      final seen = <int>[];
      final cancel = flow.listen(seen.add);

      // initial sync output is 1 => ignored
      expect(seen, [0]);

      src.setValue(2);
      src.setValue(3);
      src.setValue(4);

      expect(seen, [0, 2, 4]);

      cancel();
    });

    test('async loading does not update flow; async data does', () async {
      final src = ControlledAsyncInputBox(1);

      final flow = StateObserverBuilder<String>()
          .on<int>(src, (v) => 'v=$v')
          .build(initial: 'init');

      final seen = <String>[];
      final cancel = flow.listen(seen.add);

      // No async data yet.
      expect(seen, ['init']);

      src.completerFor(1).complete(10);
      await Future<void>.delayed(Duration.zero);

      expect(seen.last, 'v=10');

      cancel();
    });

    test('flow supports re-entrant updates in listener (queue behavior)', () {
      final src = SpySyncBox(1);

      final flow =
          StateObserverBuilder<int>().on<int>(src, (v) => v).build(initial: 0);

      var bumped = false;
      final seen = <int>[];
      final cancel = flow.listen((s) {
        seen.add(s);
        // On first observed mapped value 1, trigger another update.
        if (s == 1 && !bumped) {
          bumped = true;
          src.setValue(2);
        }
      });

      // When constructed, Flow listens to src and enqueues update for value=1.
      // The listener then triggers value=2. Both must be delivered.
      expect(seen.contains(1), isTrue);
      expect(seen.contains(2), isTrue);

      cancel();
    });

    test('cancel stops further flow emissions', () {
      final src = SpySyncBox(1);

      final flow = StateObserverBuilder<String>()
          .on<int>(src, (v) => 'v=$v')
          .build(initial: 'init');

      final seen = <String>[];
      final cancel = flow.listen(seen.add);

      cancel();
      src.setValue(2);

      // might have already emitted v=1 at build time due to immediate listen callbacks,
      // but must not emit v=2 after cancel.
      expect(seen.contains('v=2'), isFalse);
    });
  });
}
