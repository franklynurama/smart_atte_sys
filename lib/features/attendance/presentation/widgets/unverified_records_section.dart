import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../courses/data/models/course_model.dart';
import '../../../courses/data/models/student_model.dart';
import '../../data/models/attendance_session_model.dart';
import '../../data/models/unverified_record_model.dart';
import '../../data/services/attendance_service.dart';
import '../../../courses/presentation/providers/course_provider.dart';
import '../providers/attendance_provider.dart';

class UnverifiedRecordsSection extends ConsumerWidget {
  final CourseModel course;
  final VoidCallback onChanged;

  const UnverifiedRecordsSection({
    super.key,
    required this.course,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unverifiedAsync = ref.watch(unverifiedRecordsProvider(course.courseId));
    final normalAsync = ref.watch(normalAttendanceSessionsProvider(course.courseId));
    final makeupAsync = ref.watch(makeupAttendanceSessionsProvider(course.courseId));
    final attendanceService = AttendanceService();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: unverifiedAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Failed to load unverified records: $e')),
          data: (records) {
            final allSessions = [
              ...(normalAsync.valueOrNull ?? const <AttendanceSessionModel>[]),
              ...(makeupAsync.valueOrNull ?? const <AttendanceSessionModel>[]),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Unverified Records', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (records.isEmpty)
                  const Expanded(child: Center(child: Text('No unverified records.')))
                else
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Name')),
                            DataColumn(label: Text('ID')),
                            DataColumn(label: Text('Type')),
                            DataColumn(label: Text('Date')),
                            DataColumn(label: Text('Time')),
                            DataColumn(label: Text('Add Student')),
                            DataColumn(label: Text('Mark Present')),
                            DataColumn(label: Text('Delete')),
                          ],
                          rows: [
                            for (final r in records)
                              DataRow(
                                cells: [
                                  DataCell(Text(r.studentName)),
                                  DataCell(Text(r.studentId)),
                                  DataCell(Text(r.isMakeup ? 'Makeup' : 'Normal')),
                                  DataCell(Text(r.date)),
                                  DataCell(Text(r.time)),
                                  DataCell(
                                    FilledButton(
                                      onPressed: () => _addStudentAndMarkPresent(
                                        context: context,
                                        ref: ref,
                                        attendanceService: attendanceService,
                                        course: course,
                                        record: r,
                                        allSessions: allSessions,
                                        onChanged: onChanged,
                                      ),
                                      child: const Text('Add Student'),
                                    ),
                                  ),
                                  DataCell(
                                    FilledButton(
                                      onPressed: () => _markPresent(
                                        context: context,
                                        ref: ref,
                                        attendanceService: attendanceService,
                                        course: course,
                                        record: r,
                                        allSessions: allSessions,
                                        onChanged: onChanged,
                                      ),
                                      child: const Text('Mark Present'),
                                    ),
                                  ),
                                  DataCell(
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () => _ignoreRecord(
                                        context: context,
                                        attendanceService: attendanceService,
                                        course: course,
                                        record: r,
                                        onChanged: onChanged,
                                      ),
                                      child: const Text('Ignore'),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String sessionDisplayLabel(CourseModel course, AttendanceSessionModel session) {
    if (session.isMakeup) {
      return 'Makeup • ${session.date} ${session.startTimeHHmm}-${session.endTimeHHmm}';
    }
    final parts = session.sessionId.split('_');
    final date = parts.isNotEmpty ? parts.first : session.date;
    final start = parts.length > 1 ? parts[1] : session.startTimeHHmm;
    if (date.isEmpty || start.isEmpty) {
      return 'Normal • ${session.sessionId}';
    }
    String end = session.endTimeHHmm;
    final dateParts = date.split('-');
    if (dateParts.length == 3) {
      final y = int.tryParse(dateParts[0]);
      final m = int.tryParse(dateParts[1]);
      final d = int.tryParse(dateParts[2]);
      if (y != null && m != null && d != null) {
        final weekday = DateTime(y, m, d).weekday;
        final matched = course.sessions.where((s) => s.dayOfWeek == weekday && s.startTimeHHmm == start);
        if (matched.isNotEmpty) {
          end = matched.first.endTimeHHmm;
        }
      }
    }
    if (end.isEmpty) end = start;
    return 'Normal • $date $start-$end';
  }

  static Future<String?> pickSessionId(
    BuildContext context,
    List<AttendanceSessionModel> options,
    CourseModel course,
    String title, {
    String? preferredSessionId,
  }) async {
    if (options.isEmpty) return null;
    String current = options.first.sessionId;
    if (preferredSessionId != null && preferredSessionId.isNotEmpty) {
      final matched = options.where((o) => o.sessionId == preferredSessionId);
      if (matched.isNotEmpty) {
        current = matched.first.sessionId;
      }
    }
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => DropdownButton<String>(
            value: current,
            isExpanded: true,
            items: options
                .map(
                  (e) => DropdownMenuItem(
                    value: e.sessionId,
                    child: Text(sessionDisplayLabel(course, e), overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setLocal(() => current = v);
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(current), child: const Text('Select')),
        ],
      ),
    );
  }

  static Future<void> _addStudentAndMarkPresent({
    required BuildContext context,
    required WidgetRef ref,
    required AttendanceService attendanceService,
    required CourseModel course,
    required UnverifiedRecordModel record,
    required List<AttendanceSessionModel> allSessions,
    required VoidCallback onChanged,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      var addedStudent = false;
      final exists = course.students.any((s) => s.studentId == record.studentId);
      if (!exists) {
        await attendanceService.addStudentToCourse(
          courseId: course.courseId,
          student: StudentModel(studentName: record.studentName, studentId: record.studentId, department: ''),
        );
        addedStudent = true;
      }
      if (!context.mounted) return;
      final selectedSession = await pickSessionId(
        context,
        allSessions,
        course,
        'Select session',
        preferredSessionId: record.rawSessionId,
      );
      if (selectedSession == null) return;
      final picked = allSessions.where((s) => s.sessionId == selectedSession).firstOrNull;
      if (picked == null) return;
      await attendanceService.setManualPresent(
        courseId: course.courseId,
        sessionId: selectedSession,
        studentId: record.studentId,
        isMakeup: picked.isMakeup,
      );
      await attendanceService.deleteUnverifiedRecord(courseId: course.courseId, recordId: record.id);
      if (addedStudent) {
        ref.invalidate(coursesProvider);
      }
      ref.read(attendanceGridEditProvider.notifier).clear();
      onChanged();
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Student added and marked present.')));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  static Future<void> _markPresent({
    required BuildContext context,
    required WidgetRef ref,
    required AttendanceService attendanceService,
    required CourseModel course,
    required UnverifiedRecordModel record,
    required List<AttendanceSessionModel> allSessions,
    required VoidCallback onChanged,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final exists = course.students.any((s) => s.studentId == record.studentId);
    if (!exists) {
      messenger.showSnackBar(const SnackBar(content: Text('Student not in roster. Use Add Student first.')));
      return;
    }
    final selectedSession = await pickSessionId(
      context,
      allSessions,
      course,
      'Select session',
      preferredSessionId: record.rawSessionId,
    );
    if (selectedSession == null) return;
    try {
      final picked = allSessions.where((s) => s.sessionId == selectedSession).firstOrNull;
      if (picked == null) return;
      await attendanceService.setManualPresent(
        courseId: course.courseId,
        sessionId: selectedSession,
        studentId: record.studentId,
        isMakeup: picked.isMakeup,
      );
      await attendanceService.deleteUnverifiedRecord(courseId: course.courseId, recordId: record.id);
      ref.read(attendanceGridEditProvider.notifier).clear();
      onChanged();
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Marked present.')));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  static Future<void> _ignoreRecord({
    required BuildContext context,
    required AttendanceService attendanceService,
    required CourseModel course,
    required UnverifiedRecordModel record,
    required VoidCallback onChanged,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete unverified record?'),
        content: Text(
          'Ignore record for ${record.studentName} (${record.studentId})?\n\n'
          'This record will be permanently deleted and cannot be recovered.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await attendanceService.deleteUnverifiedRecord(courseId: course.courseId, recordId: record.id);
      onChanged();
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Record deleted.')));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

}
