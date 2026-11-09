import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'dart:ui' show AppExitResponse;
import 'package:webview_all/webview_all.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'log_filter.dart';
import 'log_entry.dart';
import 'session.dart';
import 'sdk_resolver.dart';
import 'sessions.dart';
import 'tray_actions.dart';
import 'package:tray_manager/tray_manager.dart' as tray;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RunnerApp(enableTray: true));
}

class RunnerApp extends StatefulWidget {
  const RunnerApp({super.key, this.enableTray = false});
  final bool enableTray;
  @override
  State<RunnerApp> createState() => _RunnerAppState();
}

class _RunnerAppState extends State<RunnerApp> {
  ThemeMode themeMode = ThemeMode.system;
  bool themeChanged = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted || themeChanged) return;
      final saved = prefs.getString('themeMode');
      setState(() => themeMode =
          ThemeMode.values.where((mode) => mode.name == saved).firstOrNull ??
              ThemeMode.system);
    });
  }

  void setThemeMode(ThemeMode mode) {
    themeChanged = true;
    setState(() => themeMode = mode);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString('themeMode', mode.name));
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'Flutter Run',
      theme: ThemeData(
          brightness: Brightness.light,
          colorSchemeSeed: const Color(0xff3578f6),
          scaffoldBackgroundColor: const Color(0xfff5f7fb),
          useMaterial3: true),
      darkTheme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xff69b4fc),
          scaffoldBackgroundColor: const Color(0xff101722),
          useMaterial3: true),
      themeMode: themeMode,
      home: Home(
          enableTray: widget.enableTray,
          themeMode: themeMode,
          onThemeChanged: setThemeMode));
}

class Home extends StatefulWidget {
  const Home(
      {super.key,
      this.enableTray = false,
      required this.themeMode,
      required this.onThemeChanged});
  final bool enableTray;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final sessions = Sessions();
  RunSession get session => sessions.forDevice(device ?? '');
  Set<String> connectedDevices = {};
  final sdk = TextEditingController(),
      project = TextEditingController(),
      filter = TextEditingController();
  List<Map<String, dynamic>> devices = [], emulators = [];
  String? device;
  String priority = 'V', tab = '运行日志';
  RunMode runMode = RunMode.debug;
  Process? logcat;
  int? logcatPid;
  tray.TrayIcon? trayIcon;
  tray.Menu? trayMenu;
  final List<tray.MenuItem> trayItems = [];
  final List<tray.Menu> traySubmenus = [];
  final Map<String, List<tray.MenuItem>> deviceTrayItems = {};
  final List<tray.MenuItem> batchTrayItems = [];
  final List<tray.MenuItem> selectedTrayItems = [];
  tray.MenuItem? selectedTrayLabel;
  late final AppLifecycleListener lifecycle;
  final Map<String, List<String>> deviceLogs = {};
  int logcatGeneration = 0;
  List<String> get androidLogs =>
      deviceLogs.putIfAbsent(device ?? '', () => []);
  bool paused = false, busy = false;
  bool showLogSearch = false;
  bool errorsOnly = false;
  int discoveryGeneration = 0;
  String status = '选择项目目录';
  @override
  void initState() {
    super.initState();
    sessions.addListener(refresh);
    if (widget.enableTray) setupTray();
    lifecycle = AppLifecycleListener(onExitRequested: () async {
      logcat?.kill();
      logcat = null;
      await sessions.stopAll();
      return AppExitResponse.exit;
    });
    load();
  }

  void setupTray() {
    try {
      final icon = tray.TrayIcon.create();
      final menu = tray.Menu.create();
      if (icon == null || menu == null) throw StateError('无法创建状态栏');
      trayIcon = icon;
      trayMenu = menu;
      final image = tray.ImageAsset.fromAsset('assets/tray_icon.png');
      if (image == null) throw StateError('无法加载状态栏图标');
      icon.icon = image;
      icon.setTooltip('Flutter Run');
      icon.setContextMenu(menu);
      rebuildTray();
      // The native tray installs its click handler when a listener is registered.
      icon.addListener((_) {});
      icon.setContextMenuTrigger(tray.ContextMenuTrigger.clicked);
      if (!icon.setVisible(true) || !icon.isVisible()) {
        throw StateError('无法显示状态栏图标');
      }
      updateTray();
    } catch (e) {
      trayIcon?.dispose();
      trayIcon = null;
      status = '状态栏不可用：$e';
    }
  }

