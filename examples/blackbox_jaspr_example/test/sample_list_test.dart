import 'package:blackbox_jaspr/blackbox_jaspr.dart';
import 'package:blackbox_jaspr_example/sample_list.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_test/jaspr_test.dart';

void main() {
  setUp(() async {
    LocalStorageStore.resetForTesting();
    await LocalStorageStore.preload();
  });

  testComponents('renders counter demo by default', (tester) async {
    tester.pumpComponent(const SampleList());

    expect(find.text('Simple counter chain'), findsOneComponent);
    expect(find.text('Step (sync)'), findsOneComponent);
  });

  testComponents('counter step button updates observed sync output', (
    tester,
  ) async {
    tester.pumpComponent(const SampleList());

    await tester.click(find.componentWithText(button, 'step +'));

    expect(find.text('value: 2'), findsOneComponent);
  });

  testComponents('switches to account demo', (tester) async {
    tester.pumpComponent(const SampleList());

    await tester.click(
      find.componentWithText(button, 'Account + Auth + Profile (Async)'),
    );

    expect(find.text('Account + auth + profile flow'), findsOneComponent);
    expect(find.text('Services loader'), findsOneComponent);
  });
}
