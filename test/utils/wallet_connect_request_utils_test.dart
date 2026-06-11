import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_connect_request_utils.dart';

void main() {
  group('interactiveRequestKey', () {
    test('distinct request ids produce distinct keys for identical params',
        () {
      final params = {'fromAddress': 'z1abc', 'amount': '100'};

      final first = interactiveRequestKey(
        method: 'znn_send',
        topic: 'topic-1',
        params: params,
        requestId: 1,
      );
      final second = interactiveRequestKey(
        method: 'znn_send',
        topic: 'topic-1',
        params: params,
        requestId: 2,
      );

      expect(first, isNot(equals(second)));
    });

    test('same request id produces the same key regardless of params order',
        () {
      final first = interactiveRequestKey(
        method: 'znn_send',
        topic: 'topic-1',
        params: {'a': 1, 'b': 2},
        requestId: 7,
      );
      final second = interactiveRequestKey(
        method: 'znn_send',
        topic: 'topic-1',
        params: {'b': 2, 'a': 1},
        requestId: 7,
      );

      expect(first, equals(second));
    });

    test('falls back to a canonical params fingerprint without a request id',
        () {
      final first = interactiveRequestKey(
        method: 'znn_sign',
        topic: 'topic-1',
        params: {'message': 'hi', 'nested': {'y': 2, 'x': 1}},
        requestId: null,
      );
      final second = interactiveRequestKey(
        method: 'znn_sign',
        topic: 'topic-1',
        params: {'nested': {'x': 1, 'y': 2}, 'message': 'hi'},
        requestId: null,
      );

      expect(first, equals(second));
    });

    test('produces a stable key without a request id and without params', () {
      final first = interactiveRequestKey(
        method: 'znn_info',
        topic: 'topic-1',
        params: null,
        requestId: null,
      );
      final second = interactiveRequestKey(
        method: 'znn_info',
        topic: 'topic-1',
        params: null,
        requestId: null,
      );

      expect(first, equals(second));
      expect(first, contains('znn_info'));
      expect(first, contains('topic-1'));
    });

    test('different topics never share a key', () {
      final params = {'message': 'hi'};

      final first = interactiveRequestKey(
        method: 'znn_sign',
        topic: 'topic-1',
        params: params,
        requestId: 5,
      );
      final second = interactiveRequestKey(
        method: 'znn_sign',
        topic: 'topic-2',
        params: params,
        requestId: 5,
      );

      expect(first, isNot(equals(second)));
    });
  });
}
