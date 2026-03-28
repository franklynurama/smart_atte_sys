import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter/gestures.dart';

import '../../../../routes/app_routes.dart';
import '../../data/models/course_model.dart';
import '../providers/course_provider.dart';
import 'delete_course_dialog.dart';

class _AttendanceSlot {
  final String key;
  final DateTime date;
  final DateTime weekStartMonday;
  final String dayName;
  final String startTime;
  final String endTime;
  final int sessionIndex;

  const _AttendanceSlot({
    required this.key,
    required this.date,
    required this.weekStartMonday,
    required this.dayName,
    required this.startTime,
    required this.endTime,
    required this.sessionIndex,
  });
}

class ViewCoursesPage extends ConsumerStatefulWidget {
  const ViewCoursesPage({super.key});

  @override
  ConsumerState<ViewCoursesPage> createState() => _ViewCoursesPageState();
}

class _ViewCoursesPageState extends ConsumerState<ViewCoursesPage> {
  static const double _nameColWidth = 190;
  static const double _idColWidth = 130;
  static const double _slotColWidth = 150;
  static const double _headerRowHeight = 56;
  static const double _cellHeight = 46;

  late final ScrollController _leftVerticalController;
  late final ScrollController _rightVerticalController;
  late final ScrollController _rightHorizontalController;
  bool _syncing = false;

  String? _lastCourseId;
  int _lastSlotsLen = -1;

  @override
  void initState() {
    super.initState();
    _leftVerticalController = ScrollController();
    _rightVerticalController = ScrollController();
    _rightHorizontalController = ScrollController();

    _leftVerticalController.addListener(() => _syncVert(fromLeft: true));
    _rightVerticalController.addListener(() => _syncVert(fromLeft: false));
  }

