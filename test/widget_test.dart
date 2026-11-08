import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_run/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows runner controls without a selected project',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const RunnerApp());
    await tester.pump();
    expect(find.text('Flutter SDK'), findsOneWidget);
    expect(find.text('当前项目'), findsOneWidget);
    await tester.tap(find.byTooltip('项目与 SDK 设置'));
    await tester.pumpAndSettle();
    expect(find.text('项目目录'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('热重载'), findsOneWidget);
    expect(find.text('Logcat'), findsOneWidget);
    expect(find.text('工作空间'), findsNothing);
  });
  testWidgets('follows system light and dark appearance', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(const RunnerApp());
    expect(Theme.of(tester.element(find.text('当前项目'))).brightness,
        Brightness.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('当前项目'))).brightness,
        Brightness.dark);
  });
  testWidgets('saves and restores selected appearance', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(const RunnerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('切换外观'));
    await tester.pumpAndSettle();
    await tester.tap(find.ancestor(
        of: find.text('深色模式'),
        matching: find.byType(CheckedPopupMenuItem<ThemeMode>)));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('当前项目'))).brightness,
        Brightness.dark);
    expect(
        (await SharedPreferences.getInstance()).getString('themeMode'), 'dark');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const RunnerApp());
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('当前项目'))).brightness,
        Brightness.dark);
  });
  testWidgets('saving a typed SDK discovers devices', (tester) async {
    if (Platform.isWindows) return;
    final dir = Directory.systemTemp.createTempSync('sdk-ui-test');
    final bin = Directory('${dir.path}/bin');
    bin.createSync();
    final executable = File('${bin.path}/flutter');
    executable.writeAsStringSync(
        "#!/bin/sh\nif [ \"\$1\" = devices ]; then echo '[{\"id\":\"test-device\",\"name\":\"Test device\",\"targetPlatform\":\"darwin\"}]'; else echo '[]'; fi\n");
    Process.runSync('chmod', ['+x', executable.path]);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const RunnerApp());
    await tester.pump();
    await tester.tap(find.byTooltip('项目与 SDK 设置'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.first, dir.path);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    for (var i = 0;
        i < 100 && find.text('Test device').evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(find.text('Test device'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    dir.deleteSync(recursive: true);
  });
  testWidgets('project FVM is used to discover devices without a manual SDK',
      (tester) async {
    if (Platform.isWindows) return;
    final dir = Directory.systemTemp.createTempSync('fvm-ui-test');
    final bin = Directory('${dir.path}/.fvm/flutter_sdk/bin')
      ..createSync(recursive: true);
    final executable = File('${bin.path}/flutter');
    executable.writeAsStringSync('''#!/bin/sh
if [ "\$1" = devices ]; then
  echo '[{"id":"fvm-device","name":"FVM device","targetPlatform":"darwin"}]'
elif [ "\$1" = run ]; then
  echo "\$*" > "${dir.path}/fvm-run-arguments"
  echo '[{"event":"app.start","params":{"appId":"fvm-app"}}]'
  echo '[{"event":"app.started","params":{}}]'
  for i in \$(seq 1 100); do printf '[{"event":"app.log","params":{"log":"log-%s"}}]\\n' "\$i"; done
  while read line; do case "\$line" in *app.stop*) exit 0;; esac; done
else
  echo '[]'
fi
''');
    File('${dir.path}/pubspec.yaml').writeAsStringSync('name: fvm_test');
    Process.runSync('chmod', ['+x', executable.path]);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const RunnerApp());
    await tester.pump();
    await tester.tap(find.byTooltip('项目与 SDK 设置'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.last, dir.path);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    for (var i = 0;
        i < 100 && find.text('FVM device').evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(find.text('FVM device'), findsWidgets);
    expect(find.text('Debug'), findsOneWidget);
    await tester.tap(find.byTooltip('运行模式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    final runButton = find.widgetWithText(FilledButton, '运行');
    for (var i = 0;
        i < 100 && tester.widget<FilledButton>(runButton).onPressed == null;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(tester.widget<FilledButton>(runButton).onPressed, isNotNull);
    await tester.runAsync(() => tester.tap(runButton));
    final arguments = File('${dir.path}/fvm-run-arguments');
    for (var i = 0; i < 100 && !arguments.existsSync(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(arguments.existsSync(), isTrue, reason: '项目 FVM 应被用于启动');
    expect(arguments.readAsStringSync().trim(),
        'run --machine --profile -d fvm-device');
    for (var i = 0; i < 100 && find.text('log-100').evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(find.text('log-100'), findsOneWidget);
    expect(find.text('log-1'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    dir.deleteSync(recursive: true);
  });
  testWidgets('missing project FVM prevents stale manual SDK devices',
      (tester) async {
    if (Platform.isWindows) return;
    final root = Directory.systemTemp.createTempSync('fvm-missing-ui');
    final manual = Directory('${root.path}/manual/bin')
      ..createSync(recursive: true);
    final executable = File('${manual.path}/flutter');
    executable.writeAsStringSync(
        "#!/bin/sh\nif [ \"\$1\" = devices ]; then echo '[{\"id\":\"manual-device\",\"name\":\"Manual device\",\"targetPlatform\":\"darwin\"}]'; else echo '[]'; fi\n");
    Process.runSync('chmod', ['+x', executable.path]);
    final project = Directory('${root.path}/project')..createSync();
    File('${project.path}/.fvmrc').writeAsStringSync('{"flutter":"3.47.9"}');
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const RunnerApp());
    await tester.pump();
    await tester.tap(find.byTooltip('项目与 SDK 设置'));
    await tester.pumpAndSettle();
    final manualFields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(manualFields.first, '${root.path}/manual');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    for (var i = 0;
        i < 100 && find.text('Manual device').evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(find.text('Manual device'), findsWidgets);
    await tester.tap(find.byTooltip('项目与 SDK 设置'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.last, project.path);
    await tester.pump();
    expect(find.textContaining('fvm install'), findsWidgets);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('Manual device'), findsNothing);
    expect(find.textContaining('fvm install'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    root.deleteSync(recursive: true);
  });
}
