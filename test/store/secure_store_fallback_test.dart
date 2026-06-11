import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reown_core/store/i_store.dart';
import 'package:reown_core/store/secure_store.dart';
import 'package:reown_core/utils/constants.dart';

/// In-memory stand-in for SharedPrefsStores: keys are stored with the core
/// storage prefix internally, public API takes unprefixed keys.
class _MemoryStore implements IStore<Map<String, dynamic>> {
  final Map<String, Map<String, dynamic>> _data = {};

  @override
  Map<String, Map<String, dynamic>> get map => _data;

  @override
  List<String> get keys => _data.keys.toList();

  @override
  List<Map<String, dynamic>> get values => _data.values.toList();

  @override
  String get storagePrefix => ReownConstants.CORE_STORAGE_PREFIX;

  String _addPrefix(String key) => '$storagePrefix$key';

  @override
  Future<void> init() async {}

  @override
  Future<void> set(String key, Map<String, dynamic> value) async {
    _data[_addPrefix(key)] = value;
  }

  @override
  Map<String, dynamic>? get(String key) => _data[_addPrefix(key)];

  @override
  bool has(String key) => _data.containsKey(_addPrefix(key));

  @override
  List<dynamic> getAll() => values;

  @override
  Future<void> update(String key, Map<String, dynamic> value) async {
    _data[_addPrefix(key)] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(_addPrefix(key));
  }

  @override
  Future<void> deleteAll() async {
    _data.clear();
  }
}

/// Fake keychain whose reads and writes can be made to fail independently,
/// mirroring the macOS failure mode where reads succeed but writes fail.
class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage({
    this.failWrites = false,
    this.failReads = false,
    Map<String, String>? initialData,
  }) : data = initialData ?? {};

  final Map<String, String> data;
  bool failWrites;
  bool failReads;

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failWrites) {
      throw Exception('keychain write denied');
    }
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failReads) {
      throw Exception('keychain read denied');
    }
    return data[key];
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failReads) {
      throw Exception('keychain read denied');
    }
    return Map<String, String>.from(data);
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failWrites) {
      throw Exception('keychain delete denied');
    }
    data.remove(key);
  }
}

void main() {
  group('SecureStore fallback stickiness', () {
    test('stays on secure storage when keychain works', () async {
      final fallback = _MemoryStore();
      final keychain = _FakeSecureStorage();

      final store = SecureStore(
        fallbackStorage: fallback,
        secureStorage: keychain,
      );
      await store.init();
      await store.set('wc_sessions', {'topic': 'abc'});

      expect(store.get('wc_sessions'), equals({'topic': 'abc'}));
      expect(keychain.data, isNotEmpty);
      expect(fallback.map, isEmpty);
    });

    test(
        'fallback survives relaunch when keychain reads work but writes fail',
        () async {
      final fallback = _MemoryStore();

      // Launch 1: reads succeed (empty keychain), writes fail.
      final brokenKeychain = _FakeSecureStorage(failWrites: true);
      final firstLaunch = SecureStore(
        fallbackStorage: fallback,
        secureStorage: brokenKeychain,
      );
      await firstLaunch.init();
      await firstLaunch.set('wc_sessions', {'topic': 'abc'});

      // The write failure must have routed the data to the fallback.
      expect(firstLaunch.get('wc_sessions'), equals({'topic': 'abc'}));

      // Launch 2: keychain reads still succeed and return nothing, because
      // the writes never landed. The store must keep using the fallback
      // instead of treating the empty keychain as authoritative.
      final secondLaunch = SecureStore(
        fallbackStorage: fallback,
        secureStorage: _FakeSecureStorage(),
      );
      await secondLaunch.init();

      expect(secondLaunch.get('wc_sessions'), equals({'topic': 'abc'}));
    });

    test('fallback survives relaunch after an initial restore failure',
        () async {
      final fallback = _MemoryStore();

      // Launch 1: keychain reads fail entirely; data goes to the fallback.
      final firstLaunch = SecureStore(
        fallbackStorage: fallback,
        secureStorage: _FakeSecureStorage(failReads: true),
      );
      await firstLaunch.init();
      await firstLaunch.set('wc_sessions', {'topic': 'abc'});

      // Launch 2: keychain recovered but is empty; the fallback still holds
      // the authoritative state and must keep being used.
      final secondLaunch = SecureStore(
        fallbackStorage: fallback,
        secureStorage: _FakeSecureStorage(),
      );
      await secondLaunch.init();

      expect(secondLaunch.get('wc_sessions'), equals({'topic': 'abc'}));
    });
  });
}
