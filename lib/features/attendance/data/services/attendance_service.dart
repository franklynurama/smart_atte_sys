import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/constants/constants.dart';
import '../../../courses/data/models/student_model.dart';
import '../models/attendance_session_model.dart';
import '../models/unverified_record_model.dart';

class AttendanceService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  AttendanceService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('User not authenticated.');
    return user.uid;
  }

  Future<void> updateAttendanceRecord({
    required String courseId,
    required String recordKey,
    required List<String> attendedStudentIds,
  }) async {
    final courseRef = _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId);

    developer.log(
      'updateAttendanceRecord start courseId=$courseId recordKey=$recordKey attended=${attendedStudentIds.length}',
      name: 'AttendanceService',
    );
    try {
      final studentIds = (await getStudents(courseId)).map((s) => s.studentId).where((id) => id.isNotEmpty).toList();
      await _firestore.runTransaction((tx) async {
        final doc = await tx.get(courseRef);
        if (!doc.exists) {
          throw StateError('Course not found.');
        }

        final attendedSet = attendedStudentIds.toSet();
        final attendanceMap = <String, bool>{
          for (final id in studentIds) id: attendedSet.contains(id),
        };

        final normalDoc = courseRef
            .collection(AppConstants.normalAttendanceCollection)
            .doc(recordKey);
        tx.set(
          normalDoc,
          <String, dynamic>{
            'sessionId': recordKey,
            'attendanceMap': attendanceMap,
            'updatedAt': FieldValue.serverTimestamp(),
            'isMakeup': false,
          },
          SetOptions(merge: true),
        );
      });
      developer.log(
        'updateAttendanceRecord success courseId=$courseId recordKey=$recordKey',
        name: 'AttendanceService',
      );
    } catch (e, st) {
      developer.log(
        'updateAttendanceRecord failed',
        name: 'AttendanceService',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  CollectionReference<Map<String, dynamic>> _courseCollection(String courseId) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId)
        .collection(AppConstants.studentsField);
  }

  Future<List<StudentModel>> getStudents(String courseId) async {
    final snap = await _courseCollection(courseId).get();
    return snap.docs.map((d) => StudentModel.fromMap(d.data())).toList();
  }

  Future<void> addStudentToCourse({
    required String courseId,
    required StudentModel student,
  }) async {
    final ref = _courseCollection(courseId).doc(student.studentId);
    final existing = await ref.get();
    if (existing.exists) {
      throw StateError('Student with ID ${student.studentId} already exists in this course.');
    }
    await ref.set({
      ...student.toMap(),
      AppConstants.createdAtField: FieldValue.serverTimestamp(),
    });
  }

  Future<List<AttendanceSessionModel>> getNormalAttendanceSessions(String courseId) async {
    final snap = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId)
        .collection(AppConstants.normalAttendanceCollection)
        .get();
    return snap.docs
        .map((d) => AttendanceSessionModel.fromMap(sessionId: d.id, map: d.data(), isMakeup: false))
        .toList()
      ..sort((a, b) => a.sessionId.compareTo(b.sessionId));
  }

  Future<List<AttendanceSessionModel>> getMakeupAttendanceSessions(String courseId) async {
    final snap = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId)
        .collection(AppConstants.makeupAttendanceCollection)
        .get();
    return snap.docs
        .map((d) => AttendanceSessionModel.fromMap(sessionId: d.id, map: d.data(), isMakeup: true))
        .toList()
      ..sort((a, b) => a.sessionId.compareTo(b.sessionId));
  }

  Future<String> createMakeupAttendanceSession({
    required String courseId,
    required String date,
    required String startTime,
    required String endTime,
    required List<String> attendedStudentIds,
  }) async {
    final students = await getStudents(courseId);
    final attendedSet = attendedStudentIds.toSet();
    final attendanceMap = <String, bool>{
      for (final s in students) s.studentId: attendedSet.contains(s.studentId),
    };
    final sessionId = 'makeup_${date}_${startTime}_$endTime';
    final doc = _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId)
        .collection(AppConstants.makeupAttendanceCollection)
        .doc(sessionId);
    final existing = await doc.get();
    if (existing.exists) {
      throw StateError('Makeup session already exists for this course/date/time.');
    }
    await doc.set({
      'sessionId': sessionId,
      'date': date,
      'startTime': startTime,
      'endTime': endTime,
      'attendanceMap': attendanceMap,
      'updatedAt': FieldValue.serverTimestamp(),
      'isMakeup': true,
    }, SetOptions(merge: true));
    return sessionId;
  }

  Future<List<UnverifiedRecordModel>> getUnverifiedRecords(String courseId) async {
    final snap = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId)
        .collection(AppConstants.unverifiedRecordsCollection)
        .orderBy(AppConstants.createdAtField, descending: true)
        .get();
    return snap.docs.map((d) => UnverifiedRecordModel.fromMap(id: d.id, map: d.data())).toList();
  }

  Future<void> addUnverifiedRecord({
    required String courseId,
    required String studentName,
    required String studentId,
    required String date,
    required String time,
    required String rawSessionId,
    required bool isMakeup,
  }) async {
    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId)
        .collection(AppConstants.unverifiedRecordsCollection)
        .add({
      'studentName': studentName,
      'studentId': studentId,
      'date': date,
      'time': time,
      'rawSessionId': rawSessionId,
      'isMakeup': isMakeup,
      'processed': false,
      AppConstants.createdAtField: FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteUnverifiedRecord({
    required String courseId,
    required String recordId,
  }) async {
    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId)
        .collection(AppConstants.unverifiedRecordsCollection)
        .doc(recordId)
        .delete();
  }

  Future<void> saveAttendanceMapBatch({
    required String courseId,
    required bool isMakeup,
    required Map<String, Map<String, bool>> sessions,
  }) async {
    if (sessions.isEmpty) return;
    final courseRef = _firestore
        .collection(AppConstants.usersCollection)
        .doc(_uid)
        .collection(AppConstants.coursesCollection)
        .doc(courseId);
    final targetCollection = isMakeup
        ? AppConstants.makeupAttendanceCollection
        : AppConstants.normalAttendanceCollection;
    final batch = _firestore.batch();
    for (final entry in sessions.entries) {
      final sessionId = entry.key;
      final attendanceMap = entry.value;
      final docRef = courseRef.collection(targetCollection).doc(sessionId);
      batch.set(
        docRef,
        {
          'sessionId': sessionId,
          'attendanceMap': attendanceMap,
          'updatedAt': FieldValue.serverTimestamp(),
          'isMakeup': isMakeup,
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }
}

