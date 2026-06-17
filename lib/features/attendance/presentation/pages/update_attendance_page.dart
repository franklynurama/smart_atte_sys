import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../courses/data/models/course_model.dart';
import '../../../courses/domain/course_display.dart';
import '../../../courses/presentation/providers/course_provider.dart';
import '../../data/models/attendance_session_model.dart';
import '../../data/services/attendance_service.dart';
import '../../data/services/file_service.dart';
import '../providers/attendance_provider.dart';
import '../utils/attendance_import_reset.dart';

class UpdateAttendancePage extends ConsumerWidget {
  const UpdateAttendancePage({super.key});

  List<_SessionOption> _sessionOptions({
    required CourseModel? course,
    required List<AttendanceSessionModel> normalSessions,
    required List<AttendanceSessionModel> makeupSessions,
  }) {
    final options = <_SessionOption>[
      ...normalSessions
          .map(
            (s) {
              final date = _sessionDateFromNormalSessionId(s.sessionId);
              final start = _sessionTimeFromNormalSessionId(s.sessionId);
              final end = _normalEndTimeFromCourse(
                course: course,
                sessionDate: date,
                sessionStart: start,
              );
              return _SessionOption(
                value: 'normal|${s.sessionId}',
                sessionId: s.sessionId,
                isMakeup: false,
                date: date,
                startTime: start,
                endTime: end,
                label: 'Normal • $date $start-$end',
              );
            },
          ),
      ...makeupSessions
          .map(
            (s) => _SessionOption(
              value: 'makeup|${s.sessionId}',
              sessionId: s.sessionId,
              isMakeup: true,
              date: s.date,
              startTime: s.startTimeHHmm,
              endTime: s.endTimeHHmm,
              label: 'Makeup • ${s.date} ${s.startTimeHHmm}-${s.endTimeHHmm}',
            ),
          ),
    ];
    final deduped = <String, _SessionOption>{};
    for (final option in options) {
      deduped[option.value] = option;
    }
    return deduped.values.toList();
  }

  String _sessionDateFromNormalSessionId(String sessionId) {
    final parts = sessionId.split('_');
    return parts.isNotEmpty ? parts.first : '';
  }

  String _sessionTimeFromNormalSessionId(String sessionId) {
    final parts = sessionId.split('_');
    return parts.length == 2 ? parts[1] : '';
  }

  String _normalEndTimeFromCourse({
    required CourseModel? course,
    required String sessionDate,
    required String sessionStart,
  }) {
    if (course == null || sessionDate.isEmpty || sessionStart.isEmpty) return sessionStart;
    final parts = sessionDate.split('-');
    if (parts.length != 3) return sessionStart;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return sessionStart;
    final dt = DateTime(y, m, d);
    final match = course.sessions.where(
      (s) => s.dayOfWeek == dt.weekday && s.startTimeHHmm == sessionStart,
    );
    return match.isNotEmpty ? match.first.endTimeHHmm : sessionStart;
  }

