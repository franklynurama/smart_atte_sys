import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../attendance/data/services/attendance_service.dart';
import '../../data/models/student_model.dart';
import '../providers/course_provider.dart';

class AddStudentPage extends ConsumerStatefulWidget {
  const AddStudentPage({super.key});

  @override
  ConsumerState<AddStudentPage> createState() => _AddStudentPageState();
}

class _AddStudentPageState extends ConsumerState<AddStudentPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  bool _isSaving = false;
  String? _selectedCourseId;
  final AttendanceService _service = AttendanceService();

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(coursesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Add Student')),
      body: coursesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load courses: $e')),
        data: (courses) {
          final effectiveCourse = _selectedCourseId ?? (courses.isNotEmpty ? courses.first.courseId : null);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    DropdownButtonFormField<String>(
                    isExpanded: true,
                      initialValue: effectiveCourse,
                      decoration: const InputDecoration(labelText: 'Course'),
                      items: courses
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.courseId,
                              child: Text('${c.courseName} (${c.courseCode} • ${c.section})', overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedCourseId = v),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Student Name',
                        hintText: 'Supports Unicode (e.g., Turkish characters)',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Student name is required.' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _idController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Student ID',
                        hintText: '7 digit number only',
                      ),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (value.isEmpty) return 'Student ID is required.';
                        if (!RegExp(r'^\d{7}$').hasMatch(value)) {
                          return 'Student ID must be exactly 7 digits.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () async {
                              if (_formKey.currentState?.validate() != true) return;
                              final courseId = effectiveCourse;
                              if (courseId == null) return;
                              setState(() => _isSaving = true);
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                await _service.addStudentToCourse(
                                  courseId: courseId,
                                  student: StudentModel(
                                    studentName: _nameController.text.trim(),
                                    studentId: _idController.text.trim(),
                                    department: '',
                                  ),
                                );
                                ref.invalidate(coursesProvider);
                                if (!mounted) return;
                                _nameController.clear();
                                _idController.clear();
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('Student added successfully.')),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(content: Text(e.toString())),
                                );
                              } finally {
                                if (mounted) setState(() => _isSaving = false);
                              }
                            },
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: Text(_isSaving ? 'Saving...' : 'Add Student'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
