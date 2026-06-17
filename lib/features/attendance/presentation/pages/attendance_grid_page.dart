import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/download_bytes.dart';
import '../../../courses/data/models/course_model.dart';
import '../../../courses/domain/course_display.dart';
import '../../../courses/domain/course_term.dart';
import '../../../courses/presentation/providers/course_provider.dart';
import '../../data/models/attendance_session_model.dart';
import '../../data/services/attendance_export_service.dart';
import '../../data/services/attendance_service.dart';
import '../models/attendance_view_mode.dart';
import '../providers/attendance_provider.dart';
import '../utils/attendance_manual_save.dart';
import '../utils/attendance_slot_builder.dart';
import '../widgets/attendance_grid_widget.dart';
import '../widgets/unverified_records_section.dart';

enum _TableType { normal, makeup }

class AttendanceGridPage extends ConsumerStatefulWidget {
  final String courseId;
  final AttendanceViewMode mode;

  const AttendanceGridPage({
    super.key,
    required this.courseId,
    required this.mode,
  });

  @override
  ConsumerState<AttendanceGridPage> createState() => _AttendanceGridPageState();
}

class _AttendanceGridPageState extends ConsumerState<AttendanceGridPage> {
  _TableType _activeTable = _TableType.normal;
  bool _isSavingChanges = false;
  bool _isExporting = false;
  final AttendanceService _attendanceService = AttendanceService();
  final AttendanceExportService _exportService = AttendanceExportService();

  void _refreshAttendanceViews() {
    ref.invalidate(coursesProvider);
    ref.invalidate(normalAttendanceSessionsProvider(widget.courseId));
    ref.invalidate(makeupAttendanceSessionsProvider(widget.courseId));
    if (widget.mode == AttendanceViewMode.adjustments) {
      ref.invalidate(unverifiedRecordsProvider(widget.courseId));
    }
  }

  CourseModel? _findCourse(List<CourseModel> courses) {
    for (final c in courses) {
      if (c.courseId == widget.courseId) return c;
    }
    return null;
  }

  Future<void> _saveChanges(CourseModel course, List<AttendanceSessionModel> sessions) async {
    final messenger = ScaffoldMessenger.of(context);
    if (mounted) setState(() => _isSavingChanges = true);
    try {
      final isMakeup = _activeTable == _TableType.makeup;
      final edits = ref.read(attendanceGridEditProvider);
      final draft = isMakeup ? edits.makeupDraft : edits.normalDraft;
      final rawBySession = {for (final s in sessions) s.sessionId: s.attendanceMapRaw};
      final manualBySession = {for (final s in sessions) s.sessionId: s.attendanceMapManual};
      final changed = buildSparseManualMapsForSave(
        students: course.students,
        rawBySession: rawBySession,
        manualBySession: manualBySession,
        draft: draft,
      );
      if (changed.isEmpty) {
        if (!context.mounted) return;
        messenger.showSnackBar(const SnackBar(content: Text('No attendance changes to save.')));
        return;
      }
      await _attendanceService.replaceManualAttendanceBatch(
        courseId: course.courseId,
        isMakeup: isMakeup,
        sessions: changed,
      );
      ref.read(attendanceGridEditProvider.notifier).clear();
      _refreshAttendanceViews();
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Attendance changes saved.')));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _isSavingChanges = false);
    }
  }

