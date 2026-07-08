import 'package:blackbox/blackbox.dart';
import 'package:blackbox_jaspr/blackbox_jaspr.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_test/jaspr_test.dart';

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

final class ProbeComponent extends StatelessComponent {
  const ProbeComponent(this.onBuild, {super.key});

  final void Function(BuildContext context) onBuild;

  @override
  Component build(BuildContext context) {
    onBuild(context);
    return Component.text('probe');
  }
}

void main() {
  testComponents('nested BoxProvider keeps parent boxes visible', (
    tester,
  ) async {
    final parentBox = ParentBox(1);
    final childBox = ChildBox(2);

    ParentBox? resolvedParent;
    ChildBox? resolvedChild;

    tester.pumpComponent(
      BoxProvider.single(
        box: parentBox,
        child: BoxProvider.single(
          box: childBox,
          child: ProbeComponent((context) {
            resolvedParent = context.box<ParentBox>();
            resolvedChild = context.box<ChildBox>();
          }),
        ),
      ),
    );

    expect(identical(resolvedParent, parentBox), isTrue);
    expect(identical(resolvedChild, childBox), isTrue);
  });

  testComponents('nested BoxProvider prefers the local box for same type', (
    tester,
  ) async {
    final parentBox = SharedBox(1);
    final childBox = SharedBox(2);

    SharedBox? resolved;

    tester.pumpComponent(
      BoxProvider.single(
        box: parentBox,
        child: BoxProvider.single(
          box: childBox,
          child: ProbeComponent((context) {
            resolved = context.box<SharedBox>();
          }),
        ),
      ),
    );

    expect(identical(resolved, childBox), isTrue);
  });

  testComponents(
      'BoxProvider.overrides resolves box by explicit type key', (tester) async {
    final mock = SharedBox(42);

    SharedBox? resolved;

    tester.pumpComponent(
      BoxProvider.overrides(
        overrides: [BoxOverride.of<SharedBox>(mock)],
        child: ProbeComponent((context) {
          resolved = context.box<SharedBox>();
        }),
      ),
    );

    expect(identical(resolved, mock), isTrue);
    expect(resolved!.value, 42);
  });

  testComponents(
      'BoxProvider.overrides registers box under parent type, not runtimeType',
      (tester) async {
    final override = _OverrideBox(99);

    SharedBox? resolved;

    tester.pumpComponent(
      BoxProvider.overrides(
        overrides: [BoxOverride.of<SharedBox>(override)],
        child: ProbeComponent((context) {
          resolved = context.box<SharedBox>();
        }),
      ),
    );

    expect(identical(resolved, override), isTrue);
    expect(resolved!.value, 99);
  });

  testComponents('BoxProvider.overrides supports multiple entries',
      (tester) async {
    final mockParent = ParentBox(10);
    final mockChild = ChildBox(20);

    ParentBox? resolvedParent;
    ChildBox? resolvedChild;

    tester.pumpComponent(
      BoxProvider.overrides(
        overrides: [
          BoxOverride.of<ParentBox>(mockParent),
          BoxOverride.of<ChildBox>(mockChild),
        ],
        child: ProbeComponent((context) {
          resolvedParent = context.box<ParentBox>();
          resolvedChild = context.box<ChildBox>();
        }),
      ),
    );

    expect(identical(resolvedParent, mockParent), isTrue);
    expect(identical(resolvedChild, mockChild), isTrue);
  });

  testComponents('provides a MultiBox composite through context.box', (
    tester,
  ) async {
    final player = _TestPlayerBox();
    _TestPlayerBox? resolved;
    String? statusSeen;

    tester.pumpComponent(
      BoxProvider.multi(
        boxes: [player],
        child: ProbeComponent((context) {
          resolved = context.box<_TestPlayerBox>();
          statusSeen = resolved!.status.value;
        }),
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
