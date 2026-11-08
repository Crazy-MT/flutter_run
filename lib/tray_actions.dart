import 'sessions.dart';

List<bool> trayActions(
        {required bool hasDevice,
        required bool running,
        required bool starting,
        bool debug = true}) =>
    [
      hasDevice && !running && !starting,
      running && debug,
      running && debug,
      running || starting
    ];

Future<void> dispatchTrayAction(int index, String? device, Sessions sessions,
    Future<void> Function(String) run) async {
  if (device == null) return;
  final session = sessions[device];
  switch (index) {
    case 0:
      await run(device);
    case 1:
      session?.restart(fullRestart: false);
    case 2:
      session?.restart(fullRestart: true);
    case 3:
      await session?.stop();
  }
}