  Future<void> _exportGridCsv(CourseModel course) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final normalSessions = await ref.read(normalAttendanceSessionsProvider(course.courseId).future);
      final makeupSessions = await ref.read(makeupAttendanceSessionsProvider(course.courseId).future);
      final normalBundle = resolveSlotsBundle(course: course, sessions: normalSessions, isMakeup: false);
      final makeupBundle = resolveSlotsBundle(course: course, sessions: makeupSessions, isMakeup: true);
      final normalBytes = await _exportService.buildGridCsv(
        course: course,
        slots: normalBundle.slots,
        sessions: normalSessions,
        isMakeup: false,
      );
      final makeupBytes = await _exportService.buildGridCsv(
        course: course,
        slots: makeupBundle.slots,
        sessions: makeupSessions,
        isMakeup: true,
      );
      final prefix = courseExportPrefix(course);
      await downloadBytesToDevice(normalBytes, '${prefix}_normal_final.csv');
      await downloadBytesToDevice(makeupBytes, '${prefix}_makeup_final.csv');
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Semester tables downloaded (2 CSV files).')));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportGridExcel(CourseModel course) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final normalSessions = await ref.read(normalAttendanceSessionsProvider(course.courseId).future);
      final makeupSessions = await ref.read(makeupAttendanceSessionsProvider(course.courseId).future);
      final normalBundle = resolveSlotsBundle(course: course, sessions: normalSessions, isMakeup: false);
      final makeupBundle = resolveSlotsBundle(course: course, sessions: makeupSessions, isMakeup: true);
      final bytes = await _exportService.buildSemesterExcel(
        course: course,
        normalSlots: normalBundle.slots,
        normalSessions: normalSessions,
        makeupSlots: makeupBundle.slots,
        makeupSessions: makeupSessions,
      );
      final prefix = courseExportPrefix(course);
      await downloadBytesToDevice(bytes, '${prefix}_final_attendance.xlsx');
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Semester tables downloaded (Excel, 2 sheets).')));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportPercentage({required CourseModel course, required bool excel}) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final normalSessions = await ref.read(normalAttendanceSessionsProvider(course.courseId).future);
      final makeupSessions = await ref.read(makeupAttendanceSessionsProvider(course.courseId).future);
      final bytes = excel
          ? await _exportService.buildPercentageExcel(
              course: course,
              normalSessions: normalSessions,
              makeupSessions: makeupSessions,
            )
          : await _exportService.buildPercentageCsv(
              course: course,
              normalSessions: normalSessions,
              makeupSessions: makeupSessions,
            );
      final ext = excel ? 'xlsx' : 'csv';
      final prefix = courseExportPrefix(course);
      await downloadBytesToDevice(bytes, '${prefix}_attendance_percentage.$ext');
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Attendance percentage downloaded ($ext).')));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Widget _tableSwitcher() {
    Widget card({required _TableType type, required String title, required IconData icon}) {
      final active = _activeTable == type;
      return Expanded(
        child: InkWell(
          onTap: () {
            setState(() => _activeTable = type);
            ref.read(attendanceGridEditProvider.notifier).clear();
          },
          borderRadius: BorderRadius.circular(12),
          child: Card(
            elevation: active ? 3 : 1,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(icon),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(fontWeight: active ? FontWeight.w700 : FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        card(type: _TableType.normal, title: 'Normal Attendance Table', icon: Icons.table_rows_outlined),
        const SizedBox(width: 10),
        card(type: _TableType.makeup, title: 'Makeup Attendance Table', icon: Icons.event_repeat_outlined),
      ],
    );
  }

  Widget _exportBar(CourseModel course) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _isExporting ? null : () => _exportGridCsv(course),
          icon: const Icon(Icons.table_chart_outlined),
          label: const Text('Download semester table (CSV)'),
        ),
        OutlinedButton.icon(
          onPressed: _isExporting ? null : () => _exportGridExcel(course),
          icon: const Icon(Icons.grid_on_outlined),
          label: const Text('Download semester table (Excel)'),
        ),
        OutlinedButton.icon(
          onPressed: _isExporting ? null : () => _exportPercentage(course: course, excel: false),
          icon: const Icon(Icons.percent_outlined),
          label: const Text('Download attendance % (CSV)'),
        ),
        OutlinedButton.icon(
          onPressed: _isExporting ? null : () => _exportPercentage(course: course, excel: true),
          icon: const Icon(Icons.summarize_outlined),
          label: const Text('Download attendance % (Excel)'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(coursesProvider);
    final isMakeup = _activeTable == _TableType.makeup;
    final sessionsAsync = isMakeup
        ? ref.watch(makeupAttendanceSessionsProvider(widget.courseId))
        : ref.watch(normalAttendanceSessionsProvider(widget.courseId));

    return Scaffold(
      appBar: AppBar(title: Text(widget.mode.title)),
      body: coursesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load course: $e')),
        data: (courses) {
          final course = _findCourse(courses);
          if (course == null) {
            return const Center(child: Text('Course not found.'));
          }
          final isArchived = course.status == CourseStatus.archived;
          final effectiveMode = isArchived ? AttendanceViewMode.finalAttendance : widget.mode;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (isArchived && widget.mode != AttendanceViewMode.finalAttendance)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'This course is archived. Showing Final Attendance in read-only mode.',
                    ),
                  ),
                if (effectiveMode == AttendanceViewMode.finalAttendance) ...[
                  _exportBar(course),
                  if (_isExporting)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    ),
                  const SizedBox(height: 12),
                ],
                _tableSwitcher(),
                const SizedBox(height: 12),
                Expanded(
                  flex: effectiveMode == AttendanceViewMode.adjustments ? 7 : 10,
                  child: sessionsAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Failed to load sessions: $e')),
                    data: (sessions) => AttendanceGridWidget(
                      course: course,
                      sessions: sessions,
                      isMakeup: isMakeup,
                      mode: effectiveMode,
                      isSaving: _isSavingChanges,
                      onSave: effectiveMode == AttendanceViewMode.adjustments && !isArchived
                          ? () => _saveChanges(course, sessions)
                          : null,
                    ),
                  ),
                ),
                if (effectiveMode == AttendanceViewMode.adjustments && !isArchived) ...[
                  const SizedBox(height: 12),
                  Expanded(
                    flex: 3,
                    child: UnverifiedRecordsSection(
                      course: course,
                      onChanged: _refreshAttendanceViews,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
