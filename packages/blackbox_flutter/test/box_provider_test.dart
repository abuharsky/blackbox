import 'package:blackbox/blackbox.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class ParentBox extends NoInputBox<int> {
  ParentBox(this.seed);

  final int seed;

  @override
  int compute(int? previous) => seed;
}

final class ChildBox extends NoInputBox<int> {
  ChildBox(this.seed);

  final int seed;

  @override
  int compute(int? previous) => seed;
}

final class SharedBox extends NoInputBox<int> {
  SharedBox(this.seed);

  final int seed;

  @override
  int compute(int? previous) => seed;
}

void main() {
  testWidgets('nested BoxProvider keeps parent boxes visible', (tester) async {
    final parentBox = ParentBox(1);
    final childBox = ChildBox(2);

    ParentBox? resolvedParent;
    ChildBox? resolvedChild;

    await tester.pumpWidget(
      BoxProvider.single(
        box: parentBox,
        child: BoxProvider.single(
          box: childBox,
          child: Builder(
            builder: (context) {
              resolvedParent = context.box<ParentBox>();
              resolvedChild = context.box<ChildBox>();
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(identical(resolvedParent, parentBox), isTrue);
    expect(identical(resolvedChild, childBox), isTrue);
  });

  testWidgets('nested BoxProvider prefers the local box for same type',
      (tester) async {
    final parentBox = SharedBox(1);
    final childBox = SharedBox(2);

    SharedBox? resolved;

    await tester.pumpWidget(
      BoxProvider.single(
        box: parentBox,
        child: BoxProvider.single(
          box: childBox,
          child: Builder(
            builder: (context) {
              resolved = context.box<SharedBox>();
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(identical(resolved, childBox), isTrue);
  });

  testWidgets('BoxProvider.overrides resolves box by explicit type key',
      (tester) async {
    final mock = SharedBox(42);

    SharedBox? resolved;

    await tester.pumpWidget(
      BoxProvider.overrides(
        overrides: [BoxOverride.of<SharedBox>(mock)],
        child: Builder(
          builder: (context) {
            resolved = context.box<SharedBox>();
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(identical(resolved, mock), isTrue);
    expect(resolved!.value, 42);
  });

  testWidgets(
      'BoxProvider.overrides registers box under parent type, not runtimeType',
      (tester) async {
    // OverrideBox extends SharedBox — without overrides, context.box<SharedBox>()
    // would fail because it would be stored under OverrideBox, not SharedBox.
    final override = _OverrideBox(99);

    SharedBox? resolved;

    await tester.pumpWidget(
      BoxProvider.overrides(
        overrides: [BoxOverride.of<SharedBox>(override)],
        child: Builder(
          builder: (context) {
            resolved = context.box<SharedBox>();
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(identical(resolved, override), isTrue);
    expect(resolved!.value, 99);
  });

  testWidgets('BoxProvider.overrides supports multiple entries', (tester) async {
    final mockParent = ParentBox(10);
    final mockChild = ChildBox(20);

    ParentBox? resolvedParent;
    ChildBox? resolvedChild;

    await tester.pumpWidget(
      BoxProvider.overrides(
        overrides: [
          BoxOverride.of<ParentBox>(mockParent),
          BoxOverride.of<ChildBox>(mockChild),
        ],
        child: Builder(
          builder: (context) {
            resolvedParent = context.box<ParentBox>();
            resolvedChild = context.box<ChildBox>();
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(identical(resolvedParent, mockParent), isTrue);
    expect(identical(resolvedChild, mockChild), isTrue);
  });

  testWidgets('provides a MultiBox composite through context.box', (
    tester,
  ) async {
    final player = _TestPlayerBox();
    _TestPlayerBox? resolved;
    String? statusSeen;

    await tester.pumpWidget(
      BoxProvider.multi(
        boxes: [player],
        child: Builder(
          builder: (context) {
            resolved = context.box<_TestPlayerBox>();
            statusSeen = resolved!.status.value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(identical(resolved, player), isTrue);
    expect(statusSeen, 'idle');
    player.dispose();
  });
}

final class _TestPlayerBox extends MultiBox<int> {
  late final status = child('idle');

  @override
  void compute(int input, int? previous) => dispatch(status, 'ch\$input');
}

final class _OverrideBox extends SharedBox {
  _OverrideBox(super.seed);
}
