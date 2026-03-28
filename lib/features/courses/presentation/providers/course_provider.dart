import 'dart:developer' as developer;

import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/csv_parser.dart';
import '../../data/models/course_model.dart';
import '../../data/models/student_model.dart';
import '../../data/services/course_service.dart';

class CoursesNotifier extends AsyncNotifier<List<CourseModel>> {
  final CourseService _service = CourseService();

  @override
  Future<List<CourseModel>> build() async {
    return _service.getCoursesOnce();
  }
}

final coursesProvider = AsyncNotifierProvider<CoursesNotifier, List<CourseModel>>(
  () => CoursesNotifier(),
);

class SelectedCourseState {
  final String? courseId;
  const SelectedCourseState({required this.courseId});
}

class SelectedCourseNotifier extends StateNotifier<SelectedCourseState> {
  SelectedCourseNotifier() : super(const SelectedCourseState(courseId: null));

  void select(String? courseId) => state = SelectedCourseState(courseId: courseId);
}

final selectedCourseProvider = StateNotifierProvider<SelectedCourseNotifier, SelectedCourseState>(
  (ref) => SelectedCourseNotifier(),
);

class CourseDraftState {
  final String courseName;
  final String courseCode;
  final String abbreviation;
  final List<CourseSessionModel> sessions;
  final DateTime? semesterStartDate;
  final DateTime? semesterEndDate;
  final List<StudentModel> students;
  final bool isLoadingStudents;
  final String? errorMessage;

  const CourseDraftState({
    required this.courseName,
    required this.courseCode,
    required this.abbreviation,
    required this.sessions,
    required this.semesterStartDate,
    required this.semesterEndDate,
    required this.students,
    required this.isLoadingStudents,
    required this.errorMessage,
  });

  factory CourseDraftState.initial() => const CourseDraftState(
        courseName: '',
        courseCode: '',
        abbreviation: '',
        // One default session so "Create Course" is usable without an extra tap.
        sessions: [
          CourseSessionModel(dayOfWeek: 1, startTimeHHmm: '08:00', endTimeHHmm: '09:00'),
        ],
        semesterStartDate: null,
        semesterEndDate: null,
        students: [],
        isLoadingStudents: false,
        errorMessage: null,
      );

  CourseDraftState copyWith({
    String? courseName,
    String? courseCode,
    String? abbreviation,
    List<CourseSessionModel>? sessions,
    DateTime? semesterStartDate,
    DateTime? semesterEndDate,
    List<StudentModel>? students,
    bool? isLoadingStudents,
    String? errorMessage, // pass null to clear
  }) {
    return CourseDraftState(
      courseName: courseName ?? this.courseName,
      courseCode: courseCode ?? this.courseCode,
      abbreviation: abbreviation ?? this.abbreviation,
      sessions: sessions ?? this.sessions,
      semesterStartDate: semesterStartDate ?? this.semesterStartDate,
      semesterEndDate: semesterEndDate ?? this.semesterEndDate,
      students: students ?? this.students,
      isLoadingStudents: isLoadingStudents ?? this.isLoadingStudents,
      errorMessage: errorMessage,
    );
  }
}

class CourseDraftNotifier extends StateNotifier<CourseDraftState> {
  CourseDraftNotifier() : super(CourseDraftState.initial());

  void setCourseName(String v) => state = state.copyWith(courseName: v, errorMessage: null);
  void setCourseCode(String v) => state = state.copyWith(courseCode: v, errorMessage: null);
  void setAbbreviation(String v) => state = state.copyWith(abbreviation: v, errorMessage: null);
  void setSemesterStartDate(DateTime v) => state = state.copyWith(semesterStartDate: v, errorMessage: null);
  void setSemesterEndDate(DateTime v) => state = state.copyWith(semesterEndDate: v, errorMessage: null);

  void addSession() {
    if (state.sessions.length >= 3) return;
    // Default session: Monday 08:00-09:00
    state = state.copyWith(
      sessions: [
        ...state.sessions,
        const CourseSessionModel(dayOfWeek: 1, startTimeHHmm: '08:00', endTimeHHmm: '09:00'),
      ],
      errorMessage: null,
    );
  }

  void removeSessionAt(int index) {
    final newSessions = [...state.sessions]..removeAt(index);
    state = state.copyWith(sessions: newSessions, errorMessage: null);
  }

