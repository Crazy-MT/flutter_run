enum LogLevel { verbose, debug, info, warning, error, normal }

class LogEntry {
  LogEntry(this.text, {this.isError = false});
  final String text;
  final bool isError;

  LogLevel get level {
    if (isError) return LogLevel.error;
    final input = text.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
    final android = RegExp(
            r'^\s*(?:\d\d-\d\d\s+\S+\s+\d+\s+\d+\s+|)([VDIWEF])/[^:]+(?:\s*\(\s*\d+\))?:',
            caseSensitive: false)
        .firstMatch(input);
    final threadtime = RegExp(r'^\s*\d\d-\d\d\s+\S+\s+\d+\s+\d+\s+([VDIWEF])\s')
        .firstMatch(input);
    final prefix = RegExp(
            r'^\s*(?:flutter:\s*)?(?:\[\s*(VERBOSE|DEBUG|INFO|WARN(?:ING)?|ERROR|FATAL|[VDIWEF])\s*\]|(VERBOSE|DEBUG|INFO|WARN(?:ING)?|ERROR|FATAL)\s*:)',
            caseSensitive: false)
        .firstMatch(input);
    final name = (threadtime?.group(1) ??
            android?.group(1) ??
            prefix?.group(1) ??
            prefix?.group(2))
        ?.toUpperCase();
    return switch (name) {
      'V' || 'VERBOSE' => LogLevel.verbose,
      'D' || 'DEBUG' => LogLevel.debug,
      'I' || 'INFO' => LogLevel.info,
      'W' || 'WARN' || 'WARNING' => LogLevel.warning,
      'E' || 'F' || 'ERROR' || 'FATAL' => LogLevel.error,
      _ => LogLevel.normal,
    };
  }
}
