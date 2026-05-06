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

  /// How far into the future to pre-generate attendance records (days).
  static const int defaultAttendanceHorizonDays = 28;
}

