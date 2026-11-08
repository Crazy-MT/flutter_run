import 'dart:convert';
import 'dart:io';

String resolveAdb(Map<String, String> environment) {
  for (final root in [environment['ANDROID_SDK_ROOT'], environment['ANDROID_HOME']]) {
    if (root == null || root.isEmpty) continue;
    final path = '$root${Platform.pathSeparator}platform-tools${Platform.pathSeparator}${Platform.isWindows ? 'adb.exe' : 'adb'}';
    if (File(path).existsSync()) return path;
  }
  return 'adb';
}

class FlutterSdkResolution {
  const FlutterSdkResolution(
      {required this.isFvm, this.sdkPath, this.executable, this.error});
  final bool isFvm;
  final String? sdkPath;
  final String? executable;
  final String? error;
}

FlutterSdkResolution resolveFlutterSdk(
    String projectPath, String manualSdkPath) {
  final project = projectPath.trim();
  final separator = Platform.pathSeparator;
  final executableName = Platform.isWindows ? 'flutter.bat' : 'flutter';
  if (project.isNotEmpty) {
    final fvmDirectory = '$project$separator.fvm';
    if (Directory(fvmDirectory).existsSync() ||
        File('$project$separator.fvmrc').existsSync()) {
      final sdk = '$fvmDirectory${separator}flutter_sdk';
      final executable = '$sdk${separator}bin$separator$executableName';
      final modernConfig = File('$project$separator.fvmrc');
      final legacyConfig = File('$fvmDirectory${separator}fvm_config.json');
      final config = modernConfig.existsSync() ? modernConfig : legacyConfig;
      if (config.existsSync()) {
        try {
          final decoded = jsonDecode(config.readAsStringSync());
          if (decoded is! Map) throw const FormatException();
          final version = modernConfig.existsSync()
              ? decoded['flutter']
              : decoded['flutterSdkVersion'];
          if (version != null && version is! String) {
            throw const FormatException();
          }
          final release = File('$fvmDirectory${separator}release');
          if (version is String &&
              version.isNotEmpty &&
              release.existsSync() &&
              release.readAsStringSync().trim() != version.trim()) {
            return FlutterSdkResolution(
                isFvm: true,
                sdkPath: sdk,
                error: '项目 FVM 版本与本地 SDK 记录不一致，请在项目目录运行 fvm install。');
          }
        } catch (_) {
          return FlutterSdkResolution(
              isFvm: true,
              sdkPath: sdk,
              error: '无法读取项目 FVM 配置 ${config.path}，请检查配置文件。');
        }
      }
      if (!File(executable).existsSync()) {
        return FlutterSdkResolution(
            isFvm: true,
            sdkPath: sdk,
            error: '项目配置了 FVM，但 Flutter SDK 不存在。请在项目目录运行 fvm install。');
      }
      return FlutterSdkResolution(
          isFvm: true, sdkPath: sdk, executable: executable);
    }
  }
  final manual = manualSdkPath.trim();
  if (manual.isEmpty) {
    return const FlutterSdkResolution(isFvm: false, error: '请配置 Flutter SDK。');
  }
  return FlutterSdkResolution(
      isFvm: false,
      sdkPath: manual,
      executable: '$manual${separator}bin$separator$executableName');
}
