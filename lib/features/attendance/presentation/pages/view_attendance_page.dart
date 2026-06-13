import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../routes/app_routes.dart';
import '../../../courses/presentation/providers/course_provider.dart';
import '../providers/attendance_provider.dart';

class ViewAttendancePage extends ConsumerWidget {
  const ViewAttendancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(coursesProvider);
    final selectedId = ref.watch(selectedCourseProvider).courseId;

    ref.listen(coursesProvider, (prev, next) {
      final list = next.valueOrNull;
      if ((selectedId == null || selectedId.isEmpty) && list != null && list.isNotEmpty) {
        ref.read(selectedCourseProvider.notifier).select(list.first.courseId);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('View Attendance'),
        actions: [
          IconButton(
            tooltip: 'Add course',
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.addCourse),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: coursesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load courses: $e')),
        data: (courses) {
          if (courses.isEmpty) {
            return const Center(child: Text('No courses yet. Add a course first.'));
          }
          final activeId = selectedId ?? courses.first.courseId;
          final activeCourse = courses.firstWhere((c) => c.courseId == activeId, orElse: () => courses.first);

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: activeCourse.courseId,
                  decoration: const InputDecoration(labelText: 'Select course'),
                  items: courses
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: c.courseId,
                          child: Text(
                            '${c.courseCode} • ${c.abbreviation} • ${c.courseName}${c.section.isNotEmpty ? ' • ${c.section}' : ''}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    ref.read(selectedCourseProvider.notifier).select(v);
                    ref.read(attendanceGridEditProvider.notifier).clear();
                  },
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      AppRoutes.attendanceMode,
                      arguments: {'courseId': activeCourse.courseId},
                    );
                  },
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('View'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
