import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reown_core/events/i_events.dart';
import 'package:reown_core/store/i_store.dart';
import 'package:reown_walletkit/reown_walletkit.dart';
import 'package:zenon_syrius_wallet_flutter/services/desktop_signing_wallet_kit.dart';

class _FakeStore implements IStore<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEvents implements IEvents {
  Map<String, String>? lastQueryParams;
  int sendStoredEventsCalls = 0;
  Future<void> Function()? onSendStoredEvents;

  @override
  void setQueryParams(Map<String, String> params) {
    lastQueryParams = Map<String, String>.from(params);
  }

  @override
  Future<void> sendStoredEvents() async {
    sendStoredEventsCalls++;
    await onSendStoredEvents?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCore implements IReownCore {
  _FakeCore({required this.events, required this.storage});

  @override
  final IEvents events;

  @override
  IStore<Map<String, dynamic>> storage;

  @override
  String get projectId => 'synthetic-project-id';

  int startCalls = 0;
  Future<void> Function()? onStart;

  @override
  Future<void> start() async {
    startCalls++;
    await onStart?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSign implements IReownSign {
  int initCalls = 0;
  Future<void> Function()? onInit;

  @override
  Future<void> init() async {
    initCalls++;
    await onInit?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControlledKit extends DesktopSigningWalletKit {
  _ControlledKit(IReownCore core, this.sign)
      : super(
          core: core,
          metadata: const PairingMetadata(
            name: 'Synthetic desktop wallet',
            description: 'Offline initialization fixture',
            url: 'https://example.invalid',
          ),
        );

  final IReownSign sign;

  @override
  IReownSign get reOwnSign => sign;
}

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeCore core;
  late _FakeEvents events;
  late _FakeSign sign;
  late _ControlledKit kit;
  late List<String> order;
  late int paymentCalls;

  setUp(() {
    events = _FakeEvents();
    core = _FakeCore(events: events, storage: _FakeStore());
    sign = _FakeSign();
    order = <String>[];
    paymentCalls = 0;
    core.onStart = () async => order.add('core');
    events.onSendStoredEvents = () async => order.add('events');
    sign.onInit = () async => order.add('sign');
    kit = _ControlledKit(core, sign);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('walletconnect_pay'),
      (_) async {
        paymentCalls++;
        throw MissingPluginException('Synthetic unsupported desktop channel');
      },
    );
  });

  tearDown(() {
    binding.removeObserver(kit);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('walletconnect_pay'),
      null,
    );
  });

  test(
    'initializes signing with no desktop payment channel invocation',
    () async {
      await kit.init();
      await kit.init();
      expect(order, <String>['core', 'events', 'sign']);
      expect(events.lastQueryParams, <String, String>{
        'projectId': 'synthetic-project-id',
        'st': 'events_sdk',
        'sv': ReownCoreUtils.coreSdkVersion(packageVersion),
      });
      expect(paymentCalls, 0);
      expect(() => kit.pay, throwsUnsupportedError);
      expect(core.startCalls, 1);
      expect(events.sendStoredEventsCalls, 1);
      expect(sign.initCalls, 1);
    },
  );

  test(
    'concurrent initialization waits for the same signing operation',
    () async {
      final Completer<void> started = Completer<void>();
      final Completer<void> release = Completer<void>();
      sign.onInit = () {
        started.complete();
        return release.future;
      };
      final Future<void> first = kit.init();
      await started.future;
      final Future<void> second = kit.init();
      expect(identical(first, second), isTrue);
      release.complete();
      await Future.wait(<Future<void>>[first, second]);
      expect(paymentCalls, 0);
      expect(sign.initCalls, 1);
    },
  );

  test('failed signing initialization remains retryable', () async {
    int attempts = 0;
    sign.onInit = () async {
      if (++attempts == 1) throw StateError('Synthetic signing failure');
    };
    await expectLater(kit.init(), throwsStateError);
    await kit.init();
    await kit.init();
    expect(attempts, 2);
    expect(paymentCalls, 0);
    expect(core.startCalls, 2);
  });

  test(
    'core failure prevents events and signing from becoming ready',
    () async {
      core.onStart = () async => throw StateError('Synthetic core failure');
      await expectLater(kit.init(), throwsStateError);
      expect(events.sendStoredEventsCalls, 0);
      expect(sign.initCalls, 0);
      expect(paymentCalls, 0);
    },
  );
}
