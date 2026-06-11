import 'package:flutter_test/flutter_test.dart';
import 'package:reown_sign/reown_sign.dart';

void main() {
  group('invokeSessionRequestHandler', () {
    test('passes the JSON-RPC request id to id-aware handlers', () async {
      int? receivedId;
      String? receivedTopic;
      dynamic receivedParams;

      Future<dynamic> handler(
        String topic,
        dynamic params, {
        int? requestId,
      }) async {
        receivedTopic = topic;
        receivedParams = params;
        receivedId = requestId;
        return 'signed';
      }

      final result = await invokeSessionRequestHandler(
        handler,
        'topic-1',
        {'message': 'hi'},
        42,
      );

      expect(result, equals('signed'));
      expect(receivedTopic, equals('topic-1'));
      expect(receivedParams, equals({'message': 'hi'}));
      expect(receivedId, equals(42));
    });

    test(
        'id-aware handlers with extra optional named params still receive the '
        'id', () async {
      // Mirrors the syrius handler shape:
      // _handleZnnSendRequest(String, dynamic, {String? chainId, int? requestId})
      int? receivedId;

      Future<dynamic> handler(
        String topic,
        dynamic params, {
        String? chainId,
        int? requestId,
      }) async {
        receivedId = requestId;
        return 'sent';
      }

      final result = await invokeSessionRequestHandler(
        handler,
        'topic-1',
        {'amount': '100'},
        7,
      );

      expect(result, equals('sent'));
      expect(receivedId, equals(7));
    });

    test('invokes plain handlers without an id', () async {
      String? receivedTopic;

      Future<dynamic> handler(String topic, dynamic params) async {
        receivedTopic = topic;
        return 'plain';
      }

      final result = await invokeSessionRequestHandler(
        handler,
        'topic-1',
        null,
        13,
      );

      expect(result, equals('plain'));
      expect(receivedTopic, equals('topic-1'));
    });
  });
}
