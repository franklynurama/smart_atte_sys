import 'package:flutter/material.dart';

enum AttendanceViewMode {
  imported,
  adjustments,
  finalAttendance,
}

extension AttendanceViewModeX on AttendanceViewMode {
  String get title => switch (this) {
        AttendanceViewMode.imported => 'Imported',
        AttendanceViewMode.adjustments => 'Adjustments',
        AttendanceViewMode.finalAttendance => 'Final Attendance',
      };

  String get description => switch (this) {
        AttendanceViewMode.imported => 'Attendance as received from uploads and decrypt.',
        AttendanceViewMode.adjustments => 'Review, correct, and resolve unverified records.',
        AttendanceViewMode.finalAttendance => 'Official record for reporting and exports.',
      };

  IconData get icon => switch (this) {
        AttendanceViewMode.imported => Icons.cloud_download_outlined,
        AttendanceViewMode.adjustments => Icons.edit_note_outlined,
        AttendanceViewMode.finalAttendance => Icons.fact_check_outlined,
      };
}
