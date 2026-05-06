import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../courses/data/models/course_model.dart';
import '../../../courses/presentation/providers/course_provider.dart';
import '../../data/models/attendance_session_model.dart';
import '../../data/services/attendance_service.dart';
import '../../data/services/backend_api_service.dart';
import '../../data/services/file_service.dart';
import '../providers/attendance_provider.dart';

class DecryptAttendancePage extends ConsumerWidget {
  const DecryptAttendancePage({super.key});

  List<_SessionOption> _sessionOptions({
    required CourseModel? course,
    required List<AttendanceSessionModel> normalSessions,
    required List<AttendanceSessionModel> makeupSessions,
  }) {
    return <_SessionOption>[
      ...normalSessions.map(
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
      ...makeupSessions.map(
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
    required _DecryptedRow row,
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

  List<_DecryptedRow> _rowsFromDecrypted(Map<String, dynamic> decrypted) {
    final topDate = (decrypted['date'] ?? '').toString().trim();
    final topTime = (decrypted['time'] ?? '').toString().trim();
    final students = (decrypted['students'] as List<dynamic>? ?? const []);
    if (students.isEmpty) {
      throw const FormatException(
        'Enter a valid attendance file. Required columns: student_id, student_name, timestamp.',
      );
    }
    final out = <_DecryptedRow>[];
    for (final raw in students) {
      if (raw is! Map<String, dynamic>) continue;
      if (!raw.containsKey('student_id') || !raw.containsKey('student_name') || !raw.containsKey('timestamp')) {
        throw const FormatException(
          'Enter a valid attendance file. Required columns: student_id, student_name, timestamp.',
        );
      }
      final sid = (raw['student_id'] ?? '').toString().trim();
      if (sid.isEmpty) continue;
      final name = (raw['student_name'] ?? '').toString().trim();
      String date = topDate;
      String time = topTime;
      final ts = (raw['timestamp'] ?? '').toString().trim();
      if (ts.isNotEmpty) {
        final parsed = DateTime.tryParse(ts.contains('T') ? ts : ts.replaceFirst(' ', 'T'));
        if (parsed != null) {
          date = DateFormat('yyyy-MM-dd').format(parsed);
          time = DateFormat('HH:mm').format(parsed);
        }
      }
      out.add(_DecryptedRow(studentName: name, studentId: sid, date: date, time: time));
    }
    if (out.isEmpty) {
      throw const FormatException(
        'Enter a valid attendance file. Required columns: student_id, student_name, timestamp.',
      );
    }
    return out;
  }

  Future<void> _applyAttendanceToSession({
    required AttendanceService attendanceService,
    required _SessionOption selected,
    required String courseId,
    required List<String> validIds,
    required List<AttendanceSessionModel> makeupSessions,
  }) async {
    if (!selected.isMakeup) {
      await attendanceService.updateAttendanceRecord(
        courseId: courseId,
        recordKey: selected.sessionId,
        attendedStudentIds: validIds,
      );
      return;
    }
    final target = makeupSessions.where((s) => s.sessionId == selected.sessionId).firstOrNull;
    if (target == null) {
      throw StateError('Selected makeup session not found.');
    }
    final map = Map<String, bool>.from(target.attendanceMap);
    for (final id in validIds) {
      map[id] = true;
    }
    await attendanceService.saveAttendanceMapBatch(
      courseId: courseId,
      isMakeup: true,
      sessions: {selected.sessionId: map},
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(attendanceSelectionProvider);
    final encryptedFile = ref.watch(encryptedFileProvider);
    final attendanceService = AttendanceService();
    final fileService = FileService();
    final coursesAsync = ref.watch(coursesProvider);
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
        final msg = state.successMessage!;
        final isProcessComplete = msg == AttendanceDecryptMessages.updateOk ||
            msg == AttendanceDecryptMessages.downloadOk ||
            msg == AttendanceDecryptMessages.bothOk;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );

        if (isProcessComplete) {
          ref.invalidate(coursesProvider);
          if (selection.courseId != null) {
            ref.invalidate(normalAttendanceSessionsProvider(selection.courseId!));
            ref.invalidate(makeupAttendanceSessionsProvider(selection.courseId!));
            ref.invalidate(unverifiedRecordsProvider(selection.courseId!));
          }
          ref.read(attendanceGridEditProvider.notifier).clear();
          ref.read(encryptedFileProvider.notifier).clear();
          ref.read(privateKeyFileProvider.notifier).clear();
          ref.read(attendanceMutationProvider.notifier).resetDecryptFlow();
        } else {
          ref.read(attendanceMutationProvider.notifier).clearFeedback();
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Decrypt Attendance'),
      ),
      body: coursesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load courses: $e')),
        data: (courses) {
          final effectiveCourseId = selection.courseId ?? (courses.isNotEmpty ? courses.first.courseId : null);
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
                    initialValue: currentCourse?.courseId,
                    decoration: const InputDecoration(labelText: 'Course'),
                    items: courses
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c.courseId,
                            child: Text('${c.courseCode} • ${c.abbreviation} • ${c.courseName}${c.section.isNotEmpty ? ' • ${c.section}' : ''}', overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => ref.read(attendanceSelectionProvider.notifier).selectCourse(v),
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
                        final selectedValue = selection.recordKey ?? (options.isNotEmpty ? options.first.value : null);
                        return DropdownButtonFormField<String>(
                          isExpanded: true,
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
                  Text('Private key (.pem)', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    ref.watch(privateKeyFileProvider).isLoaded
                        ? 'Loaded: ${ref.watch(privateKeyFileProvider).fileName ?? 'private key'}'
                        : 'Pick private key file',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: mutationState.isLoading
                        ? null
                        : () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: const ['pem'],
                              withData: true,
                            );
                            if (result == null || result.files.isEmpty) return;

                            final file = result.files.first;
                            final bytes = file.bytes;
                            if (bytes == null) return;

                            ref.read(privateKeyFileProvider.notifier).setFile(bytes, file.name);
                          },
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Upload Private Key'),
                  ),
                  const SizedBox(height: 16),
                  Text('Encrypted file (.sec)', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    encryptedFile.isLoaded
                        ? 'Loaded: ${encryptedFile.fileName ?? 'encrypted file'}'
                        : 'Pick encrypted file',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: mutationState.isLoading
                        ? null
                        : () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: const ['sec'],
                              withData: true,
                            );
                            if (result == null || result.files.isEmpty) return;

                            final file = result.files.first;
                            final bytes = file.bytes;
                            if (bytes == null) return;

                            ref.read(encryptedFileProvider.notifier).setFile(bytes, file.name);
                          },
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Upload Encrypted File'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: mutationState.isLoading ||
                            !encryptedFile.isLoaded ||
                            !ref.watch(privateKeyFileProvider).isLoaded
                        ? null
                        : () async {
                            final key = ref.read(privateKeyFileProvider);
                            await ref.read(attendanceMutationProvider.notifier).decryptWithBackend(
                                  secBytes: encryptedFile.bytes!,
                                  secFileName: encryptedFile.fileName ?? 'attendance.sec',
                                  privateKeyBytes: key.bytes!,
                                  privateKeyFileName: key.fileName ?? 'private_key.pem',
                                );
                          },
                    icon: const Icon(Icons.vpn_key_outlined),
                    label: const Text('Decrypt'),
                  ),
                  const SizedBox(height: 12),
                  if (mutationState.decryptedJson != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Decryption complete. '
                          'Records: ${mutationState.decryptedCount ?? 0}. '
                          'Now choose an action.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (mutationState.downloadPath != null) ...[
                    Text('Saved to: ${mutationState.downloadPath}'),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 12),
                  if (mutationState.decryptedJson != null)
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton(
                          onPressed: mutationState.isLoading
                              ? null
                              : () async {
                                  final courseId = effectiveCourseId;
                                  final encoded = selection.recordKey;
                                  if (courseId == null || encoded == null || currentCourse == null) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Please select a session first.')),
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
                                  final selected = options.where((o) => o.value == encoded).firstOrNull;
                                  if (selected == null || mutationState.decryptedJson == null) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Please select a session first.')),
                                    );
                                    return;
                                  }
                                  final List<_DecryptedRow> rows;
                                  try {
                                    rows = _rowsFromDecrypted(mutationState.decryptedJson!);
                                  } on FormatException catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('${e.message}')),
                                    );
                                    return;
                                  }
                                  final validIds = <String>[];
                                  for (final row in rows) {
                                    final inRoster = _isStudentInRoster(currentCourse, row.studentId);
                                    final matches = _rowMatchesSession(
                                      fileService: fileService,
                                      row: row,
                                      selected: selected,
                                    );
                                    if (inRoster && matches) {
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
                                    makeupSessions: makeupSessions,
                                  );
                                  ref.invalidate(coursesProvider);
                                  ref.invalidate(normalAttendanceSessionsProvider(courseId));
                                  ref.invalidate(makeupAttendanceSessionsProvider(courseId));
                                  ref.invalidate(unverifiedRecordsProvider(courseId));
                                  ref.read(attendanceGridEditProvider.notifier).clear();
                                  ref.read(attendanceMutationProvider.notifier).clearFeedback();
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Attendance updated: ${validIds.length} valid row(s). Non-matching rows moved to unverified.',
                                      ),
                                    ),
                                  );
                                },
                          child: const Text('Update Attendance Directly'),
                        ),
                        FilledButton(
                          onPressed: mutationState.isLoading
                              ? null
                              : () async {
                                  final courseId = effectiveCourseId;
                                  if (courseId == null) return;
                                  if (!context.mounted) return;

                                  final pickedFormat = await showDialog<BackendDownloadFormat>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Download Format'),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ListTile(
                                            title: const Text('CSV'),
                                            onTap: () => Navigator.of(ctx).pop(BackendDownloadFormat.csv),
                                          ),
                                          ListTile(
                                            title: const Text('Excel (.xlsx)'),
                                            onTap: () => Navigator.of(ctx).pop(BackendDownloadFormat.xlsx),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  if (pickedFormat == null) return;

                                  await ref.read(attendanceMutationProvider.notifier).processDecrypted(
                                        courseId: courseId,
                                        action: DecryptAction.download,
                                        downloadFormat: pickedFormat,
                                      );
                                },
                          child: const Text('Download Decrypted File'),
                        ),
                        FilledButton(
                          onPressed: mutationState.isLoading
                              ? null
                              : () async {
                                  final courseId = effectiveCourseId;
                                  final encoded = selection.recordKey;
                                  if (courseId == null || encoded == null || currentCourse == null) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Please select a session first.')),
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
                                  final selected = options.where((o) => o.value == encoded).firstOrNull;
                                  if (selected == null || mutationState.decryptedJson == null) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Please select a session first.')),
                                    );
                                    return;
                                  }
                                  if (!context.mounted) return;

                                  final pickedFormat = await showDialog<BackendDownloadFormat>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Download Format'),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ListTile(
                                            title: const Text('CSV'),
                                            onTap: () => Navigator.of(ctx).pop(BackendDownloadFormat.csv),
                                          ),
                                          ListTile(
                                            title: const Text('Excel (.xlsx)'),
                                            onTap: () => Navigator.of(ctx).pop(BackendDownloadFormat.xlsx),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  if (pickedFormat == null) return;

                                  final List<_DecryptedRow> rows;
                                  try {
                                    rows = _rowsFromDecrypted(mutationState.decryptedJson!);
                                  } on FormatException catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('${e.message}')),
                                    );
                                    return;
                                  }
                                  final validIds = <String>[];
                                  for (final row in rows) {
                                    final inRoster = _isStudentInRoster(currentCourse, row.studentId);
                                    final matches = _rowMatchesSession(
                                      fileService: fileService,
                                      row: row,
                                      selected: selected,
                                    );
                                    if (inRoster && matches) {
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
                                    makeupSessions: makeupSessions,
                                  );

                                  await ref.read(attendanceMutationProvider.notifier).processDecrypted(
                                        courseId: courseId,
                                        recordKey: selected.sessionId,
                                        action: DecryptAction.download,
                                        downloadFormat: pickedFormat,
                                      );
                                  ref.invalidate(coursesProvider);
                                  ref.invalidate(normalAttendanceSessionsProvider(courseId));
                                  ref.invalidate(makeupAttendanceSessionsProvider(courseId));
                                  ref.invalidate(unverifiedRecordsProvider(courseId));
                                  ref.read(attendanceGridEditProvider.notifier).clear();
                                },
                          child: const Text('Both Update and Download'),
                        ),
                      ],
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

class _DecryptedRow {
  final String studentName;
  final String studentId;
  final String date;
  final String time;

  const _DecryptedRow({
    required this.studentName,
    required this.studentId,
    required this.date,
    required this.time,
  });
}

