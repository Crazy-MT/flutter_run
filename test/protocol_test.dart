import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_run/protocol.dart';

void main() {
  test('parses machine event and ignores non-protocol output', () {
    expect(
        parseMachineMessage(
            '[{"event":"app.start","params":{"appId":"42"}}]')?['event'],
        'app.start');
    expect(parseMachineMessage('Building...'), isNull);
    expect(parseMachineMessage('[invalid'), isNull);
  });
  test('encodes restart commands with the active app id', () {
    expect(restartRequest(3, 'app', fullRestart: false),
        '[{"id":3,"method":"app.restart","params":{"appId":"app","fullRestart":false}}]');
  });
}
