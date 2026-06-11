import 'dart:convert';

/// Builds the single-flight key for an interactive WalletConnect request.
///
/// The JSON-RPC [requestId] is the canonical identity of a request: two
/// concurrent requests with identical params are still distinct requests and
/// must each get their own approval flow. The params fingerprint is only a
/// last-resort bridge for callers that do not know the request id.
String interactiveRequestKey({
  required String method,
  required String topic,
  required dynamic params,
  required int? requestId,
}) {
  if (requestId != null) {
    return '$method:$topic:#$requestId';
  }
  final paramsFingerprint = requestParamsFingerprint(params);
  return '$method:$topic:$paramsFingerprint';
}

/// Canonical JSON fingerprint of request params: map keys are sorted
/// recursively so logically equal params produce the same fingerprint.
String requestParamsFingerprint(dynamic params) {
  try {
    return jsonEncode(_canonicalJsonValue(params));
  } catch (_) {
    return params.toString();
  }
}

dynamic _canonicalJsonValue(dynamic value) {
  if (value is Map) {
    final entries = value.entries
        .map((entry) => MapEntry(entry.key.toString(), entry.value))
        .toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return <String, dynamic>{
      for (final entry in entries) entry.key: _canonicalJsonValue(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalJsonValue).toList();
  }
  return value;
}