  void rebuildTray() {
    final menu = trayMenu;
    if (menu == null) return;
    menu.clear();
    for (final item in trayItems) {
      item.dispose();
    }
    for (final submenu in traySubmenus) {
      submenu.dispose();
    }
    trayItems.clear();
    traySubmenus.clear();
    deviceTrayItems.clear();
    batchTrayItems.clear();
    selectedTrayItems.clear();
    tray.MenuItem item(String label, void Function() action) {
      final value = tray.MenuItem.createWithLabelAndType(
          label, tray.MenuItemType.normal)!;
      trayItems.add(value);
      value.addListener((event) {
        if (event is tray.MenuItemClickedEvent && value.isEnabled) action();
      });
      return value;
    }

    selectedTrayLabel = item('当前设备：未选择', () {});
    selectedTrayLabel!.isEnabled = false;
    menu.addItem(selectedTrayLabel);
    for (var i = 0; i < 4; i++) {
      final index = i;
      final action = item(
          ['运行', '热重载', '热重启', '停止'][index],
          () => unawaited(
              dispatchTrayAction(index, device, sessions, runForDevice)));
      selectedTrayItems.add(action);
      menu.addItem(action);
    }
    menu.addSeparator();

    for (final d in devices) {
      final id = d['id'] as String;
      final submenu = tray.Menu.create()!;
      traySubmenus.add(submenu);
      final parent = tray.MenuItem.createWithLabelAndType(
          '${d['name']} ($id)', tray.MenuItemType.submenu)!;
      trayItems.add(parent);
      parent.submenu = submenu;
      menu.addItem(parent);
      final actions = <tray.MenuItem>[
        for (var i = 0; i < 4; i++)
          item(
              ['运行', '热重载', '热重启', '停止'][i],
              () =>
                  unawaited(dispatchTrayAction(i, id, sessions, runForDevice))),
      ];
      deviceTrayItems[id] = actions;
      for (final value in actions) {
        submenu.addItem(value);
      }
    }
    if (devices.isNotEmpty) menu.addSeparator();
    final all = tray.Menu.create()!;
    traySubmenus.add(all);
    final parent = tray.MenuItem.createWithLabelAndType(
        '全部设备', tray.MenuItemType.submenu)!;
    trayItems.add(parent);
    parent.submenu = all;
    menu.addItem(parent);
    batchTrayItems.addAll([
      item('全部热重载', () => sessions.restartAll(fullRestart: false)),
      item('全部热重启', () => sessions.restartAll(fullRestart: true)),
      item('全部停止', () => unawaited(sessions.stopAll())),
    ]);
    for (final value in batchTrayItems) {
      all.addItem(value);
    }
    trayIcon?.setContextMenu(menu);
    updateTray();
  }

  void updateTray() {
    if (selectedTrayLabel != null) {
      final current = devices.where((d) => d['id'] == device).firstOrNull;
      selectedTrayLabel!.label = current == null
          ? '当前设备：未选择'
          : '当前设备：${current['name']} (${current['id']})';
    }
    if (selectedTrayItems.length == 4) {
      final current = device == null ? null : sessions[device!];
      final enabled = trayActions(
          hasDevice:
              !busy && device != null && connectedDevices.contains(device),
          running: current?.running ?? false,
          starting: current?.starting ?? false,
          debug: current?.mode == RunMode.debug);
      for (var i = 0; i < selectedTrayItems.length; i++) {
        selectedTrayItems[i].isEnabled = enabled[i];
      }
    }
    for (final entry in deviceTrayItems.entries) {
      final current = sessions[entry.key];
      final enabled = trayActions(
          hasDevice: !busy && connectedDevices.contains(entry.key),
          running: current?.running ?? false,
          starting: current?.starting ?? false,
          debug: current?.mode == RunMode.debug);
      for (var i = 0; i < entry.value.length; i++) {
        entry.value[i].isEnabled = enabled[i];
      }
    }
    final anyRunning = sessions.entries
        .any((e) => e.value.running && e.value.mode == RunMode.debug);
    if (batchTrayItems.length == 3) {
      batchTrayItems[0].isEnabled = anyRunning;
      batchTrayItems[1].isEnabled = anyRunning;
      batchTrayItems[2].isEnabled = sessions.active;
    }
  }

