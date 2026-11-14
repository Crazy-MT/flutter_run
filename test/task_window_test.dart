import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_run/task_window.dart';

void main() {
  test('macOS opens a separate instance of the current app bundle', () {
    final command = taskWindowCommand(
        '/Applications/Flutter Run.app/Contents/MacOS/flutter_run', 'macos');
    expect(command.executable, '/usr/bin/open');
    expect(command.arguments, ['-n', '/Applications/Flutter Run.app']);
  });
  test('macOS rejects an executable outside an app bundle', () {
    expect(() => taskWindowCommand('/usr/bin/dart', 'macos'), throwsStateError);
  });
  test('other desktops launch the current executable without shell parsing',
      () {
    for (final platform in ['windows', 'linux']) {
      final command =
          taskWindowCommand('/path with spaces/flutter_run', platform);
      expect(command.executable, '/path with spaces/flutter_run');
      expect(command.arguments, isEmpty);
    }
  });
}
