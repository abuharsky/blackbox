import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

final class SourceBox extends NoInputBox<int> {
  late final _v = state(1);
  @override
  int compute() => _v.value;
  void set(int next) => _v.value = next;
}

final class MirrorBox extends Box<int, int> {
  MirrorBox.late() : super.late();
  @override
  int compute(int input) => input;
}

void main() {
  group('graph ownership on dispose', () {
    test('disposing a graph does not kill a foreign box it read lazily',
        () async {
      // Graph A owns the source.
      final source = SourceBox();
      final a = Graph.builder().add(source).build();

      // Graph B reads A's box via onlyWhenReady — lazily registered, not owned.
      final mirror = MirrorBox.late();
      final b = Graph.builder()
          .add(mirror, input: (d) => d.onlyWhenReady(source))
          .build();
      await b.settled();
      expect(mirror.value, 1);

      b.dispose();

      // The foreign source must still be alive: its button works and
      // its own graph keeps pumping.
      source.set(5);
      await a.settled();
      expect(source.value, 5, reason: 'foreign graph must not dispose it');

      a.dispose();
      source.set(9);
      expect(source.value, 5, reason: 'the owner graph does dispose it');
    });

    test('declared boxes are still disposed by their own graph', () async {
      final source = SourceBox();
      final g = Graph.builder().add(source).build();
      await g.settled();

      g.dispose();
      source.set(3);
      expect(source.value, 1, reason: 'output frozen after owner dispose');
    });
  });

  group('one declarer per box', () {
    test('declaring a box on two live graphs throws loudly', () {
      final shared = SourceBox();
      final a = Graph.builder().add(shared).build(start: false);

      expect(
        () => Graph.builder().add(shared).build(start: false),
        throwsStateError,
      );
      a.dispose();
    });

    test('declaring the same box twice on one graph throws', () {
      final box = SourceBox();
      expect(
        () => Graph.builder().add(box).add(box).build(start: false),
        throwsStateError,
      );
    });

    test('re-declaring after the previous owner is disposed is legal', () {
      final box = SourceBox();
      final a = Graph.builder().add(box).build(start: false);
      a.dispose();

      final b = Graph.builder().add(box).build(start: false);
      b.dispose();
    });

    test('toMermaid draws borrowed sources dashed, owned ones solid',
        () async {
      final shared = SourceBox();
      final owner = Graph.builder().add(shared).build();

      final mirror = MirrorBox.late();
      final reader = Graph.builder()
          .add(mirror, input: (d) => d.onlyWhenReady(shared))
          .build();
      await reader.settled();

      final map = reader.toMermaid();
      expect(map, contains('SourceBox --> MirrorBox'));
      expect(map, contains('style SourceBox stroke-dasharray: 5 5'),
          reason: 'borrowed source is dashed');
      expect(map, isNot(contains('style MirrorBox stroke-dasharray')),
          reason: 'declared box stays solid');

      reader.dispose();
      owner.dispose();
    });

    test('reading a foreign box via onlyWhenReady is not a declaration',
        () async {
      final shared = SourceBox();
      final owner = Graph.builder().add(shared).build();

      final mirror = MirrorBox.late();
      final reader = Graph.builder()
          .add(mirror, input: (d) => d.onlyWhenReady(shared))
          .build();
      await reader.settled();
      expect(mirror.value, 1);

      reader.dispose();
      owner.dispose();
    });
  });
}