  ScrollBehavior _scrollBehavior(BuildContext context) {
    // Enable mouse drag scrolling on Flutter Web (Firefox) + desktop.
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
        final target = leftOffset.clamp(
          0.0,
          _rightVerticalController.position.maxScrollExtent,
        );
        _rightVerticalController.jumpTo(target);
      } else {
        final target = rightOffset.clamp(
          0.0,
          _leftVerticalController.position.maxScrollExtent,
        );
        _leftVerticalController.jumpTo(target);
      }
    } finally {
      _syncing = false;
    }
  }

  @override
  void dispose() {
    _leftVerticalController.dispose();
    _rightVerticalController.dispose();
    _rightHorizontalController.dispose();
    super.dispose();
  }

  String _dayName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      default:
        return '';
    }
  }

  DateTime _mondayOfWeek(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  /// Whole calendar days between two instants (ignores clock time). Avoids week
  /// index bugs when one side is midnight-local and the other is a Firestore
  /// timestamp with a non-midnight clock.
  int _calendarDaysBetween(DateTime from, DateTime to) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  int _weekIndexFromSemesterMonday({
    required DateTime semesterWeekMonday,
    required DateTime weekStartMonday,
  }) {
    final sem = _mondayOfWeek(
      DateTime(
        semesterWeekMonday.year,
        semesterWeekMonday.month,
        semesterWeekMonday.day,
      ),
    );
    final ws = _mondayOfWeek(
      DateTime(
        weekStartMonday.year,
        weekStartMonday.month,
        weekStartMonday.day,
      ),
    );
    final diffDays = _calendarDaysBetween(sem, ws);
    return (diffDays ~/ 7) + 1;
  }

  Map<DateTime, int> _stableWeekNumbers({
    required List<DateTime> weekStarts,
    required DateTime semesterWeekMonday,
  }) {
    final sorted = List<DateTime>.from(weekStarts)..sort();
    final numbers = <DateTime, int>{};
    var last = 0;
    for (final weekStart in sorted) {
      final raw = _weekIndexFromSemesterMonday(
        semesterWeekMonday: semesterWeekMonday,
        weekStartMonday: weekStart,
      );
      final normalized = raw <= last ? last + 1 : raw;
      numbers[weekStart] = normalized;
      last = normalized;
    }
    return numbers;
  }

  int _timeToMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return (h * 60) + m;
  }

  List<_AttendanceSlot> _buildSlots(CourseModel course) {
    final keys = course.attendanceRecords.keys.toList()..sort();
    final semesterStart = DateTime(
      course.semesterStartDate.year,
      course.semesterStartDate.month,
      course.semesterStartDate.day,
    );
    final semesterWeekMonday = _mondayOfWeek(semesterStart);

    final slots = <_AttendanceSlot>[];
    for (final key in keys) {
      final parts = key.split('_');
      if (parts.length != 2) continue;
      final dateParts = parts[0].split('-');
      if (dateParts.length != 3) continue;

      final date = DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
      );
      final time = parts[1];

      final matchingSessionIndex = course.sessions.indexWhere(
        (s) => s.dayOfWeek == date.weekday && s.startTimeHHmm == time,
      );
      final matched = matchingSessionIndex == -1 ? null : course.sessions[matchingSessionIndex];

      final weekStartMonday = _mondayOfWeek(date);

      slots.add(
        _AttendanceSlot(
          key: key,
          date: date,
          weekStartMonday: weekStartMonday,
          dayName: _dayName(date.weekday),
          startTime: time,
          endTime: matched?.endTimeHHmm ?? time,
          sessionIndex: matchingSessionIndex == -1 ? 1 : matchingSessionIndex + 1,
        ),
      );
    }
    // Enforce stable ordering: Week -> weekday -> start time -> session index.
    slots.sort((a, b) {
      final w = a.weekStartMonday.compareTo(b.weekStartMonday);
      if (w != 0) return w;
      final d = a.date.weekday.compareTo(b.date.weekday);
      if (d != 0) return d;
      final t = _timeToMinutes(a.startTime).compareTo(_timeToMinutes(b.startTime));
      if (t != 0) return t;
      return a.sessionIndex.compareTo(b.sessionIndex);
    });

    // Sanity: if semester start isn't Monday, week numbers are still consistent
    // because we anchor to the Monday of the semester-start week.
    // (We don't store week number on the slot anymore; it is derived when rendering.)
    // Avoid unused variable lint in case of future refactors.
    // ignore: unused_local_variable
    final _ = semesterWeekMonday;

    return slots;
  }

  Map<DateTime, List<_AttendanceSlot>> _groupSlotsByWeekStartMonday(
    List<_AttendanceSlot> slots,
  ) {
    final grouped = <int, List<_AttendanceSlot>>{};
    for (final slot in slots) {
      final k = slot.weekStartMonday;
      grouped.putIfAbsent(k.millisecondsSinceEpoch, () => []).add(slot);
    }

    final ordered = grouped.entries.toList()
      ..sort((a, b) => a.value.first.weekStartMonday.compareTo(b.value.first.weekStartMonday));

    final result = <DateTime, List<_AttendanceSlot>>{};
    for (final entry in ordered) {
      final weekSlots = List<_AttendanceSlot>.from(entry.value)
        ..sort((a, b) {
          final d = a.date.weekday.compareTo(b.date.weekday);
          if (d != 0) return d;
          final t = _timeToMinutes(a.startTime).compareTo(_timeToMinutes(b.startTime));
          if (t != 0) return t;
          return a.sessionIndex.compareTo(b.sessionIndex);
        });
      result[weekSlots.first.weekStartMonday] = weekSlots;
    }
    return result;
  }

  String _weekRangeLabel(DateTime weekStartMonday) {
    final monday = DateTime(weekStartMonday.year, weekStartMonday.month, weekStartMonday.day);
    final sunday = monday.add(const Duration(days: 6));
    final fmt = DateFormat('dd MMM yyyy');
    return '(${fmt.format(monday)} - ${fmt.format(sunday)})';
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
        child: fitText
            ? FittedBox(
                fit: BoxFit.scaleDown,
                child: text,
              )
            : text,
      ),
    );
  }

  Widget _dataCell(BuildContext context, {required Widget child, required double width}) {
    return Container(
      width: width,
      height: _cellHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: child,
    );
  }

  Widget _buildLeftHeader({
    required BuildContext context,
  }) {
    return SizedBox(
      width: _nameColWidth + _idColWidth,
      height: _headerRowHeight * 2,
      child: Column(
        children: [
          Row(
            children: [
              _headerCell(
                context,
                label: 'Student Name',
                width: _nameColWidth,
                height: _headerRowHeight,
              ),
              _headerCell(
                context,
                label: 'Student ID',
                width: _idColWidth,
                height: _headerRowHeight,
              ),
            ],
          ),
          Row(
            children: [
              _headerCell(
                context,
                label: '',
                width: _nameColWidth,
                height: _headerRowHeight,
                fontWeight: FontWeight.w400,
              ),
              _headerCell(
                context,
                label: '',
                width: _idColWidth,
                height: _headerRowHeight,
                fontWeight: FontWeight.w400,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRightHeader({
    required BuildContext context,
    required Map<DateTime, List<_AttendanceSlot>> grouped,
    required List<_AttendanceSlot> slots,
    required DateTime semesterWeekMonday,
  }) {
    final rightWidth = _slotColWidth * slots.length;
    final weekStarts = grouped.keys.toList()..sort();
    final weekNumbers = _stableWeekNumbers(
      weekStarts: weekStarts,
      semesterWeekMonday: semesterWeekMonday,
    );
    final dateFmt = DateFormat('dd MMM');

    return SizedBox(
      width: rightWidth,
      height: _headerRowHeight * 2,
      child: Column(
        children: [
          // Row 1: week merged headers
          SizedBox(
            height: _headerRowHeight,
            child: Row(
              children: [
                for (final weekStart in weekStarts)
                  _headerCell(
                    context,
                    label:
                        'Week ${weekNumbers[weekStart]}\n${_weekRangeLabel(weekStart)}',
                    width: _slotColWidth * grouped[weekStart]!.length,
                    height: _headerRowHeight,
                  ),
              ],
            ),
          ),
          // Row 2: session headers (no FittedBox — it scaled longer labels down so S2 looked "not bold")
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
                    fontWeight: FontWeight.w700,
                    fitText: false,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedCourseProvider).courseId;

    ref.listen(coursesProvider, (prev, next) {
      final list = next.valueOrNull;
      if ((selected == null || selected.isEmpty) && list != null && list.isNotEmpty) {
        ref.read(selectedCourseProvider.notifier).select(list.first.courseId);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Courses'),
        actions: [
          IconButton(
            tooltip: 'Add course',
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.addCourse),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: SafeArea(
        child: ref.watch(coursesProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed to load courses: $e')),
              data: (courses) {
                final CourseModel? current;
                if (selected == null) {
                  current = courses.isNotEmpty ? courses.first : null;
                } else {
                  final match = courses.where((c) => c.courseId == selected);
                  current = match.isNotEmpty ? match.first : (courses.isNotEmpty ? courses.first : null);
                }

                if (current == null) {
                  return const Center(child: Text('No courses yet. Add your first course.'));
                }

                final activeCourse = current;
                final slots = _buildSlots(activeCourse);
                final semesterStart = DateTime(
                  activeCourse.semesterStartDate.year,
                  activeCourse.semesterStartDate.month,
                  activeCourse.semesterStartDate.day,
                );
                final semesterWeekMonday = _mondayOfWeek(semesterStart);
                final grouped = _groupSlotsByWeekStartMonday(slots);

                // Reset scroll when switching course / structure changes.
                if (_lastCourseId != activeCourse.courseId || _lastSlotsLen != slots.length) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_leftVerticalController.hasClients) _leftVerticalController.jumpTo(0);
                    if (_rightVerticalController.hasClients) _rightVerticalController.jumpTo(0);
                  });
                  _lastCourseId = activeCourse.courseId;
                  _lastSlotsLen = slots.length;
                }

                const leftWidth = _nameColWidth + _idColWidth;
                final rightWidth = _slotColWidth * slots.length;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: activeCourse.courseId,
                              decoration: const InputDecoration(labelText: 'Select course'),
                              items: courses
                                  .map(
                                    (c) => DropdownMenuItem<String>(
                                      value: c.courseId,
                                      child: Text('${c.courseCode} • ${c.abbreviation}'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                ref.read(selectedCourseProvider.notifier).select(v);
                              },
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete course',
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
                          ),
                        ],
                      ),
                    ),
                    if (slots.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No attendance slots found for this course yet.'),
                      )
                    else
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Frozen left columns.
                            SizedBox(
                              width: leftWidth,
                              child: Column(
                                children: [
                                  _buildLeftHeader(context: context),
                                  Expanded(
                                    child: ListView.builder(
                                      controller: _leftVerticalController,
                                      itemCount: activeCourse.students.length,
                                      itemBuilder: (context, index) {
                                        final student = activeCourse.students[index];
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
                                              _dataCell(
                                                context,
                                                width: _idColWidth,
                                                child: Text(student.studentId),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Scrollable right side (week/session headers + attendance cells).
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
                                            context: context,
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
                                                itemCount: activeCourse.students.length,
                                                itemBuilder: (context, index) {
                                                  final student = activeCourse.students[index];
                                                  return SizedBox(
                                                    height: _cellHeight,
                                                    child: Row(
                                                      children: [
                                                        for (final slot in slots)
                                                          _dataCell(
                                                            context,
                                                            width: _slotColWidth,
                                                            child: ((activeCourse.attendanceRecords[slot.key]?[student.studentId] ??
                                                                        false))
                                                                ? const Text(
                                                                    '✔',
                                                                    style: TextStyle(
                                                                      color: Colors.green,
                                                                      fontWeight: FontWeight.bold,
                                                                    ),
                                                                  )
                                                                : const SizedBox.shrink(),
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
              },
            ),
      ),
    );
  }
}

