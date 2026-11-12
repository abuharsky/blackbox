import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:blackbox_jaspr/blackbox_jaspr.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_test/jaspr_test.dart';

final class CounterBox extends NoInputBox<int> {
  late final count = state(0);

  @override
  int compute() => count.value;
}

/// Not an observer: reads in build are a snapshot.
class PlainReader extends StatelessComponent {
  const PlainReader(this.box, {super.key});

  final CounterBox box;

  @override
  Component build(BuildContext context) => Component.text('${box.value}');
}

/// Takes the initial value once, in initState — a snapshot by design.
class InitReader extends StatefulComponent {
  const InitReader(this.box, {super.key});

  final CounterBox box;

  @override
  State<InitReader> createState() => _InitReaderState();
}

class _InitReaderState extends State<InitReader> {
  late int initial;

  @override
  void initState() {
    super.initState();
    initial = component.box.value;
  }

  @override
  Component build(BuildContext context) => Component.text('$initial');
}

void main() {
  late List<String> printed;

  /// Runs [body] with prints collected into [printed].
  Future<void> collect(FutureOr<void> Function() body) async {
    printed = [];
    BoxReadCheck.debugReset();
    await runZoned(
      () async => body(),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          if (line.startsWith('BoxReadCheck')) printed.add(line);
        },
      ),
    );
  }

  testComponents('a read in a plain component under an observer warns, once',
      (tester) async {
    final box = CounterBox();
    await collect(() {
      tester.pumpComponent(BoxReadCheck(
        child: BoxObserver(builder: (_) => PlainReader(box)),
      ));
    });
    expect(printed, hasLength(1));
    expect(printed.single, contains('CounterBox'));
    expect(printed.single, contains('PlainReader'));
  });

  testComponents('a read in a BoxObserver builder is tracked — silent',
      (tester) async {
    final box = CounterBox();
    await collect(() {
      tester.pumpComponent(BoxReadCheck(
        child: BoxObserver(builder: (_) => Component.text('${box.value}')),
      ));
    });
    expect(printed, isEmpty);
  });

  testComponents('an initial value in initState — silent', (tester) async {
    await collect(() {
      tester.pumpComponent(BoxReadCheck(child: InitReader(CounterBox())));
    });
    expect(printed, isEmpty);
  });

  testComponents('BoxHooks.untracked marks a deliberate snapshot — silent',
      (tester) async {
    final box = CounterBox();
    await collect(() {
      tester.pumpComponent(BoxReadCheck(
        child: Builder(
          builder: (_) =>
              Component.text('${BoxHooks.untracked(() => box.value)}'),
        ),
      ));
    });
    expect(printed, isEmpty);
  });

  testComponents('on the server nothing goes stale — silent', (tester) async {
    await collect(() {
      tester.pumpComponent(BoxReadCheck(child: PlainReader(CounterBox())));
    });
    expect(printed, isEmpty);
  }, isClient: false);

  testComponents('outside a build — silent', (tester) async {
    final box = CounterBox();
    await collect(() {
      tester.pumpComponent(const BoxReadCheck(child: Component.text('x')));
      expect(box.value, 0);
    });
    expect(printed, isEmpty);
  });
}
