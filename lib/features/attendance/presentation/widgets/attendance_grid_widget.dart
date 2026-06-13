import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../courses/data/models/course_model.dart';
import '../../../courses/data/models/student_model.dart';
import '../../data/models/attendance_session_model.dart';
import '../../domain/attendance_merge.dart';
import '../models/attendance_view_mode.dart';
import '../providers/attendance_provider.dart';
import '../providers/attendance_slots_provider.dart';
import '../utils/attendance_slot_builder.dart';

class AttendanceGridWidget extends ConsumerStatefulWidget {
  final CourseModel course;
  final List<AttendanceSessionModel> sessions;
  final bool isMakeup;
  final AttendanceViewMode mode;
  final bool isSaving;
  final VoidCallback? onSave;

  const AttendanceGridWidget({
    super.key,
    required this.course,
    required this.sessions,
    required this.isMakeup,
    required this.mode,
    this.isSaving = false,
    this.onSave,
  });

  @override
  ConsumerState<AttendanceGridWidget> createState() => _AttendanceGridWidgetState();
}

class _AttendanceGridWidgetState extends ConsumerState<AttendanceGridWidget> {
  static const double _nameColWidth = 190;
  static const double _idColWidth = 130;
  static const double _slotColWidth = 150;
  static const double _headerRowHeight = 56;
  static const double _cellHeight = 46;

