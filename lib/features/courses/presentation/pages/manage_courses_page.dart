import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../routes/app_routes.dart';
import '../../domain/course_display.dart';
import '../providers/course_provider.dart';
import 'archive_course_dialog.dart';
import 'delete_course_dialog.dart';

class ManageCoursesPage extends ConsumerWidget {
  const ManageCoursesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(activeCoursesProvider);
    final selectedId = ref.watch(selectedCourseProvider).courseId;

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Courses')),
      body: coursesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load courses: $e')),
        data: (courses) {
          if (courses.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('No active courses to manage.', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  _archivedCoursesHint(context),
                ],
              ),
            );
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
                  decoration: const InputDecoration(labelText: 'Select course'),
                  items: courses
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: c.courseId,
                          child: Text(
                            courseDropdownLabel(c),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    ref.read(selectedCourseProvider.notifier).select(v);
                  },
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => ArchiveCourseDialog(
                        courseId: activeCourse.courseId,
                        courseName: activeCourse.courseName,
                      ),
                    );
                  },
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('Archive Course'),
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
                const SizedBox(height: 24),
                _archivedCoursesHint(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _archivedCoursesHint(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'To delete archived courses, go to Archived Courses.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.archivedCourses),
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('Go to Archived Courses'),
        ),
      ],
    );
  }
}
