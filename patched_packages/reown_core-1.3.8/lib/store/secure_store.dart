import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:reown_core/store/i_store.dart';
import 'package:reown_core/utils/constants.dart';
import 'package:reown_core/utils/errors.dart';

class SecureStore implements IStore<Map<String, dynamic>> {
  /// Marker persisted in the fallback storage once secure storage has failed,
  /// so the fallback keeps being used on subsequent launches even when secure
  /// reads succeed again (e.g. macOS keychain reads work but writes fail).
  static const String _fallbackFlagKey = 'secure_store_fallback_mode';

  late final FlutterSecureStorage _secureStorage;
  late final IStore<Map<String, dynamic>> _fallbackStorage;
  bool _initialized = false;
  bool _useFallbackStorage = false;

  final Map<String, Map<String, dynamic>> _map;

  @override
  Map<String, Map<String, dynamic>> get map => _map;

  @override
  List<String> get keys => map.keys.toList();

  @override
  List<Map<String, dynamic>> get values => map.values.toList();

  @override
  String get storagePrefix => ReownConstants.CORE_STORAGE_PREFIX;

  SecureStore({
    Map<String, Map<String, dynamic>>? defaultValue,
    required IStore<Map<String, dynamic>> fallbackStorage,
    FlutterSecureStorage? secureStorage,
  }) : _map = defaultValue ?? {},
       _fallbackStorage = fallbackStorage,
       _injectedSecureStorage = secureStorage;

  final FlutterSecureStorage? _injectedSecureStorage;

  @override
  Future<void> init() async {
    if (_initialized) {
      return;
    }

    try {
      // Try secure storage first
      _secureStorage = _injectedSecureStorage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

      if (_fallbackStorage.has(_fallbackFlagKey)) {
        // A previous launch already switched to the fallback storage; keep
        // using it instead of treating possibly stale secure data as
        // authoritative.
        _useFallbackStorage = true;
        await _restoreFromFallback();
      } else {
        await restore();
      }
    } catch (e) {
      // Fall back to regular storage if secure storage fails
      _useFallbackStorage = true;
      await _persistFallbackFlag();
      // Try to restore from fallback storage
      await _restoreFromFallback();
    }

    _initialized = true;
  }

  @override
  Map<String, dynamic>? get(String key) {
    _checkInitialized();

    if (_useFallbackStorage) {
      return _fallbackStorage.get(key);
    }

    final String keyWithPrefix = _addPrefix(key);
    if (_map.containsKey(keyWithPrefix)) {
      return _map[keyWithPrefix];
    }

    // For secure storage, we can't easily read all keys at once
    // So we'll return null if not in memory, similar to SharedPrefsStores behavior
    return null;
  }

  @override
  bool has(String key) {
    _checkInitialized();

    if (_useFallbackStorage) {
      return _fallbackStorage.has(key);
    }

    final String keyWithPrefix = _addPrefix(key);

    // Only check memory for secure storage (can't check secure storage synchronously)
    return _map.containsKey(keyWithPrefix);
  }

  @override
  List<Map<String, dynamic>> getAll() {
    _checkInitialized();

    if (_useFallbackStorage) {
      return _fallbackStorage.getAll().cast<Map<String, dynamic>>();
    }

    return values;
  }

  @override
  Future<void> set(String key, Map<String, dynamic> value) async {
    _checkInitialized();

    final String keyWithPrefix = _addPrefix(key);
    _map[keyWithPrefix] = value;

    if (_useFallbackStorage) {
      await _fallbackStorage.set(key, value);
    } else {
      try {
        final stringValue = jsonEncode(value);
        await _secureStorage.write(key: keyWithPrefix, value: stringValue);
      } catch (e) {
        await _switchToFallbackStorage(e);
      }
    }
  }

  @override
  Future<void> update(String key, Map<String, dynamic> value) async {
    _checkInitialized();

    final String keyWithPrefix = _addPrefix(key);
    if (!map.containsKey(keyWithPrefix)) {
      throw Errors.getInternalError(Errors.NO_MATCHING_KEY);
    } else {
      _map[keyWithPrefix] = value;
      if (_useFallbackStorage) {
        await _fallbackStorage.update(key, value);
      } else {
        try {
          final stringValue = jsonEncode(value);
          await _secureStorage.write(key: keyWithPrefix, value: stringValue);
        } catch (e) {
          await _switchToFallbackStorage(e);
        }
      }
    }
  }

  @override
  Future<void> delete(String key) async {
    _checkInitialized();

    final String keyWithPrefix = _addPrefix(key);
    _map.remove(keyWithPrefix);

    if (_useFallbackStorage) {
      await _fallbackStorage.delete(key);
    } else {
      try {
        await _secureStorage.delete(key: keyWithPrefix);
      } catch (e) {
        await _switchToFallbackStorage(e);
        await _fallbackStorage.delete(key);
      }
    }
  }

  @override
  Future<void> deleteAll() async {
    _checkInitialized();

    if (_useFallbackStorage) {
      await _fallbackStorage.deleteAll();
    } else {
      try {
        // Get all keys from secure storage and delete them
        final allKeys = await _secureStorage.readAll();
        for (final key in allKeys.keys) {
          if (key.startsWith(storagePrefix)) {
            await _secureStorage.delete(key: key);
          }
        }
      } catch (e) {
        await _switchToFallbackStorage(e);
        await _fallbackStorage.deleteAll();
      }
    }

    _map.clear();
  }

  Future<void> restore() async {
    if (_useFallbackStorage) return;

    try {
      // Get all keys from secure storage
      final allKeys = await _secureStorage.readAll();

      // Restore data to memory map
      for (final entry in allKeys.entries) {
        final key = entry.key;
        final value = entry.value;

        if (key.startsWith(storagePrefix)) {
          try {
            final decodedValue = jsonDecode(value);
            _map[key] = decodedValue;
          } catch (e) {
            // Skip corrupted data
            debugPrint(
              'Warning: Failed to decode secure storage value for key $key: $e',
            );
          }
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _restoreFromFallback() async {
    try {
      for (final key in _fallbackStorage.keys) {
        if (!key.startsWith(storagePrefix)) {
          continue;
        }
        if (key == _addPrefix(_fallbackFlagKey)) {
          continue;
        }

        final value = _fallbackStorage.get(_removePrefix(key));
        if (value != null) {
          _map[key] = value;
        }
      }
    } catch (e) {
      debugPrint('Warning: Failed to restore from fallback storage: $e');
    }
  }

  Future<void> _switchToFallbackStorage(Object error) async {
    if (_useFallbackStorage) {
      return;
    }

    debugPrint(
      'Warning: Secure storage failed, using fallback storage: $error',
    );
    _useFallbackStorage = true;
    await _persistFallbackFlag();

    for (final entry in _map.entries) {
      await _setFallbackValue(_removePrefix(entry.key), entry.value);
    }
  }

  Future<void> _setFallbackValue(String key, Map<String, dynamic> value) async {
    await _fallbackStorage.set(key, value);
  }

  Future<void> _persistFallbackFlag() async {
    try {
      await _fallbackStorage.set(_fallbackFlagKey, {'enabled': true});
    } catch (e) {
      debugPrint(
        'Warning: Failed to persist secure storage fallback flag: $e',
      );
    }
  }

  String _addPrefix(String key) {
    return '$storagePrefix$key';
  }

  String _removePrefix(String key) {
    return key.startsWith(storagePrefix)
        ? key.substring(storagePrefix.length)
        : key;
  }

  void _checkInitialized() {
    if (!_initialized) {
      throw Errors.getInternalError(Errors.NOT_INITIALIZED);
    }
  }
}
