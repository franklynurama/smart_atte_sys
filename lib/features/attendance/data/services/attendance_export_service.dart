import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

import '../../../courses/data/models/course_model.dart';
import '../../../courses/data/models/student_model.dart';
import '../../domain/attendance_merge.dart';
import '../../data/models/attendance_session_model.dart';
import '../../presentation/utils/attendance_slot_builder.dart';

List<List<String>> _buildGridRows(Map<String, dynamic> payload) {
  final students = (payload['students'] as List<dynamic>).map((e) {
    final m = e as Map<String, dynamic>;
    return StudentModel(studentName: m['name'] as String, studentId: m['id'] as String, department: '');
  }).toList();
  final slotKeys = (payload['slotKeys'] as List<dynamic>).cast<String>();
  final slotLabels = (payload['slotLabels'] as List<dynamic>).cast<String>();
  final sessions = (payload['sessions'] as List<dynamic>).map((e) {
    final m = e as Map<String, dynamic>;
    return (
      id: m['id'] as String,
      raw: Map<String, bool>.from((m['raw'] as Map).map((k, v) => MapEntry(k as String, v as bool))),
      manual: Map<String, bool>.from((m['manual'] as Map).map((k, v) => MapEntry(k as String, v as bool))),
    );
  }).toList();
  final sessionById = {for (final s in sessions) s.id: s};

  final header = ['student_name', 'student_id', ...slotLabels];
  final rows = <List<String>>[header];
  for (final student in students) {
    final row = <String>[student.studentName, student.studentId];
    for (final key in slotKeys) {
      final session = sessionById[key];
      final raw = session?.raw ?? const {};
      final manual = session?.manual ?? const {};
      row.add(effectivePresent(manual, raw, student.studentId) ? '1' : '0');
    }
    rows.add(row);
  }
  return rows;
}

List<List<String>> _buildPercentageRows(Map<String, dynamic> payload) {
  final students = (payload['students'] as List<dynamic>).map((e) {
    final m = e as Map<String, dynamic>;
    return StudentModel(studentName: m['name'] as String, studentId: m['id'] as String, department: '');
  }).toList();
  final sessionMaps = (payload['sessionMaps'] as List<dynamic>).map((e) {
    final m = e as Map<String, dynamic>;
    return (
      raw: Map<String, bool>.from((m['raw'] as Map).map((k, v) => MapEntry(k as String, v as bool))),
      manual: Map<String, bool>.from((m['manual'] as Map).map((k, v) => MapEntry(k as String, v as bool))),
    );
  }).toList();
  final total = sessionMaps.length;
  final rows = <List<String>>[
    ['student_name', 'student_id', 'attendance_percentage'],
  ];
  for (final student in students) {
    var present = 0;
    for (final session in sessionMaps) {
      if (effectivePresent(session.manual, session.raw, student.studentId)) {
        present++;
      }
    }
    final pct = total == 0 ? 0.0 : (present / total) * 100;
    rows.add([student.studentName, student.studentId, pct.toStringAsFixed(1)]);
  }
  return rows;
}

Uint8List _rowsToCsvBytes(List<List<String>> rows) {
  return Uint8List.fromList(utf8.encode(const ListToCsvConverter().convert(rows)));
}

Uint8List _rowsToExcelBytes(List<List<String>> rows, String sheetName) {
  final excel = Excel.createExcel();
  final defaultName = excel.getDefaultSheet()!;
  excel.rename(defaultName, sheetName);
  final sheet = excel.sheets[sheetName]!;
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value = TextCellValue(rows[r][c]);
    }
  }
  return Uint8List.fromList(excel.encode()!);
}

Map<String, dynamic> _serializeGridContext({
  required CourseModel course,
  required List<AttendanceSlot> slots,
  required List<AttendanceSessionModel> sessions,
  required bool isMakeup,
}) {
  return {
    'students': course.students.map((s) => {'name': s.studentName, 'id': s.studentId}).toList(),
    'slotKeys': slots.map((s) => s.key).toList(),
    'slotLabels': slots.map((s) => sessionColumnLabel(s, isMakeup: isMakeup)).toList(),
    'sessions': sessions
        .map(
          (s) => {
            'id': s.sessionId,
            'raw': s.attendanceMapRaw,
            'manual': s.attendanceMapManual,
          },
        )
        .toList(),
  };
}

class AttendanceExportService {
  Future<Uint8List> buildGridCsv({
    required CourseModel course,
    required List<AttendanceSlot> slots,
    required List<AttendanceSessionModel> sessions,
    required bool isMakeup,
  }) async {
    final payload = _serializeGridContext(course: course, slots: slots, sessions: sessions, isMakeup: isMakeup);
    final rows = await compute(_buildGridRows, payload);
    return _rowsToCsvBytes(rows);
  }

  Future<Uint8List> buildPercentageCsv({
    required CourseModel course,
    required List<AttendanceSessionModel> normalSessions,
    required List<AttendanceSessionModel> makeupSessions,
  }) async {
    final payload = {
      'students': course.students.map((s) => {'name': s.studentName, 'id': s.studentId}).toList(),
      'sessionMaps': [...normalSessions, ...makeupSessions]
          .map((s) => {'raw': s.attendanceMapRaw, 'manual': s.attendanceMapManual})
          .toList(),
    };
    final rows = await compute(_buildPercentageRows, payload);
    return _rowsToCsvBytes(rows);
  }

  Future<Uint8List> buildSemesterExcel({
    required CourseModel course,
    required List<AttendanceSlot> normalSlots,
    required List<AttendanceSessionModel> normalSessions,
    required List<AttendanceSlot> makeupSlots,
    required List<AttendanceSessionModel> makeupSessions,
  }) async {
    final normalPayload = _serializeGridContext(
      course: course,
      slots: normalSlots,
      sessions: normalSessions,
      isMakeup: false,
    );
    final makeupPayload = _serializeGridContext(
      course: course,
      slots: makeupSlots,
      sessions: makeupSessions,
      isMakeup: true,
    );
    final normalRows = await compute(_buildGridRows, normalPayload);
    final makeupRows = await compute(_buildGridRows, makeupPayload);

    final excel = Excel.createExcel();
    final defaultName = excel.getDefaultSheet()!;
    excel.rename(defaultName, 'Normal');
    _writeRows(excel.sheets['Normal']!, normalRows);
    final makeupSheet = excel['Makeup'];
    _writeRows(makeupSheet, makeupRows);
    return Uint8List.fromList(excel.encode()!);
  }

  Future<Uint8List> buildPercentageExcel({
    required CourseModel course,
    required List<AttendanceSessionModel> normalSessions,
    required List<AttendanceSessionModel> makeupSessions,
  }) async {
    final payload = {
      'students': course.students.map((s) => {'name': s.studentName, 'id': s.studentId}).toList(),
      'sessionMaps': [...normalSessions, ...makeupSessions]
          .map((s) => {'raw': s.attendanceMapRaw, 'manual': s.attendanceMapManual})
          .toList(),
    };
    final rows = await compute(_buildPercentageRows, payload);
    return _rowsToExcelBytes(rows, 'Summary');
  }

  void _writeRows(Sheet sheet, List<List<String>> rows) {
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value = TextCellValue(rows[r][c]);
      }
    }
  }
}
