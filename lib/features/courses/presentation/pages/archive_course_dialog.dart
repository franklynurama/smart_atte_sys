import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/course_provider.dart';

class ArchiveCourseDialog extends ConsumerWidget {
  final String courseId;
  final String courseName;

  const ArchiveCourseDialog({
    super.key,
    required this.courseId,
    required this.courseName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mutation = ref.watch(courseMutationProvider);
    final mutationState = mutation.valueOrNull;
    final isLoading = mutationState?.isLoading ?? false;

    return AlertDialog(
      title: const Text('Archive course?'),
      content: Text(
        '"$courseName" will become read-only. You can still view Final Attendance and download exports, '
        'but you cannot update/import/add students anymore.',
      ),
      actions: [
        TextButton(
          onPressed: isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: isLoading
              ? null
              : () async {
                  await ref.read(courseMutationProvider.notifier).archiveCourse(courseId);
                  if (!context.mounted) return;
                  final err = ref.read(courseMutationProvider).valueOrNull?.errorMessage;
                  if (err != null) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                    return;
                  }
                  Navigator.of(context).pop();
                },
          child: isLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Archive'),
        ),
      ],
    );
  }
}
