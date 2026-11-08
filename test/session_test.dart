import 'dart:io';
import 'dart:convert';
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
  test('passes each run mode to Flutter', () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('flutter-run-mode');
    final script = File('${dir.path}/flutter');
    await script
        .writeAsString('#!/bin/sh\nprintf "%s\n" "\$*" > "${dir.path}/args"\n');
    await Process.run('chmod', ['+x', script.path]);
    for (final mode in RunMode.values) {
      final session = RunSession();
      await session.start(script.path, dir.path, 'device', mode: mode);
      await waitFor(
          () => File('${dir.path}/args').existsSync() && !session.active);
      expect(await File('${dir.path}/args').readAsString(),
          'run --machine --${mode.name} -d device\n');
      await File('${dir.path}/args').delete();
      session.dispose();
    }
    await dir.delete(recursive: true);
  });

  test('reads the running app process ID from the VM service', () async {
    if (Platform.isWindows) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((message) {
        expect(jsonDecode(message as String)['method'], 'getVM');
        socket.add(jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'result': {'pid': 1234}
        }));
      });
    });
    final dir = await Directory.systemTemp.createTemp('flutter-run-pid');
    final script = File('${dir.path}/flutter');
    await script.writeAsString('''#!/bin/sh
printf '%s\\n' '[{"event":"app.start","params":{"appId":"a"}}]' '[{"event":"app.debugPort","params":{"wsUri":"ws://127.0.0.1:${server.port}/ws"}}]' '[{"event":"app.started","params":{}}]'
while read line; do case "\$line" in *app.stop*) exit 0;; esac; done
''');
    await Process.run('chmod', ['+x', script.path]);
    final session = RunSession();
    await session.start(script.path, dir.path, 'device');
    await waitFor(() => session.processId != null);
    expect(session.processId, 1234);
    await session.stop();
    expect(session.processId, isNull);
    session.dispose();
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

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