  void refresh() {
    final pid = device == null ? null : sessions[device!]?.processId;
    if (tab == 'Logcat' && pid != logcatPid) {
      unawaited(startLogcat());
    }
    updateTray();
    if (mounted) {
      setState(() {
        if (session.running) {
          status = '运行中';
        } else if (!session.starting &&
            (status == '运行中' || status == '正在启动应用…')) {
          status = '会话已停止';
        }
      });
    }
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    sdk.text = p.getString('sdk') ?? '';
    project.text = p.getString('project') ?? '';
    if (project.text.isNotEmpty &&
        !sdkResolution.isFvm &&
        sdkResolution.error == null) {
      sdk.text = sdkResolution.sdkPath!;
    }
    if (sdkResolution.executable != null || sdkResolution.isFvm) {
      await discover();
    }
    refresh();
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('sdk', sdk.text.trim());
    await p.setString('project', project.text.trim());
  }

  FlutterSdkResolution get sdkResolution =>
      resolveFlutterSdk(project.text, sdk.text);
  String get adb {
    return resolveAdb(Platform.environment);
  }

  Future<ProcessResult> command(String executable, List<String> args) =>
      Process.run(executable, args, runInShell: Platform.isWindows);
  void deviceDiscoveryFailed(String message) {
    final previousDevice = device;
    setState(() {
      connectedDevices = {};
      devices = devices
          .where((d) => sessions[d['id']]?.active == true)
          .map((d) => {...d, 'offline': true})
          .toList();
      emulators = [];
      if (!devices.any((d) => d['id'] == device)) device = null;
      status = message;
      rebuildTray();
    });
    if (previousDevice != device) {
      logcatGeneration++;
      logcat?.kill();
      logcat = null;
    }
  }

  Future<void> discover() async {
    final generation = ++discoveryGeneration;
    final resolution = sdkResolution;
    if (resolution.executable == null) {
      if (mounted) {
        setState(() => busy = false);
        deviceDiscoveryFailed(resolution.error ?? '请配置 Flutter SDK。');
      }
      return;
    }
    final executable = resolution.executable!;
    setState(() {
      busy = true;
      status = '正在查找设备…';
      updateTray();
    });
    try {
      final results = await Future.wait([
        command(executable, ['devices', '--machine']),
        command(executable, ['emulators', '--machine'])
      ]);
      if (results[0].exitCode != 0) throw Exception(results[0].stderr);
      final found = (jsonDecode(results[0].stdout as String) as List)
          .cast<Map<String, dynamic>>();
      final virtual = results[1].exitCode == 0
          ? (jsonDecode(results[1].stdout as String) as List)
              .cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      if (!mounted || generation != discoveryGeneration) return;
      final previousDevice = device;
      setState(() {
        connectedDevices = found.map((d) => d['id'] as String).toSet();
        final retained = devices
            .where((d) =>
                !connectedDevices.contains(d['id']) &&
                (sessions[d['id']]?.active ?? false))
            .map((d) => {...d, 'offline': true});
        devices = [...found, ...retained];
        emulators = virtual;
        if (!devices.any((d) => d['id'] == device)) {
          device = devices.isEmpty ? null : devices.first['id'] as String;
        }
        status = '发现 ${found.length} 个设备';
        rebuildTray();
      });
      if (previousDevice != device) {
        logcatGeneration++;
        logcat?.kill();
        logcat = null;
        if (tab == 'Logcat') unawaited(startLogcat());
      }
      await save();
    } catch (e) {
      if (mounted && generation == discoveryGeneration) {
        deviceDiscoveryFailed('设备发现失败：$e');
      }
    } finally {
      if (mounted && generation == discoveryGeneration) {
        setState(() {
          busy = false;
          updateTray();
        });
      }
    }
  }

  Future<void> choose(TextEditingController controller) async {
    final path = await getDirectoryPath();
    if (path != null && !sessions.active) {
      if (controller == project && controller.text != path) deviceLogs.clear();
      controller.text = path;
      if (controller == project && path.isNotEmpty) {
        final resolution = resolveFlutterSdk(path, '');
        if (resolution.executable != null && !resolution.isFvm) {
          sdk.text = resolution.sdkPath!;
        } else if (resolution.isFvm) {
          sdk.clear();
        }
      }
      await save();
      refresh();
    }
  }

  Future<void> run() async {
    if (device != null) await runForDevice(device!);
  }

