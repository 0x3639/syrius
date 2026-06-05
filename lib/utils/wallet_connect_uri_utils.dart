String? extractWalletConnectUri(String rawLink, {bool isWindows = false}) {
  String normalized = rawLink.trim();

  if (normalized.isEmpty) {
    return null;
  }

  if (isWindows) {
    normalized = normalized.replaceAll('/?', '?');
  }

  final lower = normalized.toLowerCase();

  if (lower.startsWith('wc:') && _isValidWalletConnectUri(normalized)) {
    return normalized;
  }

  if (lower.startsWith('wc%3a')) {
    final decoded = _decodeUriValue(normalized);
    if (_isValidWalletConnectUri(decoded)) {
      return decoded;
    }
  }

  final parsed = Uri.tryParse(normalized);
  final uriParam = parsed?.queryParameters['uri'];
  if (uriParam != null && uriParam.isNotEmpty) {
    final decoded = _decodeUriValue(uriParam);
    if (_isValidWalletConnectUri(decoded)) {
      return decoded;
    }
  }

  final regex = RegExp(r'uri=([^&]+)', caseSensitive: false);
  final match = regex.firstMatch(normalized);
  if (match != null) {
    final encoded = match.group(1);
    if (encoded != null && encoded.isNotEmpty) {
      final decoded = _decodeUriValue(encoded);
      if (_isValidWalletConnectUri(decoded)) {
        return decoded;
      }
    }
  }

  return null;
}

bool isWalletConnectUri(String rawLink, {bool isWindows = false}) {
  return extractWalletConnectUri(rawLink, isWindows: isWindows) != null;
}

bool _isValidWalletConnectUri(String value) {
  final normalized = value.trim();
  final match = RegExp(
    r'^wc:([^@?\s]+)@(\d+)\?(.+)$',
    caseSensitive: false,
  ).firstMatch(normalized);

  if (match == null) {
    return false;
  }

  if (match.group(2) != '2') {
    return false;
  }

  final query = match.group(3);
  if (query == null || query.isEmpty) {
    return false;
  }

  try {
    final queryParameters = Uri.splitQueryString(query);
    return (queryParameters['relay-protocol']?.isNotEmpty ?? false) &&
        (queryParameters['symKey']?.isNotEmpty ?? false);
  } catch (_) {
    return false;
  }
}

String _decodeUriValue(String value) {
  var decoded = value;
  for (var i = 0; i < 2; i++) {
    final next = Uri.decodeComponent(decoded);
    if (next == decoded) {
      break;
    }
    decoded = next;
  }
  return decoded;
}
