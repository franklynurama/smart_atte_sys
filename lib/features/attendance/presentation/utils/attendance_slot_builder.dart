import 'package:intl/intl.dart';

import '../../../courses/data/models/course_model.dart';
import '../../data/models/attendance_session_model.dart';

class AttendanceSlot {
  final String key;
  final DateTime date;
  final DateTime weekStartMonday;
  final String dayName;
  final String startTime;
  final String endTime;
  final int sessionIndex;

  const AttendanceSlot({
    required this.key,
    required this.date,
    required this.weekStartMonday,
    required this.dayName,
    required this.startTime,
    required this.endTime,
    required this.sessionIndex,
  });
}

class AttendanceSlotsBundle {
  final List<AttendanceSlot> slots;
  final Map<DateTime, List<AttendanceSlot>> grouped;

  const AttendanceSlotsBundle({
    required this.slots,
    required this.grouped,
  });
}

String dayNameFromWeekday(int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return 'Monday';
    case DateTime.tuesday:
      return 'Tuesday';
    case DateTime.wednesday:
      return 'Wednesday';
    case DateTime.thursday:
      return 'Thursday';
    case DateTime.friday:
      return 'Friday';
    case DateTime.saturday:
      return 'Saturday';
    case DateTime.sunday:
      return 'Sunday';
    default:
      return '';
  }
}

DateTime mondayOfWeek(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

int calendarDaysBetween(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

int weekIndexFromSemesterMonday({
  required DateTime semesterWeekMonday,
  required DateTime weekStartMonday,
}) {
  final sem = mondayOfWeek(
    DateTime(semesterWeekMonday.year, semesterWeekMonday.month, semesterWeekMonday.day),
  );
  final ws = mondayOfWeek(
    DateTime(weekStartMonday.year, weekStartMonday.month, weekStartMonday.day),
  );
  return (calendarDaysBetween(sem, ws) ~/ 7) + 1;
}

Map<DateTime, int> stableWeekNumbers({
  required List<DateTime> weekStarts,
  required DateTime semesterWeekMonday,
}) {
  final sorted = List<DateTime>.from(weekStarts)..sort();
  final numbers = <DateTime, int>{};
  var last = 0;
  for (final weekStart in sorted) {
    final raw = weekIndexFromSemesterMonday(
      semesterWeekMonday: semesterWeekMonday,
      weekStartMonday: weekStart,
    );
    final normalized = raw <= last ? last + 1 : raw;
    numbers[weekStart] = normalized;
    last = normalized;
  }
  return numbers;
}

int timeToMinutes(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return 0;
  final h = int.tryParse(parts[0]) ?? 0;
  final m = int.tryParse(parts[1]) ?? 0;
  return (h * 60) + m;
}

List<AttendanceSlot> buildAttendanceSlots({
  required CourseModel course,
  required List<AttendanceSessionModel> sessions,
  required bool isMakeup,
}) {
  final slots = <AttendanceSlot>[];
  for (final session in sessions) {
    DateTime? date;
    String startTime = '';
    String endTime = '';

    if (isMakeup) {
      final dateParts = session.date.split('-');
      if (dateParts.length == 3) {
        date = DateTime(
          int.tryParse(dateParts[0]) ?? 1970,
          int.tryParse(dateParts[1]) ?? 1,
          int.tryParse(dateParts[2]) ?? 1,
        );
      }
      startTime = session.startTimeHHmm;
      endTime = session.endTimeHHmm;
    } else {
      final parts = session.sessionId.split('_');
      if (parts.length == 2) {
        final dateParts = parts[0].split('-');
        if (dateParts.length == 3) {
          date = DateTime(
            int.tryParse(dateParts[0]) ?? 1970,
            int.tryParse(dateParts[1]) ?? 1,
            int.tryParse(dateParts[2]) ?? 1,
          );
        }
        startTime = parts[1];
      }
    }
    if (date == null || startTime.isEmpty) continue;
    final sessionDate = date;

    final matchingSessionIndex = course.sessions.indexWhere(
      (s) => s.dayOfWeek == sessionDate.weekday && s.startTimeHHmm == startTime,
    );
    final matched = matchingSessionIndex == -1 ? null : course.sessions[matchingSessionIndex];
    final effectiveEnd = endTime.isNotEmpty ? endTime : (matched?.endTimeHHmm ?? startTime);
    final weekStartMonday = mondayOfWeek(sessionDate);

    slots.add(
      AttendanceSlot(
        key: session.sessionId,
        date: sessionDate,
        weekStartMonday: weekStartMonday,
        dayName: dayNameFromWeekday(sessionDate.weekday),
        startTime: startTime,
        endTime: effectiveEnd,
        sessionIndex: matchingSessionIndex == -1 ? 1 : matchingSessionIndex + 1,
      ),
    );
  }
  slots.sort((a, b) {
    final w = a.weekStartMonday.compareTo(b.weekStartMonday);
    if (w != 0) return w;
    final d = a.date.weekday.compareTo(b.date.weekday);
    if (d != 0) return d;
    final t = timeToMinutes(a.startTime).compareTo(timeToMinutes(b.startTime));
    if (t != 0) return t;
    return a.sessionIndex.compareTo(b.sessionIndex);
  });
  return slots;
}

Map<DateTime, List<AttendanceSlot>> groupSlotsByWeek(List<AttendanceSlot> slots) {
  final grouped = <int, List<AttendanceSlot>>{};
  for (final slot in slots) {
    grouped.putIfAbsent(slot.weekStartMonday.millisecondsSinceEpoch, () => []).add(slot);
  }

  final ordered = grouped.entries.toList()
    ..sort((a, b) => a.value.first.weekStartMonday.compareTo(b.value.first.weekStartMonday));

  final result = <DateTime, List<AttendanceSlot>>{};
  for (final entry in ordered) {
    final weekSlots = List<AttendanceSlot>.from(entry.value)
      ..sort((a, b) {
        final d = a.date.weekday.compareTo(b.date.weekday);
        if (d != 0) return d;
        final t = timeToMinutes(a.startTime).compareTo(timeToMinutes(b.startTime));
        if (t != 0) return t;
        return a.sessionIndex.compareTo(b.sessionIndex);
      });
    result[weekSlots.first.weekStartMonday] = weekSlots;
  }
  return result;
}

AttendanceSlotsBundle resolveSlotsBundle({
  required CourseModel course,
  required List<AttendanceSessionModel> sessions,
  required bool isMakeup,
}) {
  final slots = buildAttendanceSlots(course: course, sessions: sessions, isMakeup: isMakeup);
  return AttendanceSlotsBundle(slots: slots, grouped: groupSlotsByWeek(slots));
}

String weekRangeLabel(DateTime weekStartMonday) {
  final monday = DateTime(weekStartMonday.year, weekStartMonday.month, weekStartMonday.day);
  final sunday = monday.add(const Duration(days: 6));
  final fmt = DateFormat('dd MMM yyyy');
  return '(${fmt.format(monday)} - ${fmt.format(sunday)})';
}

String sessionColumnLabel(AttendanceSlot slot, {required bool isMakeup}) {
  if (isMakeup) {
    final makeupDateFmt = DateFormat('dd MMM yyyy');
    return '${makeupDateFmt.format(slot.date)} (${slot.dayName.substring(0, 3)})\n${slot.startTime}-${slot.endTime}';
  }
  final dateFmt = DateFormat('dd MMM');
  return 'S${slot.sessionIndex} - ${slot.dayName.substring(0, 3)} (${dateFmt.format(slot.date)})\n${slot.startTime} - ${slot.endTime}';
}
