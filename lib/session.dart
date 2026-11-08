import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'protocol.dart';
import 'log_entry.dart';

enum RunMode { debug, profile, release }

class RunSession extends ChangeNotifier {
  Process? _process;
  Future<Process>? _launch;
  bool _stopRequested = false;
  bool _disposed = false;
  bool _stopping = false;
  bool get active => _process != null || starting;
  String? lastOperation;
  final Map<int, String> _pending = {};
  String? appId;
  String? devToolsUri;
  int? processId;
  int _processGeneration = 0;
  RunMode mode = RunMode.debug;
  bool running = false;
  bool starting = false;
  final List<LogEntry> logs = [];
  int _id = 0;

  void _log(String line, {bool isError = false}) {
    logs.add(LogEntry(line, isError: isError));
    if (logs.length > 10000) logs.removeRange(0, logs.length - 10000);
    notifyListeners();
  }

  Future<void> start(String flutter, String project, String device,
      {RunMode mode = RunMode.debug}) async {
    if (_process != null || starting) return;
    this.mode = mode;
    starting = true;
    lastOperation = null;
    _pending.clear();
    notifyListeners();
    try {
      _stopRequested = false;
      final launch = Process.start(
          flutter, ['run', '--machine', '--${mode.name}', '-d', device],
          workingDirectory: project, runInShell: Platform.isWindows);
      _launch = launch;
      final process = await launch;
      _launch = null;
      if (_stopRequested || _disposed) {
        process.kill();
        await process.exitCode;
        starting = false;
        if (!_disposed) notifyListeners();
        return;
      }
      _process = process;
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handle);
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _log(line));
      unawaited(process.exitCode.then((code) {
        if (identical(_process, process)) {
          _process = null;
          appId = null;
          devToolsUri = null;
          _processGeneration++;
          processId = null;
          running = false;
          starting = false;
          _log('Flutter 进程已退出 ($code)', isError: code != 0);
        }
      }));
    } catch (e) {
      _launch = null;
      starting = false;
      if (!_disposed) _log('启动失败: $e', isError: true);
      rethrow;
    }
  }

  void _handle(String line) {
    final event = parseMachineMessage(line);
    if (event == null) {
      _log(line);
      return;
    }
    final requestId = event['id'];
    if (requestId is int && _pending.containsKey(requestId)) {
      final action = _pending.remove(requestId)!;
      final result = event['result'];
      final error = event['error'];
      final success = error == null && result is Map && result['code'] == 0;
      lastOperation =
          '$action${success ? '成功' : '失败'}${success ? '' : ': ${error ?? result}'}';
      _log(lastOperation!, isError: !success);
    }
    final params = event['params'] is Map
        ? Map<String, dynamic>.from(event['params'])
        : <String, dynamic>{};
    switch (event['event']) {
      case 'app.start':
        appId = params['appId'] as String?;
      case 'app.started':
        running = true;
        starting = false;
      case 'app.debugPort':
        final uri = params['wsUri'];
        if (uri is String) unawaited(_readProcessId(uri));
      case 'app.devTools':
        devToolsUri = params['uri'] as String?;
      case 'app.log':
        _log('${params['log'] ?? ''}', isError: params['error'] == true);
      case 'app.stop':
        _processGeneration++;
        processId = null;
        running = false;
        starting = false;
        devToolsUri = null;
      default:
        if (event['error'] != null) {
          _log('请求失败: ${event['error']}', isError: true);
        }
    }
    notifyListeners();
  }

  Future<void> _readProcessId(String uri) async {
    final currentApp = appId;
    final generation = ++_processGeneration;
    WebSocket? socket;
    try {
      socket = await WebSocket.connect(uri).timeout(const Duration(seconds: 5));
      socket.add(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'getVM'}));
      final response = await socket.first.timeout(const Duration(seconds: 5));
      final result = jsonDecode(response as String)['result'];
      if (!_disposed &&
          appId == currentApp &&
          generation == _processGeneration &&
          result is Map &&
          result['pid'] is int) {
        processId = result['pid'] as int;
        notifyListeners();
      }
    } catch (_) {
      // The VM service may disappear while the app is stopping.
    } finally {
      await socket?.close();
    }
  }

  void restart({required bool fullRestart}) {
    if (mode == RunMode.debug && appId != null && _process != null) {
      final id = ++_id;
      final action = fullRestart ? '热重启' : '热重载';
      _pending[id] = action;
      lastOperation = '$action中';
      notifyListeners();
      _process!.stdin
          .writeln(restartRequest(id, appId!, fullRestart: fullRestart));
    }
  }

  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;
    var process = _process;
    final launch = _launch;
    if (process == null && launch != null) {
      _stopRequested = true;
      try {
        final pending = await launch;
        pending.kill();
        await pending.exitCode;
      } catch (_) {}
      _stopping = false;
      return;
    }
    if (process == null) {
      _stopping = false;
      return;
    }
    if (appId != null) {
      process.stdin.writeln(jsonEncode([
        {
          'id': ++_id,
          'method': 'app.stop',
          'params': {'appId': appId}
        }
      ]));
      await process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
        process.kill();
        return -1;
      });
    } else {
      process.kill();
      await process.exitCode;
    }
    if (identical(_process, process)) _process = null;
    running = false;
    starting = false;
    _stopping = false;
    lastOperation = '已停止';
    appId = null;
    devToolsUri = null;
    _processGeneration++;
    processId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopRequested = true;
    _process?.kill();
    _process = null;
    super.dispose();
  }
}
