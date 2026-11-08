import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_run/sessions.dart';
import 'package:flutter_run/tray_actions.dart';

Future<void> waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw StateError('会话事件等待超时');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  test('two devices have independent sessions and stop independently',
      () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('multi-run');
    final script = File('${dir.path}/flutter');
    await script.writeAsString('''#!/bin/sh
id="\$5"
printf '%s\\n' "[{\\"event\\":\\"app.start\\",\\"params\\":{\\"appId\\":\\"\$id\\"}}]" "[{\\"event\\":\\"app.started\\",\\"params\\":{}}]"
while read line; do
  case "\$line" in
    *app.restart*) printf '%s\n' '[{"id":1,"result":{"code":0,"message":"ok"}}]' ;;
    *app.stop*) exit 0 ;;
  esac
done
''');
    await Process.run('chmod', ['+x', script.path]);
    final sessions = Sessions();
    final a = sessions.forDevice('one');
    final b = sessions.forDevice('two');
    await Future.wait([
      a.start(script.path, dir.path, 'one'),
      b.start(script.path, dir.path, 'two')
    ]);
    await waitFor(() => a.running && b.running);
    expect(a.appId, 'one');
    expect(b.appId, 'two');
    sessions.restartAll(fullRestart: false);
    await waitFor(
        () => a.lastOperation == '热重载成功' && b.lastOperation == '热重载成功');
    expect(a.lastOperation, '热重载成功');
    expect(b.lastOperation, '热重载成功');
    await dispatchTrayAction(3, 'one', sessions, (_) async {});
    expect(a.running, false);
    expect(b.running, true);
    await sessions.stopAll();
    expect(b.running, false);
    sessions.dispose();
    await dir.delete(recursive: true);
  });
  test('stop requested while process is launching leaves no active session',
      () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('multi-stop');
    final script = File('${dir.path}/flutter');
    await script.writeAsString('#!/bin/sh\nsleep 20\n');
    await Process.run('chmod', ['+x', script.path]);
    final sessions = Sessions();
    final session = sessions.forDevice('device');
    final starting = session.start(script.path, dir.path, 'device');
    await session.stop();
    await starting;
    expect(session.active, false);
    expect(session.running, false);
    sessions.dispose();
    await dir.delete(recursive: true);
  });
}
