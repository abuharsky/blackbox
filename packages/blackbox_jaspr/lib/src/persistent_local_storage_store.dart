import 'dart:convert';

import 'package:blackbox/blackbox.dart';
import 'package:meta/meta.dart';
import 'package:universal_web/web.dart' as web;

/// A synchronous [PersistentStore] backed by browser `localStorage`.
///
/// Outside the browser this store falls back to an in-memory map so SSR and
/// tests can create persistent boxes without additional setup.
class LocalStorageStore implements PersistentStore {
  LocalStorageStore._(this._backend, this._cache);

  factory LocalStorageStore() => instance;

  final _StorageBackend _backend;
  final Map<String, Object?> _cache;

  static LocalStorageStore? _instance;

  static const bool _isBrowser = bool.fromEnvironment(
    'dart.library.js_interop',
  );

  /// Initializes the shared store and registers it in [BlackboxPersistence].
  static Future<void> preload() async {
    BlackboxPersistence.init(instance);
  }

  /// Shared singleton instance.
  static LocalStorageStore get instance {
    final existing = _instance;
    if (existing != null) return existing;

    final backend = _isBrowser
        ? _BrowserLocalStorageBackend()
        : _MemoryStorageBackend();
    final cache = <String, Object?>{};

    for (final entry in backend.readAll().entries) {
      final decoded = _tryDecodeValue(entry.value);
      if (decoded case final value?) {
        cache[entry.key] = value;
      }
    }

    final created = LocalStorageStore._(backend, cache);
    _instance = created;
    return created;
  }

  @visibleForTesting
  static void resetForTesting() {
    _instance = null;
    BlackboxPersistence.reset();
  }

  @override
  Object? read(String key) {
    return _cache[key];
  }

  @override
  void write(String key, Object? value) {
    if (value == null) {
      delete(key);
      return;
    }

    _cache[key] = value;
    _backend.write(key, _encodeValue(value));
  }

  @override
  void delete(String key) {
    _cache.remove(key);
    _backend.delete(key);
  }

  static String _encodeValue(Object value) {
    final payload = switch (value) {
      int _ => {'type': 'int', 'value': value},
      double _ => {'type': 'double', 'value': value},
      bool _ => {'type': 'bool', 'value': value},
      String _ => {'type': 'string', 'value': value},
      List<String> _ => {'type': 'string_list', 'value': value},
      Map<String, dynamic> _ => {'type': 'json', 'value': value},
      _ => throw UnsupportedError(
        'LocalStorageStore supports only primitive values. '
        'Got ${value.runtimeType}',
      ),
    };

    return jsonEncode(payload);
  }

  static Object? _tryDecodeValue(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      return switch (decoded['type']) {
        'int' => decoded['value'] as int,
        'double' => (decoded['value'] as num).toDouble(),
        'bool' => decoded['value'] as bool,
        'string' => decoded['value'] as String,
        'string_list' => (decoded['value'] as List<dynamic>).cast<String>(),
        'json' =>
          (decoded['value'] as Map<dynamic, dynamic>).cast<String, dynamic>(),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }
}

abstract interface class _StorageBackend {
  Map<String, String> readAll();
  void write(String key, String value);
  void delete(String key);
}

final class _MemoryStorageBackend implements _StorageBackend {
  final Map<String, String> _values = <String, String>{};

  @override
  Map<String, String> readAll() => Map<String, String>.from(_values);

  @override
  void write(String key, String value) {
    _values[key] = value;
  }

  @override
  void delete(String key) {
    _values.remove(key);
  }
}

final class _BrowserLocalStorageBackend implements _StorageBackend {
  @override
  Map<String, String> readAll() {
    final result = <String, String>{};
    final storage = web.window.localStorage;

    for (var i = 0; i < storage.length; i++) {
      final key = storage.key(i);
      final value = key == null ? null : storage.getItem(key);
      if (key != null && value != null) {
        result[key] = value;
      }
    }

    return result;
  }

  @override
  void write(String key, String value) {
    web.window.localStorage.setItem(key, value);
  }

  @override
  void delete(String key) {
    web.window.localStorage.removeItem(key);
  }
}
