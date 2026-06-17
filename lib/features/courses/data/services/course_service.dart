import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/constants/constants.dart';
import '../../../../core/utils/date_utils.dart' as app_date;
import '../../domain/course_term.dart';
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
    required CourseTerm term,
    required String academicYearLabel,
    required int academicYearStart,
    required DateTime semesterStartDate,
    required DateTime semesterEndDate,
    required List<CourseSessionModel> sessions,
    required List<StudentModel> students,
  }) async {
    final duplicate = await _isDuplicateOffering(
      courseCode: courseCode,
      section: section,
      term: term,
      academicYearLabel: academicYearLabel,
    );
    if (duplicate) {
      throw StateError(
        'An active course with this code, section, term, and academic year already exists.',
      );
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
      AppConstants.termField: term.toFirestore(),
      AppConstants.academicYearLabelField: academicYearLabel,
      AppConstants.academicYearStartField: academicYearStart,
      AppConstants.statusField: CourseStatus.active.toFirestore(),
      AppConstants.archivedAtField: null,
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

  Future<void> deleteCourse(String courseId) async {
    final courseRef = _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId);

    final doc = await courseRef.get();
    if (!doc.exists) {
      throw StateError('Course not found.');
    }

    await _deleteAllDocumentsInCollection(courseRef.collection(AppConstants.studentsField));
    await _deleteAllDocumentsInCollection(courseRef.collection(AppConstants.normalAttendanceCollection));
    await _deleteAllDocumentsInCollection(courseRef.collection(AppConstants.makeupAttendanceCollection));
    await _deleteAllDocumentsInCollection(courseRef.collection(AppConstants.unverifiedRecordsCollection));
    await courseRef.delete();

    developer.log('Deleted course $courseId and all subcollections', name: 'CourseService');
  }

  /// Firestore does not cascade-delete subcollections; delete in batches (max 500 ops/batch).
  Future<void> _deleteAllDocumentsInCollection(
    CollectionReference<Map<String, dynamic>> collectionRef,
  ) async {
    const batchSize = 400;
    while (true) {
      final snap = await collectionRef.limit(batchSize).get();
      if (snap.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }

  Future<void> archiveCourse(String courseId) async {
    final ref = _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId);
    final doc = await ref.get();
    if (!doc.exists) {
      throw StateError('Course not found.');
    }
    final status = courseStatusFromFirestore((doc.data()?[AppConstants.statusField]) as String?);
    if (status == CourseStatus.archived) {
      throw StateError('Course is already archived.');
    }
    await ref.update({
      AppConstants.statusField: CourseStatus.archived.toFirestore(),
      AppConstants.archivedAtField: FieldValue.serverTimestamp(),
    });
  }

  Future<void> assertCourseNotArchived(String courseId) async {
    final doc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId)
        .get();
    if (!doc.exists) {
      throw StateError('Course not found.');
    }
    final status = courseStatusFromFirestore((doc.data()?[AppConstants.statusField]) as String?);
    if (status == CourseStatus.archived) {
      throw StateError('Course is archived and cannot be modified.');
    }
  }

  Future<bool> _isDuplicateOffering({
    required String courseCode,
    required String section,
    required CourseTerm term,
    required String academicYearLabel,
  }) async {
    final snap = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .where('courseCode', isEqualTo: courseCode.trim())
        .where('section', isEqualTo: section.trim())
        .where(AppConstants.termField, isEqualTo: term.toFirestore())
        .where(AppConstants.academicYearLabelField, isEqualTo: academicYearLabel.trim())
        .where(AppConstants.statusField, isEqualTo: CourseStatus.active.toFirestore())
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
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
            AppConstants.attendanceMapRawField: e.value,
            AppConstants.attendanceMapManualField: <String, bool>{},
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
      final data = d.data();
      final rawField = data[AppConstants.attendanceMapRawField] as Map<String, dynamic>?;
      final legacy = data[AppConstants.attendanceMapField] as Map<String, dynamic>?;
      final raw = rawField ?? legacy ?? <String, dynamic>{};
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

