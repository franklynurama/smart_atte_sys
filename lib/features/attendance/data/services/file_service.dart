import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../../../../core/utils/csv_parser.dart';

class FileService {
  static const _requiredColumnsError =
      'Enter a valid attendance CSV file. Required columns: student_id, student_name, timestamp.';

  Future<List<AttendanceCsvRow>> parseAttendanceRowsWithDateTime({
    required Uint8List bytes,
    required String? fileName,
  }) async {
    final rows = await CsvParser.parseCsvBytes(bytes);
    if (rows.isEmpty) return [];

    final header = rows.first.map(_normalizeHeader).toList();
    final idxName = _findColumn(header, ['studentname', 'student_name', 'name']);
    final idxId = _findColumn(header, ['studentid', 'student_id']);
    final idxTimestamp = _findColumn(header, ['timestamp', 'dateformatted']);
    final idxDate = _findColumn(header, ['date']);
    final idxTime = _findColumn(header, ['time']);
    if (idxId == -1 || idxName == -1 || idxTimestamp == -1) {
      throw const FormatException(_requiredColumnsError);
    }

    final out = <AttendanceCsvRow>[];
    for (int i = 1; i < rows.length; i++) {
      final r = rows[i];
      final id = idxId < r.length ? r[idxId].trim() : '';
      final name = idxName < r.length ? r[idxName].trim() : '';
      final tsRaw = idxTimestamp < r.length ? r[idxTimestamp].trim() : '';
      if (id.isEmpty || name.isEmpty || tsRaw.isEmpty) continue;
      var parsed = _parseTimestamp(tsRaw);
      if (parsed == null && idxDate != -1 && idxDate < r.length) {
        final dateRaw = r[idxDate].trim();
        final timeRaw = idxTime != -1 && idxTime < r.length ? r[idxTime].trim() : '';
        parsed = _parseTimestamp(timeRaw.isEmpty ? dateRaw : '$dateRaw $timeRaw');
      }
      if (parsed == null) continue;
      if (id.isEmpty) continue;
      out.add(
        AttendanceCsvRow(
          studentId: id,
          studentName: name,
          date: DateFormat('yyyy-MM-dd').format(parsed),
          time: DateFormat('HH:mm').format(parsed),
        ),
      );
    }
    if (out.isEmpty) {
      throw const FormatException(_requiredColumnsError);
    }
    return out;
  }

  /// Parses Raspberry Pi attendance CSV/Excel and returns student IDs marked as attended.
  ///
  /// If a student ID appears in the upload file, we treat it as attended.
  /// Students not present in the file are marked as absent during Firestore update.
  Future<List<String>> parseAttendedStudentIdsFromCsvBytes({
    required Uint8List bytes,
  }) async {
    final rows = await parseAttendanceRowsWithDateTime(bytes: bytes, fileName: 'attendance.csv');
    return rows.map((e) => e.studentId).toSet().toList();
  }

  Future<List<String>> parseAttendedStudentIdsFromExcelBytes({
    required Uint8List bytes,
  }) async {
    throw const FormatException('Excel attendance upload is not supported. Please use CSV.');
  }

  Future<List<String>> parseAttendedStudentIdsFromFileBytes({
    required Uint8List bytes,
    required String? fileName,
  }) async {
    final lower = (fileName ?? '').toLowerCase();
    final ext = lower.contains('.') ? lower.split('.').last : '';

    if (ext == 'xlsx' || ext == 'xls') {
      throw const FormatException('Excel attendance upload is not supported. Please use CSV.');
    }
    return parseAttendedStudentIdsFromCsvBytes(bytes: bytes);
  }

  String _normalizeHeader(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('_', '')
        .replaceAll('-', '')
        .replaceAll(' ', '');
  }

  int _findColumn(List<String> header, List<String> keys) {
    for (int i = 0; i < header.length; i++) {
      final h = header[i];
      if (keys.map(_normalizeHeader).any((k) => h == k || h.contains(k))) return i;
    }
    return -1;
  }

  DateTime? _parseTimestamp(String value) {
    final t = value.trim();
    if (t.isEmpty) return null;
    final serial = double.tryParse(t);
    if (serial != null && serial > 20000) {
      final base = DateTime.utc(1899, 12, 30);
      final micros = (serial * Duration.microsecondsPerDay).round();
      return base.add(Duration(microseconds: micros)).toLocal();
    }
    final normalized = t.contains('T') ? t : t.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized);
  }

  bool isWithinSessionWindow({
    required String csvTime,
    required String sessionStartHHmm,
    required String sessionEndHHmm,
  }) {
    try {
      final t = _toMinutes(csvTime);
      final s = _toMinutes(sessionStartHHmm);
      final e = _toMinutes(sessionEndHHmm);
      return t >= s && t <= e;
    } catch (_) {
      return false;
    }
  }

  int _toMinutes(String hhmm) {
    final parsed = hhmm.trim().split(':');
    if (parsed.length < 2) throw const FormatException('Invalid time');
    return (int.parse(parsed[0]) * 60) + int.parse(parsed[1]);
  }
}

class AttendanceCsvRow {
  final String studentName;
  final String studentId;
  final String date;
  final String time;

  const AttendanceCsvRow({
    required this.studentName,
    required this.studentId,
    required this.date,
    required this.time,
  });
}
