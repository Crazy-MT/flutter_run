import 'dart:io';

({String executable, List<String> arguments}) taskWindowCommand(
    String executable, String operatingSystem) {
  if (operatingSystem == 'macos') {
    final marker = executable.lastIndexOf('.app/Contents/MacOS/');
    if (marker < 0) throw StateError('无法定位当前应用，请从桌面应用中新建窗口。');
    return (
      executable: '/usr/bin/open',
      arguments: ['-n', executable.substring(0, marker + 4)],
    );
  }
  return (executable: executable, arguments: []);
}

Future<void> openTaskWindow() async {
  final command =
      taskWindowCommand(Platform.resolvedExecutable, Platform.operatingSystem);
  if (Platform.isMacOS) {
    final result = await Process.run(command.executable, command.arguments);
    if (result.exitCode != 0) throw StateError('${result.stderr}'.trim());
  } else {
    await Process.start(command.executable, command.arguments,
        mode: ProcessStartMode.detached);
  }
}
