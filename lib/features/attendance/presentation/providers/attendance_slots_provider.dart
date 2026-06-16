import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../courses/data/models/course_model.dart';
import '../../data/models/attendance_session_model.dart';
import '../utils/attendance_slot_builder.dart';

class AttendanceSlotsRequest {
  final CourseModel course;
  final List<AttendanceSessionModel> sessions;
  final bool isMakeup;

  const AttendanceSlotsRequest({
    required this.course,
    required this.sessions,
    required this.isMakeup,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttendanceSlotsRequest &&
          course.courseId == other.course.courseId &&
          isMakeup == other.isMakeup &&
          _sessionSig(sessions) == _sessionSig(other.sessions);

  @override
  int get hashCode => Object.hash(course.courseId, isMakeup, _sessionSig(sessions));

  static String _sessionSig(List<AttendanceSessionModel> sessions) =>
      sessions.map((s) => s.sessionId).join('|');
}

final attendanceSlotsBundleProvider = Provider.autoDispose.family<AttendanceSlotsBundle, AttendanceSlotsRequest>(
  (ref, request) => resolveSlotsBundle(
    course: request.course,
    sessions: request.sessions,
    isMakeup: request.isMakeup,
  ),
);
