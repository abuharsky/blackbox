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
}
