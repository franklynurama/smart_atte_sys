import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/constants/constants.dart';

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
      await _firestore.runTransaction((tx) async {
        final doc = await tx.get(courseRef);
        if (!doc.exists) {
          throw StateError('Course not found.');
        }

        final data = doc.data() as Map<String, dynamic>;
        final studentsRaw = (data['students'] ?? []) as List<dynamic>;
        final studentIds = studentsRaw
            .map((e) => (e as Map<String, dynamic>)['studentId']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList();

        final attendedSet = attendedStudentIds.toSet();
        final attendanceMap = <String, bool>{
          for (final id in studentIds) id: attendedSet.contains(id),
        };

        tx.update(courseRef, {'${AppConstants.attendanceRecordsField}.$recordKey': attendanceMap});
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
}

