import 'package:flutter/foundation.dart';
import 'session.dart';

class Sessions extends ChangeNotifier {
  final Map<String, RunSession> _sessions = {};
  RunSession forDevice(String id) => _sessions.putIfAbsent(id, () {
        final session = RunSession();
        session.addListener(notifyListeners);
        return session;
      });
  RunSession? operator [](String id) => _sessions[id];
  Iterable<MapEntry<String, RunSession>> get entries => _sessions.entries;
  bool get active => _sessions.values.any((s) => s.active);
  void restartAll({required bool fullRestart}) {
    for (final session in _sessions.values) {
      if (session.running) session.restart(fullRestart: fullRestart);
    }
  }

  Future<void> stopAll() async {
    await Future.wait(_sessions.values.map((session) => session.stop()));
  }

  @override
  void dispose() {
    for (final session in _sessions.values) {
      session.removeListener(notifyListeners);
      session.dispose();
    }
    super.dispose();
  }
}
