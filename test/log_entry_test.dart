import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_run/log_entry.dart';

void main() {
  test('recognizes explicit levels and preserves emoji and plain text', () {
    expect(LogEntry('[DEBUG] 🔎 connected').level, LogLevel.debug);
    expect(LogEntry('flutter: [INFO] 🚀 已连接').level, LogLevel.info);
    expect(LogEntry('WARN: ⚠️ cached').level, LogLevel.warning);
    expect(LogEntry('E/flutter (42): ❌ broken').level, LogLevel.error);
    expect(LogEntry('no error in this message').level, LogLevel.normal);
    expect(LogEntry('✅ 成功').text, '✅ 成功');
    expect(LogEntry('plain', isError: true).level, LogLevel.error);
    expect(LogEntry('11-06 14:00:00.000  123  123 W Tag: ⚠️').level,
        LogLevel.warning);
    expect(LogEntry('INFO about the error case').level, LogLevel.normal);
  });
}