  late final ScrollController _leftVerticalController;
  late final ScrollController _rightVerticalController;
  late final ScrollController _rightHorizontalController;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _leftVerticalController = ScrollController();
    _rightVerticalController = ScrollController();
    _rightHorizontalController = ScrollController();
    _leftVerticalController.addListener(() => _syncVert(fromLeft: true));
    _rightVerticalController.addListener(() => _syncVert(fromLeft: false));
  }

  @override
  void dispose() {
    _leftVerticalController.dispose();
    _rightVerticalController.dispose();
    _rightHorizontalController.dispose();
    super.dispose();
  }

  ScrollBehavior _scrollBehavior(BuildContext context) {
    final base = ScrollConfiguration.of(context);
    return base.copyWith(
      dragDevices: const {
        PointerDeviceKind.mouse,
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      },
      scrollbars: false,
    );
  }

  void _syncVert({required bool fromLeft}) {
    if (_syncing) return;
    if (!_leftVerticalController.hasClients || !_rightVerticalController.hasClients) return;
    final leftOffset = _leftVerticalController.offset;
    final rightOffset = _rightVerticalController.offset;
    if ((leftOffset - rightOffset).abs() <= 1.0) return;
    _syncing = true;
    try {
      if (fromLeft) {
        _rightVerticalController.jumpTo(
          leftOffset.clamp(0.0, _rightVerticalController.position.maxScrollExtent),
        );
      } else {
        _leftVerticalController.jumpTo(
          rightOffset.clamp(0.0, _leftVerticalController.position.maxScrollExtent),
        );
      }
    } finally {
      _syncing = false;
    }
  }

  Widget _headerCell(
    BuildContext context, {
    required String label,
    required double width,
    required double height,
    FontWeight fontWeight = FontWeight.w700,
    bool fitText = true,
  }) {
    final baseStyle = Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: fontWeight);
    final text = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: fitText ? 2 : 3,
      overflow: fitText ? TextOverflow.visible : TextOverflow.ellipsis,
      style: baseStyle,
    );
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Center(
        child: fitText ? FittedBox(fit: BoxFit.scaleDown, child: text) : text,
      ),
    );
  }

  Widget _dataCell(BuildContext context, {required Widget child, required double width}) {
    return Container(
      width: width,
      height: _cellHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor)),
      child: child,
    );
  }

  Widget _buildLeftHeader(BuildContext context) {
    if (widget.isMakeup) {
      return SizedBox(
        width: _nameColWidth + _idColWidth,
        height: _headerRowHeight,
        child: Row(
          children: [
            _headerCell(context, label: 'Student Name', width: _nameColWidth, height: _headerRowHeight),
            _headerCell(context, label: 'Student ID', width: _idColWidth, height: _headerRowHeight),
          ],
        ),
      );
    }
    return SizedBox(
      width: _nameColWidth + _idColWidth,
      height: _headerRowHeight * 2,
      child: Column(
        children: [
          Row(
            children: [
              _headerCell(context, label: 'Student Name', width: _nameColWidth, height: _headerRowHeight),
              _headerCell(context, label: 'Student ID', width: _idColWidth, height: _headerRowHeight),
            ],
          ),
          Row(
            children: [
              _headerCell(context, label: '', width: _nameColWidth, height: _headerRowHeight, fontWeight: FontWeight.w400),
              _headerCell(context, label: '', width: _idColWidth, height: _headerRowHeight, fontWeight: FontWeight.w400),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRightHeader(
    BuildContext context, {
    required Map<DateTime, List<AttendanceSlot>> grouped,
    required List<AttendanceSlot> slots,
    required DateTime semesterWeekMonday,
  }) {
    final rightWidth = _slotColWidth * slots.length;
    final weekStarts = grouped.keys.toList()..sort();
    final weekNumbers = stableWeekNumbers(weekStarts: weekStarts, semesterWeekMonday: semesterWeekMonday);
    final dateFmt = DateFormat('dd MMM');
    final makeupDateFmt = DateFormat('dd MMM yyyy');

    return SizedBox(
      width: rightWidth,
      height: widget.isMakeup ? _headerRowHeight : _headerRowHeight * 2,
      child: Column(
        children: [
          if (!widget.isMakeup)
            SizedBox(
              height: _headerRowHeight,
              child: Row(
                children: [
                  for (final weekStart in weekStarts)
                    _headerCell(
                      context,
                      label: 'Week ${weekNumbers[weekStart]}\n${weekRangeLabel(weekStart)}',
                      width: _slotColWidth * grouped[weekStart]!.length,
                      height: _headerRowHeight,
                    ),
                ],
              ),
            )
          else
            SizedBox(
              height: _headerRowHeight,
              child: Row(
                children: [
                  for (final slot in slots)
                    _headerCell(
                      context,
                      label:
                          '${makeupDateFmt.format(slot.date)} (${slot.dayName.substring(0, 3)})\n${slot.startTime}-${slot.endTime}',
                      width: _slotColWidth,
                      height: _headerRowHeight,
                      fitText: false,
                    ),
                ],
              ),
            ),
          if (!widget.isMakeup)
            SizedBox(
              height: _headerRowHeight,
              child: Row(
                children: [
                  for (final slot in slots)
                    _headerCell(
                      context,
                      label:
                          'S${slot.sessionIndex} - ${slot.dayName.substring(0, 3)} (${dateFmt.format(slot.date)})\n${slot.startTime} - ${slot.endTime}',
                      width: _slotColWidth,
                      height: _headerRowHeight,
                      fitText: false,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  bool _cellPresent({
    required AttendanceViewMode mode,
    required Map<String, bool> raw,
    required Map<String, bool> manual,
    required Map<String, Map<String, bool>> draft,
    required String sessionId,
    required String studentId,
  }) {
    return switch (mode) {
      AttendanceViewMode.imported => raw[studentId] ?? false,
      AttendanceViewMode.adjustments =>
        draft[sessionId]?[studentId] ?? adjustmentsDisplay(manual, raw, studentId),
      AttendanceViewMode.finalAttendance => effectivePresent(manual, raw, studentId),
    };
  }

  @override
  Widget build(BuildContext context) {
    final bundle = ref.watch(
      attendanceSlotsBundleProvider(
        AttendanceSlotsRequest(
          course: widget.course,
          sessions: widget.sessions,
          isMakeup: widget.isMakeup,
        ),
      ),
    );
    final slots = bundle.slots;
    final grouped = bundle.grouped;

    final rawBySession = {
      for (final s in widget.sessions) s.sessionId: s.attendanceMapRaw,
    };
    final manualBySession = {
      for (final s in widget.sessions) s.sessionId: s.attendanceMapManual,
    };

    final edits = ref.watch(attendanceGridEditProvider);
    final draft = widget.isMakeup ? edits.makeupDraft : edits.normalDraft;

    final semesterStart = DateTime(
      widget.course.semesterStartDate.year,
      widget.course.semesterStartDate.month,
      widget.course.semesterStartDate.day,
    );
    final semesterWeekMonday = mondayOfWeek(semesterStart);

    if (slots.isEmpty) {
      return const Center(child: Text('No attendance slots found for this table yet.'));
    }

    const leftWidth = _nameColWidth + _idColWidth;
    final rightWidth = _slotColWidth * slots.length;
    final showSave = widget.mode == AttendanceViewMode.adjustments;

    return Column(
      children: [
        if (showSave)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.isMakeup ? 'Makeup Attendance' : 'Normal Attendance',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                FilledButton.icon(
                  onPressed: widget.isSaving ? null : widget.onSave,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save Changes'),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.isMakeup ? 'Makeup Attendance' : 'Normal Attendance',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        if (widget.isSaving)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Saving attendance changes...'),
              ],
            ),
          ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: leftWidth,
                child: Column(
                  children: [
                    _buildLeftHeader(context),
                    Expanded(
                      child: ListView.builder(
                        controller: _leftVerticalController,
                        itemCount: widget.course.students.length,
                        itemBuilder: (context, index) {
                          final student = widget.course.students[index];
                          return SizedBox(
                            height: _cellHeight,
                            child: Row(
                              children: [
                                _dataCell(
                                  context,
                                  width: _nameColWidth,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(student.studentName),
                                    ),
                                  ),
                                ),
                                _dataCell(context, width: _idColWidth, child: Text(student.studentId)),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ScrollConfiguration(
                  behavior: _scrollBehavior(context),
                  child: Scrollbar(
                    controller: _rightHorizontalController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    interactive: true,
                    child: SingleChildScrollView(
                      controller: _rightHorizontalController,
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: SizedBox(
                        width: rightWidth,
                        child: Column(
                          children: [
                            _buildRightHeader(
                              context,
                              grouped: grouped,
                              slots: slots,
                              semesterWeekMonday: semesterWeekMonday,
                            ),
                            Expanded(
                              child: Scrollbar(
                                controller: _rightVerticalController,
                                thumbVisibility: true,
                                interactive: true,
                                child: ListView.builder(
                                  controller: _rightVerticalController,
                                  itemCount: widget.course.students.length,
                                  itemBuilder: (context, index) {
                                    final student = widget.course.students[index];
                                    return SizedBox(
                                      height: _cellHeight,
                                      child: Row(
                                        children: [
                                          for (final slot in slots)
                                            _dataCell(
                                              context,
                                              width: _slotColWidth,
                                              child: _buildCell(
                                                raw: rawBySession[slot.key] ?? const {},
                                                manual: manualBySession[slot.key] ?? const {},
                                                sessionId: slot.key,
                                                student: student,
                                                draft: draft,
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCell({
    required Map<String, bool> raw,
    required Map<String, bool> manual,
    required String sessionId,
    required StudentModel student,
    required Map<String, Map<String, bool>> draft,
  }) {
    final present = _cellPresent(
      mode: widget.mode,
      raw: raw,
      manual: manual,
      draft: draft,
      sessionId: sessionId,
      studentId: student.studentId,
    );

    if (widget.mode == AttendanceViewMode.adjustments) {
      return Checkbox(
        value: present,
        onChanged: widget.isSaving
            ? null
            : (v) {
                if (v == null) return;
                ref.read(attendanceGridEditProvider.notifier).toggle(
                      isMakeup: widget.isMakeup,
                      sessionId: sessionId,
                      studentId: student.studentId,
                      value: v,
                    );
              },
      );
    }

    return present
        ? const Icon(Icons.check, size: 20)
        : const SizedBox.shrink();
  }
}
