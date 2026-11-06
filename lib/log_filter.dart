bool matchesLog(String line, String keyword, String priority) {
  if (!line.toLowerCase().contains(keyword.toLowerCase())) return false;
  final match =
      RegExp(r'^\S+\s+\S+\s+\d+\s+\d+\s+([VDIWEF])\s').firstMatch(line);
  if (match == null) return priority == 'V';
  return 'VDIWEF'.indexOf(match[1]!) >= 'VDIWEF'.indexOf(priority);
}
