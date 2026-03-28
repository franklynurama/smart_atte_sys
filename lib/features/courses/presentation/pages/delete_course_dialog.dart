import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/course_provider.dart';

class DeleteCourseDialog extends ConsumerWidget {
  final String courseId;
  final String courseName;

  const DeleteCourseDialog({
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
      title: const Text('Delete course?'),
      content: Text('This will remove "$courseName" and its attendance records.'),
      actions: [
        TextButton(
          onPressed: isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: isLoading
              ? null
              : () async {
                  await ref.read(courseMutationProvider.notifier).deleteCourse(courseId);
                  if (!context.mounted) return;
                  final err = ref.read(courseMutationProvider).valueOrNull?.errorMessage;
                  if (err != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(err)),
                    );
                    return;
                  }
                  Navigator.of(context).pop();
                },
          child: isLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Delete'),
        ),
      ],
    );
  }
}

