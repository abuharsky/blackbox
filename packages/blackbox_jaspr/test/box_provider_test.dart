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
}
