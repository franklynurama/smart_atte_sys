import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/date_utils.dart' as app_date;
import '../../../courses/domain/course_display.dart';
import '../providers/attendance_provider.dart';
import '../../../courses/presentation/providers/course_provider.dart';
import '../../data/services/attendance_service.dart';

class MakeupAttendancePage extends ConsumerStatefulWidget {
  const MakeupAttendancePage({super.key});

  @override
  ConsumerState<MakeupAttendancePage> createState() => _MakeupAttendancePageState();
}

class _MakeupAttendancePageState extends ConsumerState<MakeupAttendancePage> {
  String? _courseId;
  DateTime? _date;
  String _startTimeHHmm = '08:00';
  String _endTimeHHmm = '09:00';
  final AttendanceService _attendanceService = AttendanceService();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(activeCoursesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Makeup Attendance')),
      body: coursesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load courses: $e')),
        data: (courses) {
          final courseIds = courses.map((c) => c.courseId).toSet();
          final selected = courseIds.contains(_courseId) ? _courseId : (courses.isNotEmpty ? courses.first.courseId : null);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    key: ValueKey(selected),
                    initialValue: selected,
                    decoration: const InputDecoration(labelText: 'Select Course'),
                    items: courses
                        .map((c) => DropdownMenuItem(
                              value: c.courseId,
                              child: Text(courseDropdownLabel(c), overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _courseId = v),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
                    child: Text(
                      _date == null
                          ? 'Select Date'
                          : 'Date: ${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final initial = app_date.AppDateUtils.parseHHmm(_startTimeHHmm);
                            final picked = await showTimePicker(context: context, initialTime: initial);
                            if (picked == null) return;
                            setState(() => _startTimeHHmm = app_date.AppDateUtils.timeOfDayToHHmm(picked));
                          },
                          child: Text('Start: $_startTimeHHmm'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final initial = app_date.AppDateUtils.parseHHmm(_endTimeHHmm);
                            final picked = await showTimePicker(context: context, initialTime: initial);
                            if (picked == null) return;
                            setState(() => _endTimeHHmm = app_date.AppDateUtils.timeOfDayToHHmm(picked));
                          },
                          child: Text('End: $_endTimeHHmm'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Makeup attendance uses the same roster as the selected course.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final cid = selected;
                            if (cid == null || _date == null) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Select course, date, and time range first.')),
                              );
                              return;
                            }
                            final start = app_date.AppDateUtils.parseHHmm(_startTimeHHmm);
                            final end = app_date.AppDateUtils.parseHHmm(_endTimeHHmm);
                            final startMinutes = start.hour * 60 + start.minute;
                            final endMinutes = end.hour * 60 + end.minute;
                            if (endMinutes < startMinutes) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('End time must be after start time.')),
                              );
                              return;
                            }

                            setState(() => _isLoading = true);
                            try {
                              await _attendanceService.createMakeupAttendanceSession(
                                courseId: cid,
                                date:
                                    '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}',
                                startTime: _startTimeHHmm,
                                endTime: _endTimeHHmm,
                                attendedStudentIds: const <String>[],
                              );
                              ref.invalidate(coursesProvider);
                              ref.invalidate(normalAttendanceSessionsProvider(cid));
                              ref.invalidate(makeupAttendanceSessionsProvider(cid));
                              ref.invalidate(unverifiedRecordsProvider(cid));
                              if (!mounted) return;
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Makeup session created successfully.')),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              final msg = e is StateError
                                  ? e.message.toString()
                                  : e.toString();
                              messenger.showSnackBar(SnackBar(content: Text(msg)));
                            } finally {
                              if (mounted) setState(() => _isLoading = false);
                            }
                          },
                    icon: const Icon(Icons.add_task_outlined),
                    label: Text(_isLoading ? 'Creating...' : 'Create Makeup Session'),
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
