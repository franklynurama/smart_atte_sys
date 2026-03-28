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
        .map((snap) {
      return snap.docs.map((d) => CourseModel.fromDoc(courseId: d.id, data: d.data())).toList();
    });
  }

  Future<List<CourseModel>> getCoursesOnce() async {
    final snap = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs
        .map((d) => CourseModel.fromDoc(courseId: d.id, data: d.data()))
        .toList();
  }

  Future<CourseModel?> getCourseOnce(String courseId) async {
    final doc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId)
        .get();
    if (!doc.exists) return null;
    return CourseModel.fromDoc(courseId: doc.id, data: doc.data()!);
  }

  Future<String> createCourse({
    required String courseName,
    required String courseCode,
    required String abbreviation,
    required DateTime semesterStartDate,
    required DateTime semesterEndDate,
    required List<CourseSessionModel> sessions,
    required List<StudentModel> students,
  }) async {
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
    );
    final end = DateTime(
      semesterEndDate.year,
      semesterEndDate.month,
      semesterEndDate.day,
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
      'sessions': sessions.map((s) => s.toMap()).toList(),
      'students': students.map((s) => s.toMap()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      'semesterStartDate': Timestamp.fromDate(start),
      'semesterEndDate': Timestamp.fromDate(end),
      'attendanceRecords': attendanceRecords,
    });

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
}

