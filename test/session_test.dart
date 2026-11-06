import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_run/session.dart';
import 'package:flutter_run/log_entry.dart';

Future<void> waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw StateError('会话事件等待超时');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  test('session handles machine events and terminates', () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('flutter-run-test');
    final script = File('${dir.path}/flutter');
    await script.writeAsString('''#!/bin/sh
printf '%s\\n' '[{"event":"app.start","params":{"appId":"a"}}]' '[{"event":"app.devTools","params":{"uri":"http://127.0.0.1:1234/"}}]' '[{"event":"app.started","params":{}}]' '[{"event":"app.log","params":{"log":"❌ 出错","error":true}}]'
while read line; do case "\$line" in *app.stop*) exit 0;; esac; done
''');
    await Process.run('chmod', ['+x', script.path]);
    final session = RunSession();
    await session.start(script.path, dir.path, 'device');
    await waitFor(() =>
        session.running &&
        session.devToolsUri != null &&
        session.logs.isNotEmpty);
    expect(session.logs.last.text, '❌ 出错');
    expect(session.logs.last.level, LogLevel.error);
    expect(session.appId, 'a');
    expect(session.devToolsUri, 'http://127.0.0.1:1234/');
    expect(session.running, isTrue);
    await session.stop();
    expect(session.running, isFalse);
    session.dispose();
    await dir.delete(recursive: true);
  });
}
