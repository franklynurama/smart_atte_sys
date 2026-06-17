class AppConstants {
  static const String usersCollection = 'users';
  static const String coursesCollection = 'courses';
  static const String attendanceRecordsField = 'attendanceRecords';
  static const String studentsField = 'students';
  static const String sectionField = 'section';
  static const String normalAttendanceCollection = 'normalAttendance';
  static const String makeupAttendanceCollection = 'makeupAttendance';
  static const String unverifiedRecordsCollection = 'unverifiedRecords';
  static const String createdAtField = 'createdAt';
  static const String attendanceMapRawField = 'attendanceMapRaw';
  static const String attendanceMapManualField = 'attendanceMapManual';
  static const String attendanceMapField = 'attendanceMap';
  static const String termField = 'term';
  static const String academicYearLabelField = 'academicYearLabel';
  static const String academicYearStartField = 'academicYearStart';
  static const String statusField = 'status';
  static const String archivedAtField = 'archivedAt';

  /// How far into the future to pre-generate attendance records (days).
  static const int defaultAttendanceHorizonDays = 28;
}

