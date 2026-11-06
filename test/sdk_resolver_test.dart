import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_run/sdk_resolver.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('fvm-resolver'));
  tearDown(() => root.deleteSync(recursive: true));

  test('uses project FVM SDK instead of manual SDK', () {
    final project = Directory('${root.path}/project')..createSync();
    final sdk = Directory('${project.path}/.fvm/flutter_sdk/bin')
      ..createSync(recursive: true);
    final executable =
        File('${sdk.path}/${Platform.isWindows ? 'flutter.bat' : 'flutter'}')
          ..writeAsStringSync('');
    final result = resolveFlutterSdk(project.path, '/manual/sdk');
    expect(result.isFvm, true);
    expect(result.executable, executable.path);
    expect(result.error, isNull);
  });

  test('missing FVM SDK is reported instead of silently using manual SDK', () {
    final project = Directory('${root.path}/project')..createSync();
    File('${project.path}/.fvmrc').writeAsStringSync('{"flutter":"3.47.9"}');
    final result = resolveFlutterSdk(project.path, '/manual/sdk');
    expect(result.isFvm, true);
    expect(result.executable, isNull);
    expect(result.error, contains('fvm install'));
  });

  test('uses manual SDK for a project without FVM', () {
    final result = resolveFlutterSdk(root.path, '/manual/sdk');
    expect(result.isFvm, false);
    expect(result.executable,
        '/manual/sdk${Platform.pathSeparator}bin${Platform.pathSeparator}${Platform.isWindows ? 'flutter.bat' : 'flutter'}');
  });

  test('an incomplete .fvm directory reports missing SDK', () {
    Directory('${root.path}/.fvm').createSync();
    final result = resolveFlutterSdk(root.path, '/manual/sdk');
    expect(result.isFvm, true);
    expect(result.error, contains('fvm install'));
  });
  test('follows the FVM SDK symlink and reports a broken link', () {
    if (Platform.isWindows) return;
    final fvmDir = Directory('${root.path}/.fvm')..createSync();
    final sdk = Directory('${root.path}/cache/bin')
      ..createSync(recursive: true);
    File('${sdk.path}/flutter').writeAsStringSync('');
    final link = Link('${fvmDir.path}/flutter_sdk')
      ..createSync('${root.path}/cache');
    expect(resolveFlutterSdk(root.path, '/manual').executable,
        '${link.path}/bin/flutter');
    link.deleteSync();
    link.createSync('${root.path}/missing');
    expect(
        resolveFlutterSdk(root.path, '/manual').error, contains('fvm install'));
  });
  test('rejects a stale FVM SDK when the configured version changed', () {
    final fvm = Directory('${root.path}/.fvm')..createSync();
    Directory('${fvm.path}/flutter_sdk/bin').createSync(recursive: true);
    File('${fvm.path}/flutter_sdk/bin/${Platform.isWindows ? 'flutter.bat' : 'flutter'}')
        .writeAsStringSync('');
    File('${root.path}/.fvmrc').writeAsStringSync('{"flutter":"3.47.9"}');
    File('${fvm.path}/release').writeAsStringSync('3.24.5');
    final result = resolveFlutterSdk(root.path, '/manual');
    expect(result.executable, isNull);
    expect(result.error, contains('fvm install'));
    File('${fvm.path}/release').writeAsStringSync('3.47.9');
    expect(resolveFlutterSdk(root.path, '/manual').executable, isNotNull);
  });

  test('does not silently ignore an unreadable FVM config', () {
    Directory('${root.path}/.fvm/flutter_sdk/bin').createSync(recursive: true);
    File('${root.path}/.fvm/flutter_sdk/bin/${Platform.isWindows ? 'flutter.bat' : 'flutter'}')
        .writeAsStringSync('');
    File('${root.path}/.fvmrc').writeAsStringSync('{broken');
    final result = resolveFlutterSdk(root.path, '/manual');
    expect(result.executable, isNull);
    expect(result.error, contains('.fvmrc'));
  });
  test('legacy FVM configuration also enforces the recorded version', () {
    final fvm = Directory('${root.path}/.fvm')..createSync();
    Directory('${fvm.path}/flutter_sdk/bin').createSync(recursive: true);
    File('${fvm.path}/flutter_sdk/bin/${Platform.isWindows ? 'flutter.bat' : 'flutter'}')
        .writeAsStringSync('');
    File('${fvm.path}/fvm_config.json')
        .writeAsStringSync('{"flutterSdkVersion":"3.24.5"}');
    File('${fvm.path}/release').writeAsStringSync('3.47.9');
    expect(
        resolveFlutterSdk(root.path, '/manual').error, contains('fvm install'));
  });
}
