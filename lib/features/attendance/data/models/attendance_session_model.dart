import '../../domain/attendance_merge.dart';

class AttendanceSessionModel {
  final String sessionId;
  final Map<String, bool> attendanceMapRaw;
  final Map<String, bool> attendanceMapManual;
  final bool isMakeup;
  final String date;
  final String startTimeHHmm;
  final String endTimeHHmm;

  const AttendanceSessionModel({
    required this.sessionId,
    required this.attendanceMapRaw,
    required this.attendanceMapManual,
    required this.isMakeup,
    required this.date,
    required this.startTimeHHmm,
    required this.endTimeHHmm,
  });

  /// Legacy alias — raw imported map.
  Map<String, bool> get attendanceMap => attendanceMapRaw;

  factory AttendanceSessionModel.fromMap({
    required String sessionId,
    required Map<String, dynamic> map,
    required bool isMakeup,
  }) {
    final legacy = parseBoolMap(map['attendanceMap'] as Map<String, dynamic>?);
    final raw = parseBoolMap(map['attendanceMapRaw'] as Map<String, dynamic>?);
    final manual = parseBoolMap(map['attendanceMapManual'] as Map<String, dynamic>?);
    final start = (map['startTime'] ?? map['startTimeHHmm'] ?? map['time'] ?? '') as String;
    final end = (map['endTime'] ?? map['endTimeHHmm'] ?? start) as String;
    return AttendanceSessionModel(
      sessionId: sessionId,
      isMakeup: isMakeup,
      attendanceMapRaw: raw.isNotEmpty ? raw : legacy,
      attendanceMapManual: manual,
      date: (map['date'] ?? '') as String,
      startTimeHHmm: start,
      endTimeHHmm: end,
    );
  }
}
