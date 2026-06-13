/// Adjustments checkbox display: manual override if set, else raw.
bool adjustmentsDisplay(
  Map<String, bool> manual,
  Map<String, bool> raw,
  String studentId,
) =>
    manual.containsKey(studentId) ? manual[studentId]! : (raw[studentId] ?? false);

/// Final Attendance + semester percentage: manual override if set, else raw.
bool effectivePresent(
  Map<String, bool> manual,
  Map<String, bool> raw,
  String studentId,
) =>
    manual.containsKey(studentId) ? manual[studentId]! : (raw[studentId] ?? false);

Map<String, bool> parseBoolMap(Map<String, dynamic>? raw) {
  if (raw == null) return {};
  return raw.map((k, v) => MapEntry(k, (v as bool?) ?? false));
}
