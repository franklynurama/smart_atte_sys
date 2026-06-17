List<String> academicYearOptions({int firstStartYear = 2000, DateTime? now}) {
  final current = now ?? DateTime.now();
  final end = current.year;
  if (firstStartYear > end) {
    return ['$end/${end + 1}'];
  }
  return [
    for (int y = firstStartYear; y <= end; y++) '$y/${y + 1}',
  ];
}

String defaultAcademicYearLabel({DateTime? now}) {
  final current = now ?? DateTime.now();
  final y = current.year;
  return '$y/${y + 1}';
}

int parseAcademicYearStart(String label) {
  final m = RegExp(r'^(\d{4})/(\d{4})$').firstMatch(label.trim());
  if (m == null) {
    throw FormatException('Invalid academic year label: $label');
  }
  final start = int.parse(m.group(1)!);
  final end = int.parse(m.group(2)!);
  if (end != start + 1) {
    throw FormatException('Invalid academic year range: $label');
  }
  return start;
}