  Future<void> runForDevice(String target) async {
    if (busy || !connectedDevices.contains(target)) return;
    final resolution = sdkResolution;
    if (resolution.executable == null) {
      setState(() => status = resolution.error ?? '请配置 Flutter SDK。');
      return;
    }
    if (!File('${project.text.trim()}${Platform.pathSeparator}pubspec.yaml')
        .existsSync()) {
      setState(() => status = '项目目录中找不到 pubspec.yaml');
      return;
    }
    final targetSession = sessions.forDevice(target);
    if (targetSession.active) return;
    try {
      final launch = targetSession.start(
          resolution.executable!, project.text.trim(), target,
          mode: runMode);
      await save();
      await launch;
      if (mounted && device == target && targetSession.starting) {
        setState(() => status = '正在启动应用…');
      }
    } catch (e) {
      setState(() => status = '启动失败：$e');
    }
  }

  void selectDevice(String? value) {
    if (device == value) return;
    setState(() {
      device = value;
      final current = value == null ? null : sessions[value];
      status = current?.running == true
          ? '运行中'
          : current?.starting == true
              ? '正在启动应用…'
              : '未运行';
      updateTray();
    });
    logcatGeneration++;
    logcat?.kill();
    logcat = null;
    if (tab == 'Logcat') unawaited(startLogcat());
    refresh();
  }

