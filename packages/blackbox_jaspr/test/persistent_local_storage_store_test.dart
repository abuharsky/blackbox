import 'package:blackbox/blackbox.dart';
import 'package:blackbox_jaspr/blackbox_jaspr.dart';
import 'package:jaspr_test/jaspr_test.dart';

void main() {
  setUp(() {
    LocalStorageStore.resetForTesting();
  });

  test(
    'LocalStorageStore.preload registers the global Blackbox store',
    () async {
      await LocalStorageStore.preload();

      expect(
        identical(
          BlackboxPersistence.requireStore(),
          LocalStorageStore.instance,
        ),
        isTrue,
      );
    },
  );

  test('LocalStorageStore persists primitive values synchronously', () {
    final store = LocalStorageStore();
    final prefix = 'local-storage-store-test';

    store.write('$prefix-int', 1);
    store.write('$prefix-double', 1.5);
    store.write('$prefix-bool', true);
    store.write('$prefix-string', 'value');
    store.write('$prefix-list', <String>['a', 'b']);

    expect(store.read('$prefix-int'), 1);
    expect(store.read('$prefix-double'), 1.5);
    expect(store.read('$prefix-bool'), true);
    expect(store.read('$prefix-string'), 'value');
    expect(store.read('$prefix-list'), <String>['a', 'b']);

    store.delete('$prefix-int');
    expect(store.read('$prefix-int'), isNull);
  });

  test('LocalStorageStore persists json maps', () {
    final store = LocalStorageStore();
    final prefix = 'local-storage-store-test';

    store.write('$prefix-map', <String, dynamic>{'v': 1, 'ts': 'now'});

    expect(store.read('$prefix-map'), <String, dynamic>{'v': 1, 'ts': 'now'});
  });

  test('LocalStorageStore rejects unsupported values', () {
    final store = LocalStorageStore();

    expect(
      () => store.write('unsupported', Object()),
      throwsUnsupportedError,
    );
  });
}
