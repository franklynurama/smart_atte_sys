import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/course_provider.dart';
import 'delete_course_dialog.dart';

class DeleteCoursePage extends ConsumerWidget {
  const DeleteCoursePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(coursesProvider);
    final selectedId = ref.watch(selectedCourseProvider).courseId;

    return Scaffold(
      appBar: AppBar(title: const Text('Delete Course')),
      body: coursesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load courses: $e')),
        data: (courses) {
          if (courses.isEmpty) {
            return const Center(child: Text('No courses to delete.'));
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
                  },
                ),
                const SizedBox(height: 24),
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
