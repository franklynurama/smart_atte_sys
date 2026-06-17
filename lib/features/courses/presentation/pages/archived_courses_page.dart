import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../routes/app_routes.dart';
import '../../../attendance/presentation/models/attendance_view_mode.dart';
import '../../domain/course_display.dart';
import '../providers/course_provider.dart';
import 'delete_course_dialog.dart';

class ArchivedCoursesPage extends ConsumerWidget {
  const ArchivedCoursesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(archivedCoursesProvider);
    final selectedId = ref.watch(selectedCourseProvider).courseId;
    return Scaffold(
      appBar: AppBar(title: const Text('Archived Courses')),
      body: coursesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load courses: $e')),
        data: (courses) {
          if (courses.isEmpty) {
            return const Center(child: Text('No archived courses.'));
          }
          final courseIds = courses.map((c) => c.courseId).toSet();
          final activeId = courseIds.contains(selectedId) ? selectedId : courses.first.courseId;
          final activeCourse = courses.firstWhere((c) => c.courseId == activeId, orElse: () => courses.first);

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: ValueKey(activeCourse.courseId),
                  initialValue: activeCourse.courseId,
                  decoration: const InputDecoration(labelText: 'Select archived course'),
                  items: courses
                      .map((c) => DropdownMenuItem<String>(value: c.courseId, child: Text(courseDropdownLabel(c))))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    ref.read(selectedCourseProvider.notifier).select(v);
                  },
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      AppRoutes.attendanceGrid,
                      arguments: {
                        'courseId': activeCourse.courseId,
                        'mode': AttendanceViewMode.finalAttendance.name,
                      },
                    );
                  },
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('View Final Attendance'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => DeleteCourseDialog(
                        courseId: activeCourse.courseId,
                        courseName: activeCourse.courseName,
                      ),
                    );
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete Course'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
