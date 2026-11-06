import 'dart:convert';

Map<String, dynamic>? parseMachineMessage(String line) {
  try {
    final value = jsonDecode(line);
    if (value is List && value.length == 1 && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
  } on FormatException {
    return null;
  }
  return null;
}

String restartRequest(int id, String appId, {required bool fullRestart}) =>
    jsonEncode([
      {
        'id': id,
        'method': 'app.restart',
        'params': {'appId': appId, 'fullRestart': fullRestart}
      }
    ]);
