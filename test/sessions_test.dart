import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_run/sessions.dart';
import 'package:flutter_run/log_entry.dart';
import 'package:flutter_run/tray_actions.dart';

Future<void> waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw StateError('会话事件等待超时');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  test('task windows run different projects and stop independently', () async {
    if (Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp('task-windows');
    final firstProject = await Directory('${root.path}/first').create();
    final secondProject = await Directory('${root.path}/second').create();
    final script = File('${root.path}/flutter');
    await script.writeAsString('''#!/bin/sh
pwd > started
printf '%s\\n' '[{"event":"app.start","params":{"appId":"task"}}]' '[{"event":"app.started","params":{}}]'
while read line; do case "\$line" in *app.stop*) exit 0;; esac; done
''');
    await Process.run('chmod', ['+x', script.path]);
    final first = Sessions();
    final second = Sessions();
    try {
      await Future.wait([
        first
            .forDevice('device')
            .start(script.path, firstProject.path, 'device'),
        second
            .forDevice('device')
            .start(script.path, secondProject.path, 'device'),
      ]);
      await waitFor(
          () => first['device']!.running && second['device']!.running);
      expect(File('${firstProject.path}/started').readAsStringSync().trim(),
          firstProject.resolveSymbolicLinksSync());
      expect(File('${secondProject.path}/started').readAsStringSync().trim(),
          secondProject.resolveSymbolicLinksSync());
      await first.stopAll();
      expect(first.active, isFalse);
      expect(second['device']!.running, isTrue);
    } finally {
      await first.stopAll();
      await second.stopAll();
      first.dispose();
      second.dispose();
      await root.delete(recursive: true);
    }
  });

  test('clearing inactive sessions removes previous project logs', () {
    final sessions = Sessions();
    final previous = sessions.forDevice('one');
    previous.logs.add(LogEntry('old project'));
    sessions.clear();
    expect(sessions.entries, isEmpty);
    expect(sessions.forDevice('one'), isNot(same(previous)));
    expect(sessions.forDevice('one').logs, isEmpty);
    sessions.dispose();
  });
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