  String _normalizeDate(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final dt = DateTime.tryParse(t);
    if (dt != null) {
      return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    return t;
  }

  bool _isStudentInRoster(CourseModel course, String studentId) {
    return course.students.any((s) => s.studentId == studentId);
  }

  bool _rowMatchesSession({
    required FileService fileService,
    required AttendanceCsvRow row,
    required _SessionOption selected,
  }) {
    if (row.time.trim().isEmpty || selected.startTime.isEmpty || selected.endTime.isEmpty) {
      return false;
    }
    final timeOk = fileService.isWithinSessionWindow(
      csvTime: row.time.trim(),
      sessionStartHHmm: selected.startTime,
      sessionEndHHmm: selected.endTime,
    );
    if (!timeOk) return false;

    if (row.date.trim().isEmpty || selected.date.trim().isEmpty) return false;
    return _normalizeDate(row.date) == _normalizeDate(selected.date);
  }

  Future<void> _applyAttendanceToSession({
    required AttendanceService attendanceService,
    required _SessionOption selected,
    required String courseId,
    required List<String> validIds,
  }) async {
    if (!selected.isMakeup) {
      await attendanceService.updateAttendanceRecord(
        courseId: courseId,
        recordKey: selected.sessionId,
        attendedStudentIds: validIds,
      );
      return;
    }

    await attendanceService.updateMakeupAttendanceRecord(
      courseId: courseId,
      sessionId: selected.sessionId,
      attendedStudentIds: validIds,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileService = FileService();
    final attendanceService = AttendanceService();
    final selection = ref.watch(attendanceSelectionProvider);
    final coursesAsync = ref.watch(activeCoursesProvider);
    final mutationAsync = ref.watch(attendanceMutationProvider);
    final mutationState = mutationAsync.valueOrNull ?? AttendanceMutationState.initial();

    ref.listen(attendanceMutationProvider, (prev, next) {
      final state = next.valueOrNull;
      if (state == null || !context.mounted) return;
      if (state.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.errorMessage!),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        ref.read(attendanceMutationProvider.notifier).clearFeedback();
      } else if (state.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.successMessage!)),
        );
        ref.read(attendanceMutationProvider.notifier).clearFeedback();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Update Attendance'),
      ),
      body: coursesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load courses: $e')),
        data: (courses) {
          final courseIds = courses.map((c) => c.courseId).toSet();
          final effectiveCourseId = courseIds.contains(selection.courseId)
              ? selection.courseId
              : (courses.isNotEmpty ? courses.first.courseId : null);
          final currentCourse = effectiveCourseId == null
              ? null
              : courses.where((c) => c.courseId == effectiveCourseId).firstOrNull;
          final normalSessionsAsync = effectiveCourseId == null
              ? const AsyncValue<List<AttendanceSessionModel>>.data(<AttendanceSessionModel>[])
              : ref.watch(normalAttendanceSessionsProvider(effectiveCourseId));
          final makeupSessionsAsync = effectiveCourseId == null
              ? const AsyncValue<List<AttendanceSessionModel>>.data(<AttendanceSessionModel>[])
              : ref.watch(makeupAttendanceSessionsProvider(effectiveCourseId));

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    key: ValueKey(effectiveCourseId),
                    initialValue: effectiveCourseId,
                    decoration: const InputDecoration(labelText: 'Course'),
                    items: courses
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c.courseId,
                            child: Text(courseDropdownLabel(c), overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      ref.read(attendanceSelectionProvider.notifier).selectCourse(v);
                    },
                  ),
                  const SizedBox(height: 12),
                  normalSessionsAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Failed to load normal sessions: $e'),
                    data: (normalSessions) => makeupSessionsAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Failed to load makeup sessions: $e'),
                      data: (makeupSessions) {
                        final options = _sessionOptions(
                          course: currentCourse,
                          normalSessions: normalSessions,
                          makeupSessions: makeupSessions,
                        );
                        final optionValues = options.map((o) => o.value).toSet();
                        final selectedValue = optionValues.contains(selection.recordKey)
                            ? selection.recordKey
                            : (options.isNotEmpty ? options.first.value : null);
                        return DropdownButtonFormField<String>(
                          isExpanded: true,
                          key: ValueKey(selectedValue),
                          initialValue: selectedValue,
                          decoration: const InputDecoration(labelText: 'Session (Normal/Makeup)'),
                          items: options
                              .map(
                                (e) => DropdownMenuItem<String>(
                                  value: e.value,
                                  child: Text(e.label, overflow: TextOverflow.ellipsis),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => ref.read(attendanceSelectionProvider.notifier).selectRecordKey(v),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (mutationState.errorMessage != null || mutationState.successMessage != null)
                    const SizedBox(height: 8),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: mutationState.isLoading
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final file = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: const ['csv'],
                              withData: true,
                            );
                            if (file == null || file.files.isEmpty) return;
                            final picked = file.files.first;
                            final bytes = picked.bytes;
                            final fileName = picked.name;
                            if (bytes == null) return;

                            final courseId = effectiveCourseId;
                            final encodedSession = selection.recordKey;
                            if (courseId == null || encodedSession == null) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Select a course and session first.')),
                              );
                              return;
                            }
                            final normalSessions = await ref.read(normalAttendanceSessionsProvider(courseId).future);
                            final makeupSessions = await ref.read(makeupAttendanceSessionsProvider(courseId).future);
                            final options = _sessionOptions(
                              course: currentCourse,
                              normalSessions: normalSessions,
                              makeupSessions: makeupSessions,
                            );
                            final selected = options.where((o) => o.value == encodedSession).firstOrNull;
                            if (selected == null) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Selected session not found.')),
                              );
                              return;
                            }

                            final List<AttendanceCsvRow> detailedRows;
                            try {
                              detailedRows = await fileService.parseAttendanceRowsWithDateTime(
                                bytes: bytes,
                                fileName: fileName,
                              );
                            } catch (_) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Enter a valid attendance CSV file. Required columns: student_id, student_name, timestamp.',
                                  ),
                                ),
                              );
                              return;
                            }
                            if (currentCourse == null) return;

                            final validIds = <String>[];
                            for (final row in detailedRows) {
                              final inRoster = _isStudentInRoster(currentCourse, row.studentId);
                              final matchesSession = _rowMatchesSession(
                                fileService: fileService,
                                row: row,
                                selected: selected,
                              );
                              if (inRoster && matchesSession) {
                                validIds.add(row.studentId);
                              } else {
                                await attendanceService.addUnverifiedRecord(
                                  courseId: courseId,
                                  studentName: row.studentName,
                                  studentId: row.studentId,
                                  date: row.date.isEmpty ? selected.date : row.date,
                                  time: row.time.isEmpty ? selected.startTime : row.time,
                                  rawSessionId: selected.sessionId,
                                  isMakeup: selected.isMakeup,
                                );
                              }
                            }
                            await _applyAttendanceToSession(
                              attendanceService: attendanceService,
                              selected: selected,
                              courseId: courseId,
                              validIds: validIds,
                            );
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Attendance updated: ${validIds.length} valid row(s). Non-matching rows moved to unverified.',
                                ),
                              ),
                            );
                            resetAfterCsvAttendanceUpdate(ref, courseId);
                          },
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Upload CSV and Update'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SessionOption {
  final String value;
  final String sessionId;
  final bool isMakeup;
  final String date;
  final String startTime;
  final String endTime;
  final String label;

  const _SessionOption({
    required this.value,
    required this.sessionId,
    required this.isMakeup,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.label,
  });
}