  void updateSession(int index, {int? dayOfWeek, String? startTimeHHmm, String? endTimeHHmm}) {
    final newSessions = [...state.sessions];
    final old = newSessions[index];
    newSessions[index] = CourseSessionModel(
      dayOfWeek: dayOfWeek ?? old.dayOfWeek,
      startTimeHHmm: startTimeHHmm ?? old.startTimeHHmm,
      endTimeHHmm: endTimeHHmm ?? old.endTimeHHmm,
    );
    state = state.copyWith(sessions: newSessions, errorMessage: null);
  }

  Future<void> loadStudentsFromFileBytes({
    required Uint8List bytes,
    required String? fileName,
  }) async {
    state = state.copyWith(isLoadingStudents: true, errorMessage: null);
    try {
      final lower = (fileName ?? '').toLowerCase();
      final ext = lower.contains('.') ? lower.split('.').last : '';

      final students = await _parseStudents(bytes: bytes, extension: ext);
      if (students.isEmpty) {
        developer.log(
          'Student file parsed but no rows: $fileName',
          name: 'CourseDraftNotifier',
        );
        state = state.copyWith(isLoadingStudents: false, errorMessage: 'No students found in file.');
        return;
      }

      developer.log('Loaded ${students.length} students from $fileName', name: 'CourseDraftNotifier');
      state = state.copyWith(isLoadingStudents: false, students: students, errorMessage: null);
    } catch (e, st) {
      developer.log('parse students failed', name: 'CourseDraftNotifier', error: e, stackTrace: st);
      state = state.copyWith(
        isLoadingStudents: false,
        errorMessage: 'Failed to parse students: $e',
      );
    }
  }

  Future<List<StudentModel>> _parseStudents({
    required Uint8List bytes,
    required String extension,
  }) async {
    if (extension == 'xlsx' || extension == 'xls') {
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables.isNotEmpty ? excel.tables.values.first : null;
      if (sheet == null) return [];

      final rows = sheet.rows.map((r) => r.map((c) => c?.value?.toString().trim() ?? '').toList()).toList();
      if (rows.isEmpty) return [];

      final header = rows.first;
      final idxName = header.indexWhere((h) => h.toLowerCase().contains('name'));
      final idxId = header.indexWhere((h) => h.toLowerCase().contains('student id') || h.toLowerCase() == 'studentid');
      final idxDept = header.indexWhere((h) => h.toLowerCase().contains('department'));
      if (idxId == -1) return [];

      final students = <StudentModel>[];
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        final id = row.length > idxId ? row[idxId] : '';
        if (id.isEmpty) continue;
        final name = idxName != -1 && row.length > idxName ? row[idxName] : id;
        final dept = idxDept != -1 && row.length > idxDept ? row[idxDept] : '';
        students.add(StudentModel(studentName: name, studentId: id, department: dept));
      }
      return students;
    }

    // Default CSV parsing.
    final parsed = await CsvParser.parseCsvBytes(bytes);
    if (parsed.isEmpty) return [];

    final header = parsed.first;
    final idxName = header.indexWhere((h) => h.toLowerCase().contains('name'));
    final idxId = header.indexWhere((h) => h.toLowerCase().contains('student id') || h.toLowerCase() == 'studentid');
    final idxDept = header.indexWhere((h) => h.toLowerCase().contains('department'));
    if (idxId == -1) return [];

    final students = <StudentModel>[];
    for (int i = 1; i < parsed.length; i++) {
      final row = parsed[i];
      final id = row.length > idxId ? row[idxId] : '';
      if (id.isEmpty) continue;
      final name = idxName != -1 && row.length > idxName ? row[idxName] : id;
      final dept = idxDept != -1 && row.length > idxDept ? row[idxDept] : '';
      students.add(StudentModel(studentName: name, studentId: id, department: dept));
    }
    return students;
  }

  void reset() => state = CourseDraftState.initial();
}

final courseDraftProvider =
    StateNotifierProvider<CourseDraftNotifier, CourseDraftState>((ref) => CourseDraftNotifier());

class CourseMutationState {
  final bool isLoading;
  final String? errorMessage;
  /// Set after successful create; clear with [CourseMutationNotifier.clearFeedback].
  final String? successMessage;

  const CourseMutationState({
    required this.isLoading,
    this.errorMessage,
    this.successMessage,
  });

  factory CourseMutationState.initial() => const CourseMutationState(
        isLoading: false,
        errorMessage: null,
        successMessage: null,
      );
}

