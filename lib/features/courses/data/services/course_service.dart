import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/constants/constants.dart';
import '../../../../core/utils/date_utils.dart' as app_date;
import '../models/course_model.dart';
import '../models/student_model.dart';

class CourseService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CourseService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('User not authenticated.');
    return user.uid;
  }

  Stream<List<CourseModel>> watchCourses() {
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snap) async {
      final out = <CourseModel>[];
      for (final d in snap.docs) {
        out.add(await _hydrateCourse(d.id, d.data()));
      }
      return out;
    });
  }

  Future<List<CourseModel>> getCoursesOnce() async {
    final snap = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .orderBy('createdAt', descending: true)
        .get();
    final out = <CourseModel>[];
    for (final d in snap.docs) {
      out.add(await _hydrateCourse(d.id, d.data()));
    }
    return out;
  }

  Future<CourseModel?> getCourseOnce(String courseId) async {
    final doc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId)
        .get();
    if (!doc.exists) return null;
    return _hydrateCourse(doc.id, doc.data()!);
  }

  Future<String> createCourse({
    required String courseName,
    required String courseCode,
    required String abbreviation,
    required String section,
    required DateTime semesterStartDate,
    required DateTime semesterEndDate,
    required List<CourseSessionModel> sessions,
    required List<StudentModel> students,
  }) async {
    final duplicate = await _isDuplicateCourseCodeAndSection(
      courseCode: courseCode,
      section: section,
    );
    if (duplicate) {
      throw StateError('A course with the same code and section already exists.');
    }

    final courseRef = _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc();

    final createdAt = DateTime.now();
    final attendanceRecords = <String, Map<String, bool>>{};

    final start = DateTime(
      semesterStartDate.year,
      semesterStartDate.month,
      semesterStartDate.day,
      0,
      0,
      0,
      0,
      0,
    );
    final end = DateTime(
      semesterEndDate.year,
      semesterEndDate.month,
      semesterEndDate.day,
      23,
      59,
      59,
      999,
      999,
    );

    for (DateTime date = start; !date.isAfter(end); date = date.add(const Duration(days: 1))) {
      for (final session in sessions) {
        if (date.weekday != session.dayOfWeek) continue;
        final startTime = app_date.AppDateUtils.parseHHmm(session.startTimeHHmm);
        final recordKey = app_date.AppDateUtils.attendanceRecordKey(date, sessionStart: startTime);
        attendanceRecords[recordKey] = {
          for (final s in students) s.studentId: false,
        };
      }
    }

    developer.log(
      'Writing course doc ${courseRef.id} (${students.length} students, ${sessions.length} sessions, ${attendanceRecords.length} attendance keys)',
      name: 'CourseService',
    );

    await courseRef.set({
      'courseName': courseName,
      'courseCode': courseCode,
      'abbreviation': abbreviation,
      'section': section,
      'sessions': sessions.map((s) => s.toMap()).toList(),
      'students': students.map((s) => s.toMap()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      'semesterStartDate': Timestamp.fromDate(start),
      'semesterEndDate': Timestamp.fromDate(end),
    });

    await _seedStudentsSubcollection(
      courseId: courseRef.id,
      students: students,
    );
    await _seedNormalAttendanceSubcollection(
      courseId: courseRef.id,
      attendanceRecords: attendanceRecords,
    );

    return courseRef.id;
  }

  Future<void> deleteCourse(String courseId) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId)
        .delete();
  }

  Future<bool> _isDuplicateCourseCodeAndSection({
    required String courseCode,
    required String section,
  }) async {
    final snap = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .where('courseCode', isEqualTo: courseCode.trim())
        .where('section', isEqualTo: section.trim())
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<void> migrateLegacyCoursesToSubcollections() async {
    final coursesSnap = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .get();

    for (final courseDoc in coursesSnap.docs) {
      final data = courseDoc.data();
      final studentsRaw = (data[AppConstants.studentsField] ?? const []) as List<dynamic>;
      final students = studentsRaw
          .whereType<Map<String, dynamic>>()
          .map(StudentModel.fromMap)
          .toList();
      final attendanceRaw = (data[AppConstants.attendanceRecordsField] ?? const <String, dynamic>{})
          as Map<String, dynamic>;
      final attendanceRecords = <String, Map<String, bool>>{};
      for (final entry in attendanceRaw.entries) {
        final inner = (entry.value as Map<String, dynamic>? ?? const <String, dynamic>{});
        attendanceRecords[entry.key] = inner.map((k, v) => MapEntry(k, (v as bool?) ?? false));
      }

      final courseRef = _firestore
          .collection(AppConstants.usersCollection)
          .doc(_uid)
          .collection(AppConstants.coursesCollection)
          .doc(courseDoc.id);
      final studentsCol = courseRef.collection(AppConstants.studentsField);
      final normalCol = courseRef.collection(AppConstants.normalAttendanceCollection);

      // Migration is triggered during provider build; keep it non-destructive by
      // seeding only when subcollections are empty.
      final existingStudents = await studentsCol.limit(1).get();
      if (existingStudents.docs.isEmpty) {
        await _seedStudentsSubcollection(courseId: courseDoc.id, students: students);
      }

      final existingNormal = await normalCol.limit(1).get();
      if (existingNormal.docs.isEmpty) {
        await _seedNormalAttendanceSubcollection(
          courseId: courseDoc.id,
          attendanceRecords: attendanceRecords,
        );
      }
    }
  }

  Future<void> _seedStudentsSubcollection({
    required String courseId,
    required List<StudentModel> students,
  }) async {
    if (students.isEmpty) return;
    final batch = _firestore.batch();
    final studentsCol = _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId)
        .collection(AppConstants.studentsField);
    for (final s in students) {
      final ref = studentsCol.doc(s.studentId);
      batch.set(
        ref,
        {
          ...s.toMap(),
          AppConstants.createdAtField: FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> _seedNormalAttendanceSubcollection({
    required String courseId,
    required Map<String, Map<String, bool>> attendanceRecords,
  }) async {
    if (attendanceRecords.isEmpty) return;
    final normalCol = _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId)
        .collection(AppConstants.normalAttendanceCollection);

    final entries = attendanceRecords.entries.toList();
    for (int i = 0; i < entries.length; i += 400) {
      final chunk = entries.skip(i).take(400);
      final batch = _firestore.batch();
      for (final e in chunk) {
        final ref = normalCol.doc(e.key);
        batch.set(
          ref,
          <String, dynamic>{
            'sessionId': e.key,
            'attendanceMap': e.value,
            'updatedAt': FieldValue.serverTimestamp(),
            'isMigrated': true,
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }

  Future<CourseModel> _hydrateCourse(String courseId, Map<String, dynamic> data) async {
    final studentsSnap = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId)
        .collection(AppConstants.studentsField)
        .get();
    final students = studentsSnap.docs.map((d) => StudentModel.fromMap(d.data())).toList();

    final normalSnap = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId)
        .collection(AppConstants.normalAttendanceCollection)
        .get();
    final subAttendance = <String, Map<String, bool>>{};
    for (final d in normalSnap.docs) {
      final raw = (d.data()['attendanceMap'] as Map<String, dynamic>? ?? <String, dynamic>{});
      subAttendance[d.id] = raw.map((k, v) => MapEntry(k, (v as bool?) ?? false));
    }

    final merged = <String, dynamic>{...data};
    if (students.isNotEmpty) {
      merged[AppConstants.studentsField] = students.map((e) => e.toMap()).toList();
    }
    if (subAttendance.isNotEmpty) {
      merged[AppConstants.attendanceRecordsField] = subAttendance;
    }
    return CourseModel.fromDoc(courseId: courseId, data: merged);
  }
}

