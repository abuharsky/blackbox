import 'package:blackbox/blackbox.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class CounterBox extends NoInputBox<int> {
  late final count = state(0);

  @override
  int compute() => count.value;

  void inc() => count.value++;
}

/// Not an observer: reads in build are a snapshot.
class PlainReader extends StatelessWidget {
  const PlainReader(this.box, {super.key});

  final CounterBox box;

  @override
  Widget build(BuildContext context) =>
      Text('${box.value}', textDirection: TextDirection.ltr);
}

/// Takes the initial value once, in initState — a snapshot by design.
class InitReader extends StatefulWidget {
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
    initial = widget.box.value;
  }

  @override
  Widget build(BuildContext context) =>
      Text('$initial', textDirection: TextDirection.ltr);
}

void main() {
  late List<String> printed;

  /// testWidgets with BoxReadCheck warnings collected into [printed].
  /// debugPrint must be back before the test body ends — the binding
  /// checks it before any tearDown runs.
  void checkWidgets(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      printed = [];
      BoxReadCheck.install();
      BoxReadCheck.debugReset();
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null && message.startsWith('BoxReadCheck')) {
          printed.add(message);
        }
      };
      try {
        await body(tester);
      } finally {
        debugPrint = original;
      }
    });
  }

  checkWidgets('a read in a plain build warns, once per site', (tester) async {
    final box = CounterBox();
    await tester.pumpWidget(PlainReader(box));
    expect(printed, hasLength(1));
    expect(printed.single, contains('CounterBox'));
    expect(printed.single, contains('box_read_check_test.dart'));

    // The same site again — no second warning.
    await tester.pumpWidget(PlainReader(box, key: UniqueKey()));
    expect(printed, hasLength(1));
  });

  checkWidgets('a read in a BoxObserver builder is tracked — silent',
      (tester) async {
    final box = CounterBox();
    await tester.pumpWidget(BoxObserver(
      builder: (_) => Text('${box.value}', textDirection: TextDirection.ltr),
    ));
    expect(printed, isEmpty);
  });

  checkWidgets('a LayoutBuilder inside a BoxObserver runs later — warns',
      (tester) async {
    final box = CounterBox();
    final other = CounterBox();
    await tester.pumpWidget(BoxObserver(
      builder: (_) {
        other.value; // the observer itself tracks something
        return LayoutBuilder(
          builder: (_, __) =>
              Text('${box.value}', textDirection: TextDirection.ltr),
        );
      },
    ));
    expect(printed, hasLength(1));
  });

  checkWidgets('BoxHooks.untracked marks a deliberate snapshot — silent',
      (tester) async {
    final box = CounterBox();
    await tester.pumpWidget(Builder(
      builder: (_) => Text('${BoxHooks.untracked(() => box.value)}',
          textDirection: TextDirection.ltr),
    ));
    expect(printed, isEmpty);
  });

  checkWidgets('reads outside build (callbacks, actions) — silent',
      (tester) async {
    final box = CounterBox();
    await tester.pumpWidget(const SizedBox.shrink());
    box.inc();
    expect(box.value, 1);
    expect(printed, isEmpty);
  });

  checkWidgets('an initial value in initState is a snapshot by design — silent',
      (tester) async {
    await tester.pumpWidget(InitReader(CounterBox()));
    expect(printed, isEmpty);
  });

  checkWidgets('enabled = false silences it', (tester) async {
    BoxReadCheck.enabled = false;
    addTearDown(() => BoxReadCheck.enabled = true);
    await tester.pumpWidget(PlainReader(CounterBox()));
    expect(printed, isEmpty);
  });
}
