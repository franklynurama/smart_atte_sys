import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../courses/data/models/course_model.dart';
import '../../../courses/presentation/providers/course_provider.dart';
import '../../data/services/backend_api_service.dart';
import '../providers/attendance_provider.dart';

class DecryptAttendancePage extends ConsumerWidget {
  const DecryptAttendancePage({super.key});

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
    final encryptedFile = ref.watch(encryptedFileProvider);
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

          final recordOptions =
              currentCourse == null ? <MapEntry<String, String>>[] : _recordKeyOptions(currentCourse);
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
                    onChanged: (v) => ref.read(attendanceSelectionProvider.notifier).selectCourse(v),
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
                                  final recordKey = effectiveRecordKey;
                                  if (courseId == null || recordKey == null) return;
                                  await ref.read(attendanceMutationProvider.notifier).processDecrypted(
                                        courseId: courseId,
                                        recordKey: recordKey,
                                        action: DecryptAction.update,
                                        downloadFormat: BackendDownloadFormat.csv,
                                      );
                                },
                          child: const Text('Update Attendance Directly'),
                        ),
                        FilledButton(
                          onPressed: mutationState.isLoading
                              ? null
                              : () async {
                                  final courseId = effectiveCourseId;
                                  final recordKey = effectiveRecordKey;
                                  if (courseId == null || recordKey == null) return;

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
                                        recordKey: recordKey,
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
                                  final recordKey = effectiveRecordKey;
                                  if (courseId == null || recordKey == null) return;

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
                                        recordKey: recordKey,
                                        action: DecryptAction.both,
                                        downloadFormat: pickedFormat,
                                      );
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

