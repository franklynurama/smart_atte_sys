import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../../../core/utils/csv_parser.dart';

class FileService {
  /// Parses Raspberry Pi attendance CSV/Excel and returns student IDs marked as attended.
  ///
  /// If a student ID appears in the upload file, we treat it as attended.
  /// Students not present in the file are marked as absent during Firestore update.
  Future<List<String>> parseAttendedStudentIdsFromCsvBytes({
    required Uint8List bytes,
  }) async {
    final rows = await CsvParser.parseCsvBytes(bytes);
    if (rows.isEmpty) return [];

    final header = rows.first.map((e) => e.toLowerCase()).toList();
    int idxStudentId = _findStudentIdColumn(header);

    final ids = <String>{};
    for (int r = 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.length <= idxStudentId) continue;
      final id = row[idxStudentId].trim();
      if (id.isNotEmpty) ids.add(id);
    }
    return ids.toList();
  }

  Future<List<String>> parseAttendedStudentIdsFromExcelBytes({
    required Uint8List bytes,
  }) async {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.isNotEmpty ? excel.tables.values.first : null;
    if (sheet == null) return [];

    final rows = sheet.rows
        .map((r) => r.map((c) => c?.value?.toString().trim() ?? '').toList())
        .toList();
    if (rows.isEmpty) return [];

    final header = rows.first.map((e) => e.toLowerCase()).toList();
    int idxStudentId = _findStudentIdColumn(header);

    final ids = <String>{};
    for (int r = 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.length <= idxStudentId) continue;
      final id = row[idxStudentId].trim();
      if (id.isNotEmpty) ids.add(id);
    }
    return ids.toList();
  }

  Future<List<String>> parseAttendedStudentIdsFromFileBytes({
    required Uint8List bytes,
    required String? fileName,
  }) async {
    final lower = (fileName ?? '').toLowerCase();
    final ext = lower.contains('.') ? lower.split('.').last : '';

    if (ext == 'xlsx' || ext == 'xls') {
      return parseAttendedStudentIdsFromExcelBytes(bytes: bytes);
    }
    return parseAttendedStudentIdsFromCsvBytes(bytes: bytes);
  }

  int _findStudentIdColumn(List<String> header) {
    for (int i = 0; i < header.length; i++) {
      final h = header[i];
      if (h == 'student id' || h == 'studentid' || h.contains('student id')) {
        return i;
      }
    }
    return header.length > 1 ? 1 : 0;
  }
}
