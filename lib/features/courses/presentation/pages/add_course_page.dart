import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/date_utils.dart' as app_date;
import '../../../../core/widgets/custom_button.dart';
import '../../../../core/widgets/custom_textfield.dart';
import '../../../../routes/app_routes.dart';
import '../../domain/academic_year.dart';
import '../../domain/course_term.dart';
import '../providers/course_provider.dart';

/// Add course: uses [Form] + [GlobalKey] so [TextFormField] validators run.
/// [courseMutationProvider] drives loading and success/error; [ref.listen] shows [SnackBar]s.
class AddCoursePage extends ConsumerStatefulWidget {
  const AddCoursePage({super.key});

  @override
  ConsumerState<AddCoursePage> createState() => _AddCoursePageState();
}

class _AddCoursePageState extends ConsumerState<AddCoursePage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController nameController;
  late final TextEditingController codeController;
  late final TextEditingController abbrController;
  late final TextEditingController sectionController;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController();
    codeController = TextEditingController();
    abbrController = TextEditingController();
    sectionController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(courseMutationProvider.notifier).clearFeedback();
      ref.read(courseDraftProvider.notifier).loadOfficialCourseListFromAsset();
    });
  }

  @override
  void dispose() {
    nameController.dispose();
    codeController.dispose();
    abbrController.dispose();
    sectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(courseDraftProvider);
    final yearOptions = academicYearOptions();
    final mutation = ref.watch(courseMutationProvider);
    final mutationState = mutation.valueOrNull ?? CourseMutationState.initial();
    if (nameController.text != draft.courseName) nameController.text = draft.courseName;
    if (codeController.text != draft.courseCode) codeController.text = draft.courseCode;
    if (abbrController.text != draft.abbreviation) abbrController.text = draft.abbreviation;
    if (sectionController.text != draft.section) sectionController.text = draft.section;

    ref.listen(courseMutationProvider, (previous, next) {
      final s = next.valueOrNull;
      if (s == null || !context.mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      final colorScheme = Theme.of(context).colorScheme;

      if (s.successMessage != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(s.successMessage!),
            behavior: SnackBarBehavior.floating,
          ),
        );
        ref.read(courseMutationProvider.notifier).clearFeedback();
        nameController.clear();
        codeController.clear();
        abbrController.clear();
        sectionController.clear();
        Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.dashboard, (r) => false);
        return;
      }

      if (s.errorMessage != null && !s.isLoading) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(s.errorMessage!),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Course'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                CustomTextField(
                  label: 'Course Name',
                  controller: nameController,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Course name is required.' : null,
                  hintText: 'e.g., Data Management and File Structures',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                    isExpanded: true,
                  initialValue: draft.selectedOfficialCourseKey,
                  decoration: const InputDecoration(labelText: 'Select course from official list'),
                  items: draft.officialCourses
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: c.selectionKey,
                          child: Text('${c.code} • ${c.abbreviation} • ${c.name}${c.section.isNotEmpty ? ' • ${c.section}' : ''}', overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => ref.read(courseDraftProvider.notifier).selectOfficialCourseByKey(v),
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  label: 'Course Code',
                  controller: codeController,
                  keyboardType: TextInputType.text,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Course code is required.' : null,
                  hintText: 'e.g., 3550351',
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  label: 'Abbreviation',
                  controller: abbrController,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Abbreviation is required.' : null,
                  hintText: 'e.g., CNG 351',
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  label: 'Section',
                  controller: sectionController,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Section is required.' : null,
                  hintText: 'e.g., S1 or Lab1',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<CourseTerm>(
                  isExpanded: true,
                  initialValue: draft.term,
                  decoration: const InputDecoration(labelText: 'Term'),
                  items: const [
                    DropdownMenuItem(value: CourseTerm.fall, child: Text('Fall')),
                    DropdownMenuItem(value: CourseTerm.spring, child: Text('Spring')),
                    DropdownMenuItem(value: CourseTerm.summer, child: Text('Summer')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    ref.read(courseDraftProvider.notifier).setTerm(v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: yearOptions.contains(draft.academicYearLabel)
                      ? draft.academicYearLabel
                      : yearOptions.last,
                  decoration: const InputDecoration(labelText: 'Academic year'),
                  items: yearOptions
                      .map((y) => DropdownMenuItem<String>(value: y, child: Text(y)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    ref.read(courseDraftProvider.notifier).setAcademicYearLabel(v);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Same course code in a different term or academic year is a separate course.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Semester Period',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final initial = draft.semesterStartDate ?? DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: initial,
                            firstDate: DateTime(DateTime.now().year - 1),
                            lastDate: DateTime(DateTime.now().year + 5),
                          );
                          if (picked == null) return;
                          ref.read(courseDraftProvider.notifier).setSemesterStartDate(picked);
                        },
                        child: Text(
                          draft.semesterStartDate == null
                              ? 'Select Start Date'
                              : 'Start: ${app_date.AppDateUtils.formatDateKey(draft.semesterStartDate!)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final initial = draft.semesterEndDate ?? (draft.semesterStartDate ?? DateTime.now());
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: initial,
                            firstDate: DateTime(DateTime.now().year - 1),
                            lastDate: DateTime(DateTime.now().year + 5),
                          );
                          if (picked == null) return;
                          ref.read(courseDraftProvider.notifier).setSemesterEndDate(picked);
                        },
                        child: Text(
                          draft.semesterEndDate == null
                              ? 'Select End Date'
                              : 'End: ${app_date.AppDateUtils.formatDateKey(draft.semesterEndDate!)}',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Schedule (1–3 sessions per week)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                ...List.generate(draft.sessions.length, (index) {
                  final session = draft.sessions[index];
                  return Padding(
                    key: ValueKey('session_${session.dayOfWeek}_${session.startTimeHHmm}_$index'),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Card(
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    isExpanded: true,
                                    initialValue: session.dayOfWeek,
                                    decoration: const InputDecoration(labelText: 'Day'),
                                    items: const [
                                      DropdownMenuItem(value: 1, child: Text('Monday')),
                                      DropdownMenuItem(value: 2, child: Text('Tuesday')),
                                      DropdownMenuItem(value: 3, child: Text('Wednesday')),
                                      DropdownMenuItem(value: 4, child: Text('Thursday')),
                                      DropdownMenuItem(value: 5, child: Text('Friday')),
                                      DropdownMenuItem(value: 6, child: Text('Saturday')),
                                      DropdownMenuItem(value: 7, child: Text('Sunday')),
                                    ],
                                    onChanged: (v) {
                                      if (v == null) return;
                                      ref.read(courseDraftProvider.notifier).updateSession(index, dayOfWeek: v);
                                    },
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove session',
                                  onPressed: () => ref.read(courseDraftProvider.notifier).removeSessionAt(index),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      final initial = app_date.AppDateUtils.parseHHmm(session.startTimeHHmm);
                                      final picked = await showTimePicker(context: context, initialTime: initial);
                                      if (picked == null) return;
                                      ref.read(courseDraftProvider.notifier).updateSession(
                                            index,
                                            startTimeHHmm: app_date.AppDateUtils.timeOfDayToHHmm(picked),
                                          );
                                    },
                                    child: Text('Start: ${session.startTimeHHmm}'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      final initial = app_date.AppDateUtils.parseHHmm(session.endTimeHHmm);
                                      final picked = await showTimePicker(context: context, initialTime: initial);
                                      if (picked == null) return;
                                      ref.read(courseDraftProvider.notifier).updateSession(
                                            index,
                                            endTimeHHmm: app_date.AppDateUtils.timeOfDayToHHmm(picked),
                                          );
                                    },
                                    child: Text('End: ${session.endTimeHHmm}'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                if (draft.sessions.length < 3)
                  OutlinedButton.icon(
                    onPressed: () => ref.read(courseDraftProvider.notifier).addSession(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Session'),
                  ),
                const SizedBox(height: 18),
                Text(
                  'Upload Students CSV/Excel',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Required columns: Student ID (and optionally Name, Department).',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 10),
                if (draft.isLoadingStudents)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Parsing file…'),
                      ],
                    ),
                  ),
                if (draft.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      draft.errorMessage!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                if (draft.students.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Loaded ${draft.students.length} student(s)',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: draft.isLoadingStudents || mutationState.isLoading
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: const ['csv', 'xlsx', 'xls'],
                            withData: true,
                          );
                          if (result == null || result.files.isEmpty) return;

                          final file = result.files.first;
                          final bytes = file.bytes;
                          if (bytes == null) {
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Could not read file bytes. Try a smaller file or re-export.')),
                            );
                            return;
                          }
                          await ref.read(courseDraftProvider.notifier).loadStudentsFromFileBytes(
                                bytes: bytes,
                                fileName: file.name,
                              );
                          final err = ref.read(courseDraftProvider).errorMessage;
                          final count = ref.read(courseDraftProvider).students.length;
                          if (!context.mounted) return;
                          if (err != null) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(err),
                                backgroundColor: Theme.of(context).colorScheme.error,
                              ),
                            );
                          } else if (count > 0) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Loaded $count student(s) from ${file.name}')),
                            );
                          }
                        },
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Pick file'),
                ),
                const SizedBox(height: 24),
                if (mutationState.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      mutationState.errorMessage!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                CustomButton(
                  label: 'Create Course',
                  icon: Icons.check_circle_outline,
                  isLoading: mutationState.isLoading,
                  enabled: !draft.isLoadingStudents,
                  onPressed: () async {
                    if (!_formKey.currentState!.validate()) {
                      return;
                    }
                    ref.read(courseDraftProvider.notifier).setCourseName(nameController.text.trim());
                    ref.read(courseDraftProvider.notifier).setCourseCode(codeController.text.trim());
                    ref.read(courseDraftProvider.notifier).setAbbreviation(abbrController.text.trim());
                    ref.read(courseDraftProvider.notifier).setSection(sectionController.text.trim());
                    await ref.read(courseMutationProvider.notifier).createCourse();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
