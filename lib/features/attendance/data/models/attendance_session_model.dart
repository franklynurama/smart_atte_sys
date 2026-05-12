class AttendanceSessionModel {
  final String sessionId;
  final Map<String, bool> attendanceMap;
  final bool isMakeup;
  final String date;
  final String startTimeHHmm;
  final String endTimeHHmm;

  const AttendanceSessionModel({
    required this.sessionId,
    required this.attendanceMap,
    required this.isMakeup,
    required this.date,
    required this.startTimeHHmm,
    required this.endTimeHHmm,
  });

  factory AttendanceSessionModel.fromMap({
    required String sessionId,
    required Map<String, dynamic> map,
    required bool isMakeup,
  }) {
    final raw = (map['attendanceMap'] as Map<String, dynamic>? ?? <String, dynamic>{});
    final start = (map['startTime'] ?? map['startTimeHHmm'] ?? map['time'] ?? '') as String;
    final end = (map['endTime'] ?? map['endTimeHHmm'] ?? start) as String;
    return AttendanceSessionModel(
      sessionId: sessionId,
      isMakeup: isMakeup,
      attendanceMap: raw.map((k, v) => MapEntry(k, (v as bool?) ?? false)),
      date: (map['date'] ?? '') as String,
      startTimeHHmm: start,
      endTimeHHmm: end,
    );
  }
}