class CourseMutationNotifier extends AsyncNotifier<CourseMutationState> {
  final CourseService _service = CourseService();

  @override
  Future<CourseMutationState> build() async {
    return CourseMutationState.initial();
  }

  Future<void> createCourse() async {
    final draft = ref.read(courseDraftProvider);
    if (draft.courseName.trim().isEmpty) {
      state = const AsyncValue.data(
        CourseMutationState(isLoading: false, errorMessage: 'Course name is required.', successMessage: null),
      );
      return;
    }
    if (draft.courseCode.trim().isEmpty) {
      state = const AsyncValue.data(
        CourseMutationState(isLoading: false, errorMessage: 'Course code is required.', successMessage: null),
      );
      return;
    }
    if (draft.sessions.isEmpty || draft.sessions.length > 3) {
      state = const AsyncValue.data(
        CourseMutationState(isLoading: false, errorMessage: 'Add 1–3 sessions per week.', successMessage: null),
      );
      return;
    }
    if (draft.semesterStartDate == null || draft.semesterEndDate == null) {
      state = const AsyncValue.data(
        CourseMutationState(
          isLoading: false,
          errorMessage: 'Select semester start and end dates.',
          successMessage: null,
        ),
      );
      return;
    }
    if (draft.semesterEndDate!.isBefore(draft.semesterStartDate!)) {
      state = const AsyncValue.data(
        CourseMutationState(
          isLoading: false,
          errorMessage: 'Semester end date cannot be before start date.',
          successMessage: null,
        ),
      );
      return;
    }
    if (draft.students.isEmpty) {
      state = const AsyncValue.data(
        CourseMutationState(
          isLoading: false,
          errorMessage: 'Upload a students CSV or Excel file first.',
          successMessage: null,
        ),
      );
      return;
    }

    state = const AsyncValue.data(
      CourseMutationState(isLoading: true, errorMessage: null, successMessage: null),
    );
    try {
      final id = await _service.createCourse(
        courseName: draft.courseName.trim(),
        courseCode: draft.courseCode.trim(),
        abbreviation: draft.abbreviation.trim(),
        semesterStartDate: draft.semesterStartDate!,
        semesterEndDate: draft.semesterEndDate!,
        sessions: draft.sessions,
        students: draft.students,
      );
      developer.log('Course created: $id', name: 'CourseMutationNotifier');
      ref.invalidate(coursesProvider);
      ref.read(courseDraftProvider.notifier).reset();
      state = const AsyncValue.data(
        CourseMutationState(
          isLoading: false,
          errorMessage: null,
          successMessage: 'Course created successfully.',
        ),
      );
    } catch (e, st) {
      developer.log('createCourse failed', name: 'CourseMutationNotifier', error: e, stackTrace: st);
      state = AsyncValue.data(
        CourseMutationState(isLoading: false, errorMessage: _formatFirestoreError(e), successMessage: null),
      );
    }
  }

  String _formatFirestoreError(Object e) {
    final msg = e.toString();
    if (msg.contains('permission-denied')) {
      return 'Permission denied. Check Firestore security rules.';
    }
    if (msg.contains('User not authenticated')) {
      return 'You must be signed in to create a course.';
    }
    return msg;
  }

  /// Clears transient success/error messages after the UI has shown feedback.
  void clearFeedback() {
    state = const AsyncValue.data(
      CourseMutationState(isLoading: false, errorMessage: null, successMessage: null),
    );
  }

  Future<void> deleteCourse(String courseId) async {
    state = const AsyncValue.data(
      CourseMutationState(isLoading: true, errorMessage: null, successMessage: null),
    );
    try {
      await _service.deleteCourse(courseId);
      ref.invalidate(coursesProvider);
      state = const AsyncValue.data(
        CourseMutationState(isLoading: false, errorMessage: null, successMessage: null),
      );
    } catch (e, st) {
      developer.log('deleteCourse failed', name: 'CourseMutationNotifier', error: e, stackTrace: st);
      state = AsyncValue.data(
        CourseMutationState(isLoading: false, errorMessage: _formatFirestoreError(e), successMessage: null),
      );
    }
  }
}

final courseMutationProvider =
    AsyncNotifierProvider<CourseMutationNotifier, CourseMutationState>(
      CourseMutationNotifier.new,
    );

final courseDetailProvider =
    FutureProvider.family<CourseModel?, String>((ref, courseId) {
  final service = CourseService();
  return service.getCourseOnce(courseId);
});

