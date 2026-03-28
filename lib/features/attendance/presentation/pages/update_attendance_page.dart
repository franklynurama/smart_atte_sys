import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../courses/data/models/course_model.dart';
import '../../../courses/presentation/providers/course_provider.dart';
import '../providers/attendance_provider.dart';

class UpdateAttendancePage extends ConsumerWidget {
  const UpdateAttendancePage({super.key});

  List<MapEntry<String, String>> _recordKeyOptions(CourseModel course) {
    final keys = course.attendanceRecords.keys.toList()..sort();
    return keys.map((k) {
      final split = k.split('_');
      final label = split.length == 2 ? '${split[0]} ${split[1]}' : k;
      return MapEntry(k, label);
    }).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(attendanceSelectionProvider);
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
          final effectiveCourseId = selection.courseId ?? (courses.isNotEmpty ? courses.first.courseId : null);
          final currentCourse = effectiveCourseId == null
              ? null
              : courses.where((c) => c.courseId == effectiveCourseId).firstOrNull;

          final recordOptions = currentCourse == null ? <MapEntry<String, String>>[] : _recordKeyOptions(currentCourse);
          final effectiveRecordKey = selection.recordKey ?? (recordOptions.isNotEmpty ? recordOptions.first.key : null);

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: currentCourse?.courseId,
                    decoration: const InputDecoration(labelText: 'Course'),
                    items: courses
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c.courseId,
                            child: Text('${c.courseCode} • ${c.abbreviation}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      ref.read(attendanceSelectionProvider.notifier).selectCourse(v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: effectiveRecordKey,
                    decoration: const InputDecoration(labelText: 'Session (Record Key)'),
                    items: recordOptions
                        .map(
                          (e) => DropdownMenuItem<String>(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => ref.read(attendanceSelectionProvider.notifier).selectRecordKey(v),
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
                              allowedExtensions: const ['csv', 'xlsx', 'xls'],
                              withData: true,
                            );
                            if (file == null || file.files.isEmpty) return;
                            final picked = file.files.first;
                            final bytes = picked.bytes;
                            final fileName = picked.name;
                            if (bytes == null) return;

                            final courseId = effectiveCourseId;
                            final recordKey = effectiveRecordKey;
                            if (courseId == null || recordKey == null) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Select a course and session first.')),
                              );
                              return;
                            }

                            await ref.read(attendanceMutationProvider.notifier).updateAttendanceFromCsv(
                                  courseId: courseId,
                                  recordKey: recordKey,
                                  bytes: bytes,
                                  fileName: fileName,
                                );

                            // Refresh views.
                            ref.invalidate(coursesProvider);
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

