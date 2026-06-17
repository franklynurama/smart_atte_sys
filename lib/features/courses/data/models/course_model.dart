import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/course_term.dart';
import 'student_model.dart';

class CourseSessionModel {
  /// Monday=1 ... Sunday=7.
  final int dayOfWeek;
  final String startTimeHHmm;
  final String endTimeHHmm;

  const CourseSessionModel({
    required this.dayOfWeek,
    required this.startTimeHHmm,
    required this.endTimeHHmm,
  });

  Map<String, dynamic> toMap() => <String, dynamic>{
        'dayOfWeek': dayOfWeek,
        'startTime': startTimeHHmm,
        'endTime': endTimeHHmm,
      };

  static CourseSessionModel fromMap(Map<String, dynamic> map) {
    return CourseSessionModel(
      dayOfWeek: (map['dayOfWeek'] ?? 1) as int,
      startTimeHHmm: (map['startTime'] ?? '00:00') as String,
      endTimeHHmm: (map['endTime'] ?? '00:00') as String,
    );
  }
}

class CourseModel {
  final String courseId;
  final String courseName;
  final String courseCode;
  final String abbreviation;
  final String section;
  final List<CourseSessionModel> sessions;
  final List<StudentModel> students;
  final DateTime createdAt;
  final DateTime semesterStartDate;
  final DateTime semesterEndDate;
  final Map<String, Map<String, bool>> attendanceRecords;
  final CourseTerm term;
  final String academicYearLabel;
  final int academicYearStart;
  final CourseStatus status;
  final DateTime? archivedAt;

  const CourseModel({
    required this.courseId,
    required this.courseName,
    required this.courseCode,
    required this.abbreviation,
    required this.section,
    required this.sessions,
    required this.students,
    required this.createdAt,
    required this.semesterStartDate,
    required this.semesterEndDate,
    required this.attendanceRecords,
    required this.term,
    required this.academicYearLabel,
    required this.academicYearStart,
    required this.status,
    required this.archivedAt,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'courseName': courseName,
      'courseCode': courseCode,
      'abbreviation': abbreviation,
      'section': section,
      'sessions': sessions.map((s) => s.toMap()).toList(),
      'students': students.map((s) => s.toMap()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      'semesterStartDate': Timestamp.fromDate(semesterStartDate),
      'semesterEndDate': Timestamp.fromDate(semesterEndDate),
      'attendanceRecords': attendanceRecords,
      'term': term.toFirestore(),
      'academicYearLabel': academicYearLabel,
      'academicYearStart': academicYearStart,
      'status': status.toFirestore(),
      'archivedAt': archivedAt == null ? null : Timestamp.fromDate(archivedAt!),
    };
  }

  static CourseModel fromDoc({
    required String courseId,
    required Map<String, dynamic> data,
  }) {
    final createdAtTs = data['createdAt'];
    final createdAt = createdAtTs is Timestamp ? createdAtTs.toDate() : DateTime.now();
    final semesterStartTs = data['semesterStartDate'];
    final semesterEndTs = data['semesterEndDate'];
    final semesterStartDate =
        semesterStartTs is Timestamp ? semesterStartTs.toDate() : DateTime.now();
    final semesterEndDate =
        semesterEndTs is Timestamp ? semesterEndTs.toDate() : DateTime.now();
    final archivedAtTs = data['archivedAt'];
    final archivedAt = archivedAtTs is Timestamp ? archivedAtTs.toDate() : null;

    final sessionsRaw = (data['sessions'] ?? []) as List<dynamic>;
    final sessions = sessionsRaw
        .map((e) => CourseSessionModel.fromMap(e as Map<String, dynamic>))
        .toList();

    final studentsRaw = (data['students'] ?? []) as List<dynamic>;
    final students =
        studentsRaw.map((e) => StudentModel.fromMap(e as Map<String, dynamic>)).toList();

    final attendanceRaw = (data['attendanceRecords'] ?? {}) as Map<String, dynamic>;
    final attendanceRecords = <String, Map<String, bool>>{};
    for (final entry in attendanceRaw.entries) {
      final inner = entry.value as Map<String, dynamic>? ?? {};
      attendanceRecords[entry.key] = inner.map((k, v) => MapEntry(k, (v as bool?) ?? false));
    }

    return CourseModel(
      courseId: courseId,
      courseName: (data['courseName'] ?? '') as String,
      courseCode: (data['courseCode'] ?? '') as String,
      abbreviation: (data['abbreviation'] ?? '') as String,
      section: (data['section'] ?? '') as String,
      sessions: sessions,
      students: students,
      createdAt: createdAt,
      semesterStartDate: semesterStartDate,
      semesterEndDate: semesterEndDate,
      attendanceRecords: attendanceRecords,
      term: courseTermFromFirestore(data['term'] as String?),
      academicYearLabel: (data['academicYearLabel'] ?? 'LEGACY') as String,
      academicYearStart: (data['academicYearStart'] ?? 0) as int,
      status: courseStatusFromFirestore(data['status'] as String?),
      archivedAt: archivedAt,
    );
  }
}

