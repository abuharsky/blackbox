import 'package:blackbox/blackbox.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _PersistedCounterBox extends NoInputBox<int>
    with Persisted<void, int> {
  int _value;

  _PersistedCounterBox({int initial = 0}) : _value = initial;

  @override
  String persistKeyFor(void _) => 'counter';

  @override
  void onFirstCompute(void _, int? previous) {
    if (previous != null) _value = previous;
  }

  @override
  int compute(int? previous) => _value;

  void setValue(int value) => action(() => _value = value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(SharedPrefsStore.resetForTesting);
  tearDown(SharedPrefsStore.resetForTesting);

  test('preload registers the global Blackbox store', () async {
    SharedPreferences.setMockInitialValues({});
    await SharedPrefsStore.preload();

    expect(
      identical(BlackboxPersistence.requireStore(), SharedPrefsStore.instance),
      isTrue,
    );
  });

  test('persists primitive values synchronously', () async {
    SharedPreferences.setMockInitialValues({});
    await SharedPrefsStore.preload();
    final store = SharedPrefsStore.instance;

    store.write('int', 1);
    store.write('double', 1.5);
    store.write('bool', true);
    store.write('string', 'value');
    store.write('list', <String>['a', 'b']);

    expect(store.read('int'), 1);
    expect(store.read('double'), 1.5);
    expect(store.read('bool'), true);
    expect(store.read('string'), 'value');
    expect(store.read('list'), <String>['a', 'b']);

    store.delete('int');
    expect(store.read('int'), isNull);
  });

  test('persists envelope maps and decodes them after a restart', () async {
    SharedPreferences.setMockInitialValues({});
    await SharedPrefsStore.preload();

    SharedPrefsStore.instance.write('user', {'v': 42, 'ts': 123});
    expect(SharedPrefsStore.instance.read('user'), {'v': 42, 'ts': 123});

    // Simulate app restart: prefs backend survives, our caches don't.
    SharedPrefsStore.resetForTesting();
    await SharedPrefsStore.preload();

    expect(SharedPrefsStore.instance.read('user'), {'v': 42, 'ts': 123});
  });

  test('reads legacy raw values written before the envelope format',
      () async {
    SharedPreferences.setMockInitialValues({
      'counter': 5,
      'name': 'plain string',
    });
    await SharedPrefsStore.preload();

    expect(SharedPrefsStore.instance.read('counter'), 5);
    expect(SharedPrefsStore.instance.read('name'), 'plain string');
  });

  test('a plain string that happens to be JSON stays a string', () async {
    SharedPreferences.setMockInitialValues({
      'jsonish': '{"some": "object"}',
    });
    await SharedPrefsStore.preload();

    expect(SharedPrefsStore.instance.read('jsonish'), '{"some": "object"}');
  });

  test('Persisted box saves and restores across a restart', () async {
    SharedPreferences.setMockInitialValues({});
    await SharedPrefsStore.preload();

    final box = _PersistedCounterBox();
    box.setValue(9);

    SharedPrefsStore.resetForTesting();
    await SharedPrefsStore.preload();

    final restored = _PersistedCounterBox();
    expect(restored.value, 9);
  });
}
