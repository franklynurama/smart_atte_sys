import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AppDateUtils {
  /// Returns Monday=1 ... Sunday=7 to match common schedule inputs.
  static int dayOfWeekToInt(Day day) {
    switch (day) {
      case Day.monday:
        return 1;
      case Day.tuesday:
        return 2;
      case Day.wednesday:
        return 3;
      case Day.thursday:
        return 4;
      case Day.friday:
        return 5;
      case Day.saturday:
        return 6;
      case Day.sunday:
        return 7;
    }
  }

  static DateTime nextDateForDay(int targetDayOfWeek, DateTime from) {
    // targetDayOfWeek: 1..7 where Monday=1 ... Sunday=7
    final fromDay = from.weekday; // Monday=1..Sunday=7
    final diff = (targetDayOfWeek - fromDay) % 7;
    return DateTime(
      from.year,
      from.month,
      from.day,
    ).add(Duration(days: diff));
  }

  static String formatDateKey(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  static String twoDigits(int n) => n.toString().padLeft(2, '0');

  static String timeOfDayToHHmm(TimeOfDay time) {
    return '${twoDigits(time.hour)}:${twoDigits(time.minute)}';
  }

  static String attendanceRecordKey(DateTime date, {required TimeOfDay sessionStart}) {
    return '${formatDateKey(date)}_${timeOfDayToHHmm(sessionStart)}';
  }

  static TimeOfDay parseHHmm(String hhmm) {
    final parts = hhmm.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return TimeOfDay(hour: hour, minute: minute);
  }
}

enum Day { monday, tuesday, wednesday, thursday, friday, saturday, sunday }

