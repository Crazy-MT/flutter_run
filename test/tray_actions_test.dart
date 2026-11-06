import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_run/tray_actions.dart';

void main() {
  test('tray actions track device and session state', () {
    expect(trayActions(hasDevice: false, running: false, starting: false),
        [false, false, false, false]);
    expect(trayActions(hasDevice: true, running: false, starting: false),
        [true, false, false, false]);
    expect(trayActions(hasDevice: true, running: false, starting: true),
        [false, false, false, true]);
    expect(trayActions(hasDevice: true, running: true, starting: false),
        [false, true, true, true]);
  });
}
