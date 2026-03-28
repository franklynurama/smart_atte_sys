import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/date_utils.dart' as app_date;
import '../../../../routes/app_routes.dart';
import '../../data/models/course_model.dart';
import '../providers/course_provider.dart';
import 'delete_course_dialog.dart';
import '../../../attendance/presentation/providers/attendance_provider.dart';

class CourseDetailPage extends ConsumerWidget {
  final String courseId;
  const CourseDetailPage({super.key, required this.courseId});

  List<String> _nextRecordKeysForCourse(CourseModel course, DateTime from) {
    final keys = <String>[];
    for (final session in course.sessions) {
      final startTime = app_date.AppDateUtils.parseHHmm(session.startTimeHHmm);
      final base = DateTime(from.year, from.month, from.day);
      for (int offset = 0; offset < 7; offset++) {
        final date = base.add(Duration(days: offset));
        if (date.weekday == session.dayOfWeek) {
          keys.add(app_date.AppDateUtils.attendanceRecordKey(date, sessionStart: startTime));
          break;
        }
      }
    }
    return keys;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courseAsync = ref.watch(courseDetailProvider(courseId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Course Detail'),
      ),
      body: courseAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load course: $e')),
        data: (course) {
          if (course == null) {
            return const Center(child: Text('Course not found.'));
          }

          final recordKeys = _nextRecordKeysForCourse(course, DateTime.now());

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.courseName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text('Code: ${course.courseCode} • ${course.abbreviation}'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (int i = 0; i < course.sessions.length; i++)
                              Chip(
                                label: Text(
                                  'S${i + 1}: D${course.sessions[i].dayOfWeek} ${course.sessions[i].startTimeHHmm}-${course.sessions[i].endTimeHHmm}',
                                ),
                              )
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ref.read(attendanceSelectionProvider.notifier).selectCourse(course.courseId);
                            if (recordKeys.isNotEmpty) {
                              ref.read(attendanceSelectionProvider.notifier).selectRecordKey(recordKeys.first);
                            }
                            Navigator.of(context).pushNamed(AppRoutes.updateAttendance);
                          },
                          icon: const Icon(Icons.edit),
                          label: const Text('Update Attendance'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ref.read(attendanceSelectionProvider.notifier).selectCourse(course.courseId);
                            if (recordKeys.isNotEmpty) {
                              ref.read(attendanceSelectionProvider.notifier).selectRecordKey(recordKeys.first);
                            }
                            Navigator.of(context).pushNamed(AppRoutes.decryptAttendance);
                          },
                          icon: const Icon(Icons.lock),
                          label: const Text('Decrypt Attendance'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => DeleteCourseDialog(courseId: course.courseId, courseName: course.courseName),
                        );
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete Course'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: [
                          const DataColumn(label: Text('Student Name')),
                          const DataColumn(label: Text('Student ID')),
                          for (int i = 0; i < course.sessions.length; i++)
                            DataColumn(
                              label: Text('Session ${i + 1}'),
                            ),
                        ],
                        rows: course.students.map((s) {
                          final rowCells = <DataCell>[];
                          for (int i = 0; i < course.sessions.length; i++) {
                            final key = recordKeys[i];
                            final record = course.attendanceRecords[key];
                            final attended = record?[s.studentId] ?? false;
                            rowCells.add(
                              DataCell(
                                attended
                                    ? const Text('✔', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                                    : const SizedBox.shrink(),
                              ),
                            );
                          }
                          return DataRow(cells: [
                            DataCell(Text(s.studentName)),
                            DataCell(Text(s.studentId)),
                            ...rowCells,
                          ]);
                        }).toList(),
                      ),
                    ),
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