  Future<void> startLogcat() async {
    final generation = ++logcatGeneration;
    final target = device;
    logcat?.kill();
    logcat = null;
    logcatPid = null;
    if (target == null) return;
    final selected = devices.where((d) => d['id'] == target).toList();
    if (selected.isEmpty ||
        !('${selected.first['targetPlatform']}'.contains('android'))) {
      setState(() => status = 'Logcat 仅适用于 Android 设备');
      return;
    }
    final pid = sessions[target]?.processId;
    if (pid == null) {
      setState(() => status = '等待当前应用启动后显示 Logcat');
      return;
    }
    logcatPid = pid;
    deviceLogs.remove(target);
    try {
      final process = await Process.start(
          adb, ['-s', target, 'logcat', '--pid=$pid', '-v', 'threadtime'],
          runInShell: Platform.isWindows);
      if (!mounted || generation != logcatGeneration || device != target) {
        process.kill();
        return;
      }
      logcat = process;
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (!paused &&
            mounted &&
            generation == logcatGeneration &&
            device == target) {
          setState(() {
            final lines = deviceLogs.putIfAbsent(target, () => []);
            lines.add(line);
            if (lines.length > 5000) lines.removeRange(0, 1000);
          });
        }
      });
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (mounted && generation == logcatGeneration) {
          setState(() => status = line);
        }
      });
      unawaited(process.exitCode.then((code) {
        if (mounted && identical(logcat, process)) {
          setState(() {
            logcat = null;
            logcatPid = null;
            status = 'Logcat 已退出 ($code)';
          });
        }
      }));
    } catch (e) {
      if (mounted && generation == logcatGeneration) {
        logcatPid = null;
        setState(() => status = '无法启动 adb：$e');
      }
    }
  }

  @override
  void dispose() {
    trayIcon?.dispose();
    trayMenu?.dispose();
    for (final item in trayItems) {
      item.dispose();
    }
    for (final submenu in traySubmenus) {
      submenu.dispose();
    }
    lifecycle.dispose();
    sessions.removeListener(refresh);
    sessions.dispose();
    logcat?.kill();
    sdk.dispose();
    project.dispose();
    filter.dispose();
    super.dispose();
  }

  Widget pathRow(String name, TextEditingController controller,
          {bool devicesAfter = false}) =>
      Row(children: [
        SizedBox(width: 95, child: Text(name)),
        Expanded(
            child: TextField(
                controller: controller,
                readOnly: sessions.active,
                decoration: const InputDecoration(
                    isDense: true, border: OutlineInputBorder()),
                onSubmitted: (_) {
                  save();
                  if (devicesAfter || identical(controller, project)) {
                    discover();
                  }
                })),
        if (controller != sdk ||
            (sdkResolution.executable == null && !sdkResolution.isFvm)) ...[
          const SizedBox(width: 8),
          OutlinedButton(
              onPressed: sessions.active
                  ? null
                  : () async {
                      await choose(controller);
                      if (devicesAfter) await discover();
                    },
              child: const Text('选择'))
        ]
      ]);
  void setTab(String value) {
    setState(() => tab = value);
    if (value == 'Logcat' && logcat == null) unawaited(startLogcat());
  }

  Color tone(int light, int dark) =>
      Color(Theme.of(context).brightness == Brightness.dark ? dark : light);

  Future<void> showSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => ListenableBuilder(
          listenable: sessions,
          builder: (context, _) => AlertDialog(
                title: const Text('项目与 Flutter SDK'),
                content: SizedBox(
                    width: 620,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (sdkResolution.executable == null &&
                          !sdkResolution.isFvm) ...[
                        pathRow('Flutter SDK', sdk, devicesAfter: true),
                        const SizedBox(height: 14),
                      ],
                      pathRow('项目目录', project),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: project,
                        builder: (_, __, ___) {
                          final resolution = sdkResolution;
                          if (resolution.sdkPath == null)
                            return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                                resolution.error ??
                                    (resolution.isFvm
                                        ? '使用项目 FVM：${resolution.sdkPath}'
                                        : '自动检测 Flutter SDK：${resolution.sdkPath}'),
                                style: TextStyle(
                                    color: resolution.error == null
                                        ? tone(0xff3578f6, 0xff69b4fc)
                                        : tone(0xffc6414c, 0xffff858b))),
                          );
                        },
                      ),
                      if (sessions.active)
                        const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text('请先停止所有会话，再修改 SDK 或项目目录。')),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () {
                        save();
                        Navigator.pop(context);
                        refresh();
                        if (!sessions.active) unawaited(discover());
                      },
                      child: const Text('完成'))
                ],
              )),
    );
  }

  Color logColor(LogLevel level) => switch (level) {
        LogLevel.verbose => tone(0xff718095, 0xff8191a6),
        LogLevel.debug => tone(0xff526f98, 0xff83bafa),
        LogLevel.info => tone(0xff198969, 0xff65d7ad),
        LogLevel.warning => tone(0xffa77116, 0xfff0bd6e),
        LogLevel.error => tone(0xffc6414c, 0xffff858b),
        LogLevel.normal => tone(0xff414a56, 0xffc3d0df),
      };

  Widget sectionTitle(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(9, 18, 2, 8),
        child: Row(children: [
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1,
                      color: tone(0xff718095, 0xff8191a6),
                      fontWeight: FontWeight.w700))),
          if (trailing != null) trailing
        ]),
      );

  Widget deviceRow(Map<String, dynamic> d) {
    final id = d['id'] as String;
    final current = sessions[id];
    final isSelected = device == id;
    final active = current?.running == true;
    final subtitle = d['offline'] == true
        ? '已断开'
        : current?.starting == true
            ? '启动中'
            : active
                ? '运行中'
                : '未运行';
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: isSelected ? tone(0xffedf4ff, 0xff263b50) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => selectDevice(id),
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
                child: Row(children: [
                  Icon(
                      '${d['targetPlatform']}'.contains('android')
                          ? Icons.phone_android_rounded
                          : Icons.laptop_mac_rounded,
                      size: 19,
                      color: isSelected
                          ? tone(0xff3578f6, 0xff69b4fc)
                          : tone(0xff718095, 0xff8191a6)),
                  const SizedBox(width: 9),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('${d['name']}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(subtitle,
                            style: TextStyle(
                                fontSize: 10,
                                color: tone(0xff718095, 0xff8191a6))),
                      ])),
                  Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active
                              ? const Color(0xff32ae80)
                              : tone(0xffaab5c2, 0xff627184))),
                ])),
          ),
        ));
  }

  Widget buildSidebar() {
    final projectName = project.text
            .trim()
            .split(RegExp(r'[/\\]'))
            .where((e) => e.isNotEmpty)
            .lastOrNull ??
        '选择项目';
    return Container(
        width: 212,
        color: tone(0xffffffff, 0xff151f2c),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
              child: Row(children: [
                Icon(Icons.flutter_dash,
                    color: tone(0xff3578f6, 0xff69b4fc), size: 21),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text('Flutter Run',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800))),
                PopupMenuButton<ThemeMode>(
                    tooltip: '切换外观',
                    iconSize: 18,
                    icon: const Icon(Icons.brightness_6_outlined),
                    onSelected: widget.onThemeChanged,
                    itemBuilder: (_) => [
                          for (final (mode, label) in [
                            (ThemeMode.system, '跟随系统'),
                            (ThemeMode.light, '浅色模式'),
                            (ThemeMode.dark, '深色模式'),
                          ])
                            CheckedPopupMenuItem(
                                value: mode,
                                checked: widget.themeMode == mode,
                                child: Text(label)),
                        ]),
                IconButton(
                    tooltip: '项目与 SDK 设置',
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    onPressed: showSettings,
                    icon: const Icon(Icons.tune_rounded)),
              ])),
          Expanded(
              child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                sectionTitle('当前项目'),
                Material(
                    color: tone(0xffffffff, 0xff1b2736),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                        onTap: showSettings,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(children: [
                              Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                      color: tone(0xffedf4ff, 0xff263b50),
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Icon(Icons.folder_outlined,
                                      size: 18,
                                      color: tone(0xff3578f6, 0xff69b4fc))),
                              const SizedBox(width: 9),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(projectName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 3),
                                    Text(
                                        project.text.isEmpty
                                            ? '点击设置项目'
                                            : project.text,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 10,
                                            color:
                                                tone(0xff718095, 0xff8191a6)))
                                  ])),
                            ])))),
                sectionTitle('设备',
                    trailing: IconButton(
                        tooltip: '刷新设备',
                        visualDensity: VisualDensity.compact,
                        iconSize: 17,
                        onPressed: busy ? null : discover,
                        icon: const Icon(Icons.refresh_rounded))),
                if (devices.isEmpty)
                  Padding(
                      padding: const EdgeInsets.all(9),
                      child: Text('暂无可用设备',
                          style: TextStyle(
                              fontSize: 11,
                              color: tone(0xff718095, 0xff8191a6)))),
                ...devices.map(deviceRow),
                PopupMenuButton<String>(
                  tooltip: '启动模拟器',
                  onSelected: (id) async {
                    try {
                      final resolution = sdkResolution;
                      if (resolution.executable == null) {
                        setState(() =>
                            status = resolution.error ?? '请配置 Flutter SDK。');
                        return;
                      }
                      final result = await command(resolution.executable!,
                          ['emulators', '--launch', id]);
                      if (mounted) {
                        setState(() => status = result.exitCode == 0
                            ? '模拟器启动中，请稍后刷新设备'
                            : '${result.stderr}');
                      }
                    } catch (e) {
                      if (mounted) setState(() => status = '启动模拟器失败：$e');
                    }
                  },
                  itemBuilder: (_) => emulators.isEmpty
                      ? [
                          const PopupMenuItem<String>(
                              enabled: false, child: Text('没有可用模拟器'))
                        ]
                      : emulators
                          .map((e) => PopupMenuItem<String>(
                              value: e['id'] as String,
                              child: Text('${e['name']}')))
                          .toList(),
                  child: Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                          border:
                              Border.all(color: tone(0xffdce3ec, 0xff344457)),
                          borderRadius: BorderRadius.circular(8)),
                      child: Center(
                          child: Text('＋  启动模拟器',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: tone(0xff647184, 0xffa8b8c8))))),
                ),
              ])),
          InkWell(
              onTap: showSettings,
              child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  decoration: BoxDecoration(
                      border: Border(
                          top:
                              BorderSide(color: tone(0xffe9edf3, 0xff2b394a)))),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Text('Flutter SDK',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 7),
                          Icon(Icons.circle,
                              size: 7,
                              color: sdkResolution.executable == null
                                  ? Colors.grey
                                  : const Color(0xff32ae80))
                        ]),
                        const SizedBox(height: 4),
                        Text(
                            sdkResolution.isFvm
                                ? (sdkResolution.error == null
                                    ? 'FVM · ${sdkResolution.sdkPath}'
                                    : 'FVM 配置异常 · 点击查看')
                                : (sdkResolution.executable != null
                                    ? sdkResolution.sdkPath!
                                    : '点击配置'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10,
                                color: tone(0xff718095, 0xff8191a6))),
                      ]))),
        ]));
  }

  Widget actionButton(String label, IconData icon, VoidCallback? action,
      {bool primary = false}) {
    final style = primary
        ? FilledButton.styleFrom(
            backgroundColor: tone(0xff3578f6, 0xff69b4fc),
            foregroundColor: tone(0xffffffff, 0xff102439),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))
        : OutlinedButton.styleFrom(
            foregroundColor: tone(0xff17263c, 0xffd3deeb),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            side: BorderSide(color: tone(0xffdce3ec, 0xff344457)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)));
    return primary
        ? FilledButton.icon(
            onPressed: action,
            style: style,
            icon: Icon(icon, size: 16),
            label: Text(label))
        : OutlinedButton.icon(
            onPressed: action,
            style: style,
            icon: Icon(icon, size: 16),
            label: Text(label));
  }

  Widget logPanel(List<LogEntry> logs) => Container(
        decoration: BoxDecoration(
            color: tone(0xffffffff, 0xff1b2736),
            border: Border.all(color: tone(0xffe9edf3, 0xff2b394a)),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x0c25303a),
                  blurRadius: 18,
                  offset: Offset(0, 4))
            ]),
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(children: [
                Text(tab,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                Text('实时输出',
                    style: TextStyle(
                        fontSize: 11, color: tone(0xff198969, 0xff65d7ad))),
                const Spacer(),
                if (tab == 'Logcat')
                  TextButton(
                      onPressed: () => setState(() => paused = !paused),
                      child: Text(paused ? '继续' : '暂停')),
                if (tab == '运行日志')
                  FilterChip(
                      label: const Text('仅错误'),
                      selected: errorsOnly,
                      onSelected: (value) =>
                          setState(() => errorsOnly = value)),
                TextButton(
                    onPressed: () => setState(() {
                          if (tab == 'Logcat') {
                            androidLogs.clear();
                          } else {
                            session.logs.clear();
                          }
                        }),
                    child: const Text('清空')),
                IconButton(
                    tooltip: showLogSearch ? '收起搜索' : '搜索日志',
                    onPressed: () => setState(() {
                          showLogSearch = !showLogSearch;
                          if (!showLogSearch) filter.clear();
                        }),
                    icon: Icon(showLogSearch ? Icons.close : Icons.search)),
              ])),
          if (showLogSearch || tab == 'Logcat') ...[
            Divider(height: 1, color: tone(0xffe9edf3, 0xff2b394a)),
            Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(children: [
                  if (showLogSearch)
                    Expanded(
                        child: TextField(
                            controller: filter,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                                isDense: true,
                                hintText: '搜索日志',
                                prefixIcon: const Icon(Icons.search, size: 18),
                                filled: true,
                                fillColor: tone(0xfff5f7fb, 0xff111b27),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(7),
                                    borderSide: BorderSide.none)))),
                  if (tab == 'Logcat') ...[
                    if (showLogSearch) const SizedBox(width: 12),
                    DropdownButton<String>(
                        value: priority,
                        underline: const SizedBox.shrink(),
                        items: 'VDIWEF'
                            .split('')
                            .map((v) => DropdownMenuItem(
                                value: v,
                                child: Text(v,
                                    style: const TextStyle(fontSize: 12))))
                            .toList(),
                        onChanged: (v) => setState(() => priority = v!))
                  ],
                ])),
          ],
          Divider(height: 1, color: tone(0xffe9edf3, 0xff2b394a)),
          Expanded(
              child: logs.isEmpty
                  ? Center(
                      child: Text('暂无日志',
                          style: TextStyle(
                              color: tone(0xff718095, 0xff8191a6),
                              fontSize: 12)))
                  : SelectionArea(
                      child: ListView.builder(
                          key: ValueKey('$tab-$device'),
                          reverse: true,
                          padding: const EdgeInsets.all(14),
                          itemCount: logs.length,
                          itemBuilder: (_, i) {
                            final entry = logs[logs.length - 1 - i];
                            return Text(entry.text,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    height: 1.5,
                                    color: logColor(entry.level)));
                          }))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final logs = tab == 'Logcat'
        ? androidLogs
            .where((line) => matchesLog(line, filter.text, priority))
            .map((line) => LogEntry(line))
            .toList()
        : session.logs
            .where((entry) =>
                (!errorsOnly || entry.level == LogLevel.error) &&
                entry.text.toLowerCase().contains(filter.text.toLowerCase()))
            .toList();
    final selected = devices.where((d) => d['id'] == device).firstOrNull;
    final name = selected?['name']?.toString() ?? '选择设备';
    final state = session.running
        ? '运行中'
        : session.starting
            ? '启动中'
            : '未运行';
    return Scaffold(
        backgroundColor: tone(0xfff5f7fb, 0xff101722),
        body: SafeArea(
            child: Row(children: [
          buildSidebar(),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(28, 22, 28, 12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('运行会话',
                              style: TextStyle(
                                  color: tone(0xff718095, 0xff8191a6),
                                  fontSize: 10,
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 10,
                              runSpacing: 12,
                              children: [
                                Text(name,
                                    style: const TextStyle(
                                        fontSize: 25,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -.6)),
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                        color: session.running
                                            ? tone(0xffdcf5e9, 0xff203d39)
                                            : tone(0xffe9edf3, 0xff2b394a),
                                        borderRadius: BorderRadius.circular(6)),
                                    child: Text('● $state',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: session.running
                                                ? tone(0xff23845f, 0xff76dbb5)
                                                : tone(
                                                    0xff647184, 0xffa8b8c8)))),
                              ]),
                          const SizedBox(height: 5),
                          Text(
                              [
                                if (selected != null)
                                  '${selected['targetPlatform']}',
                                if (device != null) device!,
                                status,
                                if (session.lastOperation != null)
                                  session.lastOperation!
                              ].join('  ·  '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: tone(0xff718095, 0xff8191a6),
                                  fontSize: 11)),
                          const SizedBox(height: 15),
                          Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Tooltip(
                                    message: '运行模式',
                                    child: DropdownButton<RunMode>(
                                      value: runMode,
                                      items: RunMode.values
                                          .map((mode) => DropdownMenuItem(
                                                value: mode,
                                                child: Text(
                                                    mode.name[0].toUpperCase() +
                                                        mode.name.substring(1)),
                                              ))
                                          .toList(),
                                      onChanged: (mode) {
                                        if (mode != null) {
                                          setState(() => runMode = mode);
                                        }
                                      },
                                    )),
                                actionButton(
                                    '运行',
                                    Icons.play_arrow_rounded,
                                    busy ||
                                            device == null ||
                                            !connectedDevices
                                                .contains(device) ||
                                            session.active
                                        ? null
                                        : run,
                                    primary: true),
                                actionButton(
                                    '热重载',
                                    Icons.bolt_rounded,
                                    session.running &&
                                            session.mode == RunMode.debug
                                        ? () =>
                                            session.restart(fullRestart: false)
                                        : null),
                                actionButton(
                                    '热重启',
                                    Icons.restart_alt_rounded,
                                    session.running &&
                                            session.mode == RunMode.debug
                                        ? () =>
                                            session.restart(fullRestart: true)
                                        : null),
                                actionButton(
                                    '停止',
                                    Icons.stop_rounded,
                                    session.running || session.starting
                                        ? session.stop
                                        : null),
                              ]),
                        ])),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Wrap(
                        spacing: 5,
                        children: ['运行日志', 'Inspector', 'Logcat']
                            .map((value) => Padding(
                                padding: const EdgeInsets.only(right: 2),
                                child: ChoiceChip(
                                    showCheckmark: false,
                                    selected: tab == value,
                                    label: Text(value),
                                    labelStyle: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600),
                                    selectedColor: tone(0xffedf4ff, 0xff263b50),
                                    backgroundColor:
                                        tone(0xffffffff, 0xff1b2736),
                                    side: BorderSide.none,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    onSelected: (_) => setTab(value))))
                            .toList())),
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 16, 28, 14),
                        child: tab == 'Inspector'
                            ? (session.devToolsUri == null
                                ? Container(
                                    decoration: BoxDecoration(
                                        color: tone(0xffffffff, 0xff1b2736),
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: Center(
                                        child: Text('运行应用后连接 Flutter Inspector',
                                            style: TextStyle(
                                                color: tone(
                                                    0xff718095, 0xff8191a6)))))
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: InspectorView(
                                        key: ValueKey(session.devToolsUri),
                                        url: session.devToolsUri!)))
                            : logPanel(logs))),
                Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
                    child: Row(children: [
                      const Icon(Icons.circle,
                          size: 7, color: Color(0xff32ae80)),
                      const SizedBox(width: 7),
                      Expanded(
                          child: Text(
                              'Flutter SDK  ·  ${sessions.entries.where((e) => e.value.running).length} 个设备运行中',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: tone(0xff718095, 0xff8191a6))))
                    ])),
              ])),
        ])));
  }
}

class InspectorView extends StatefulWidget {
  const InspectorView({super.key, required this.url});
  final String url;
  @override
  State<InspectorView> createState() => _InspectorViewState();
}

class _InspectorViewState extends State<InspectorView> {
  late final WebViewController controller;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: controller);
}
