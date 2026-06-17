import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../courses/presentation/providers/course_provider.dart';
import '../providers/attendance_provider.dart';

/// Clears decrypt inputs and mutation state after Update / Download / Both.
/// Do not call after decrypt-only ([AttendanceDecryptMessages.decryptOk]).
void resetAfterDecryptProcessComplete(WidgetRef ref, {String? courseId}) {
  if (courseId != null) {
    ref.invalidate(coursesProvider);
    ref.invalidate(normalAttendanceSessionsProvider(courseId));
    ref.invalidate(makeupAttendanceSessionsProvider(courseId));
    ref.invalidate(unverifiedRecordsProvider(courseId));
  }
  ref.read(attendanceGridEditProvider.notifier).clear();
  ref.read(encryptedFileProvider.notifier).clear();
  ref.read(privateKeyFileProvider.notifier).clear();
  ref.read(attendanceMutationProvider.notifier).resetDecryptFlow();
}

void resetAfterCsvAttendanceUpdate(WidgetRef ref, String courseId) {
  ref.invalidate(coursesProvider);
  ref.invalidate(normalAttendanceSessionsProvider(courseId));
  ref.invalidate(makeupAttendanceSessionsProvider(courseId));
  ref.invalidate(unverifiedRecordsProvider(courseId));
  ref.read(attendanceGridEditProvider.notifier).clear();
}
