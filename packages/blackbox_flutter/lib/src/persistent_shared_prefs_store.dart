import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:blackbox/blackbox.dart';
import 'package:meta/meta.dart';

class SharedPrefsStore implements PersistentStore {
  SharedPrefsStore._(this._prefs, this._cache);

  factory SharedPrefsStore() => instance;

  final SharedPreferences _prefs;
  final Map<String, Object?> _cache;

  static SharedPrefsStore? _instance;

  /// Must be called once on app startup.
  static Future<void> preload() async {
    final existing = _instance;
    if (existing != null) {
      BlackboxPersistence.init(existing);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final cache = <String, Object?>{};

    for (final key in prefs.getKeys()) {
      cache[key] = _decodePrefsValue(prefs.get(key));
    }

    final store = SharedPrefsStore._(prefs, cache);
    _instance = store;
    BlackboxPersistence.init(store);
  }

  @visibleForTesting
  static void resetForTesting() {
    _instance = null;
    BlackboxPersistence.reset();
  }

  /// Sync access after preload.
  static SharedPrefsStore get instance {
    final inst = _instance;
    if (inst == null) {
      throw StateError(
        'SharedPrefsStore is not initialized. '
        'Call SharedPrefsStore.preload() before using SharedPrefsStore.',
      );
    }
    return inst;
  }

  @override
  Object? read(String key) {
    return _cache[key];
  }

  @override
  void write(String key, Object? value) {
    _cache[key] = value;
    _writeToPrefs(key, value);
  }

  @override
  void delete(String key) {
    _cache.remove(key);
    _prefs.remove(key);
  }

  void _writeToPrefs(String key, Object? value) {
    if (value == null) {
      _prefs.remove(key);
    } else if (value is Map<String, dynamic>) {
      _prefs.setString(key, jsonEncode({'type': 'json', 'value': value}));
    } else if (value is Map<Object?, Object?>) {
      _prefs.setString(
        key,
        jsonEncode({
          'type': 'json',
          'value': value.map((key, value) => MapEntry(key.toString(), value)),
        }),
      );
    } else if (value is int) {
      _prefs.setInt(key, value);
    } else if (value is double) {
      _prefs.setDouble(key, value);
    } else if (value is bool) {
      _prefs.setBool(key, value);
    } else if (value is String) {
      _prefs.setString(key, value);
    } else if (value is List<String>) {
      _prefs.setStringList(key, value);
    } else {
      throw UnsupportedError(
        'SharedPrefsStore supports only primitive values. '
        'Got ${value.runtimeType}',
      );
    }
  }

  static Object? _decodePrefsValue(Object? stored) {
    if (stored is! String) return stored;

    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map<String, dynamic>) return stored;
      if (!decoded.containsKey('type') || !decoded.containsKey('value')) {
        return stored;
      }

      return switch (decoded['type']) {
        'json' => decoded['value'],
        _ => stored,
      };
    } catch (_) {
      return stored;
    }
  }
}
