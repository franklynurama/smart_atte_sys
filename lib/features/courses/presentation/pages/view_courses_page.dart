import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';

import '../../../../routes/app_routes.dart';
import '../../../attendance/data/models/attendance_session_model.dart';
import '../../../attendance/data/models/unverified_record_model.dart';
import '../../../attendance/data/services/attendance_service.dart';
import '../../../attendance/presentation/providers/attendance_provider.dart';
import '../../data/models/course_model.dart';
import '../../data/models/student_model.dart';
import '../providers/course_provider.dart';
import 'delete_course_dialog.dart';

enum _AttendanceViewType { normal, makeup }

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

class _SlotsBundle {
  final List<_AttendanceSlot> slots;
  final Map<DateTime, List<_AttendanceSlot>> grouped;

  const _SlotsBundle({
    required this.slots,
    required this.grouped,
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
  bool _isSavingChanges = false;
  _AttendanceViewType _activeView = _AttendanceViewType.normal;
  final AttendanceService _attendanceService = AttendanceService();

  String? _lastCourseId;
  int _lastSlotsLen = -1;
  String? _lastSlotsCacheKey;
  _SlotsBundle? _lastSlotsBundle;

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

  List<_AttendanceSlot> _buildSlots({
    required CourseModel course,
    required List<AttendanceSessionModel> sessions,
    required bool isMakeup,
  }) {
    final slots = <_AttendanceSlot>[];
    for (final session in sessions) {
      DateTime? date;
      String startTime = '';
      String endTime = '';

      if (isMakeup) {
        final dateParts = session.date.split('-');
        if (dateParts.length == 3) {
          date = DateTime(
            int.tryParse(dateParts[0]) ?? 1970,
            int.tryParse(dateParts[1]) ?? 1,
            int.tryParse(dateParts[2]) ?? 1,
          );
        }
        startTime = session.startTimeHHmm;
        endTime = session.endTimeHHmm;
      } else {
        final parts = session.sessionId.split('_');
        if (parts.length == 2) {
          final dateParts = parts[0].split('-');
          if (dateParts.length == 3) {
            date = DateTime(
              int.tryParse(dateParts[0]) ?? 1970,
              int.tryParse(dateParts[1]) ?? 1,
              int.tryParse(dateParts[2]) ?? 1,
            );
          }
          startTime = parts[1];
        }
      }
      if (date == null || startTime.isEmpty) continue;
      final sessionDate = date;

      final matchingSessionIndex = course.sessions.indexWhere(
        (s) => s.dayOfWeek == sessionDate.weekday && s.startTimeHHmm == startTime,
      );
      final matched = matchingSessionIndex == -1 ? null : course.sessions[matchingSessionIndex];
      final effectiveEnd = endTime.isNotEmpty ? endTime : (matched?.endTimeHHmm ?? startTime);
      final weekStartMonday = _mondayOfWeek(sessionDate);

      slots.add(
        _AttendanceSlot(
          key: session.sessionId,
          date: sessionDate,
          weekStartMonday: weekStartMonday,
          dayName: _dayName(sessionDate.weekday),
          startTime: startTime,
          endTime: effectiveEnd,
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

  _SlotsBundle _resolveSlotsBundle({
    required CourseModel course,
    required List<AttendanceSessionModel> sessions,
    required bool isMakeup,
  }) {
    final sig = sessions.map((s) => s.sessionId).join('|');
    final key = '${course.courseId}|${isMakeup ? 'makeup' : 'normal'}|$sig';
    if (_lastSlotsCacheKey == key && _lastSlotsBundle != null) {
      return _lastSlotsBundle!;
    }
    final slots = _buildSlots(course: course, sessions: sessions, isMakeup: isMakeup);
    final grouped = _groupSlotsByWeekStartMonday(slots);
    final bundle = _SlotsBundle(slots: slots, grouped: grouped);
    _lastSlotsCacheKey = key;
    _lastSlotsBundle = bundle;
    return bundle;
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

  Future<void> _refreshAttendanceViews(String courseId) async {
    ref.invalidate(coursesProvider);
    ref.invalidate(normalAttendanceSessionsProvider(courseId));
    ref.invalidate(makeupAttendanceSessionsProvider(courseId));
    ref.invalidate(unverifiedRecordsProvider(courseId));
  }

  Widget _buildLeftHeader({
    required BuildContext context,
    required bool isMakeup,
  }) {
    if (isMakeup) {
      return SizedBox(
        width: _nameColWidth + _idColWidth,
        height: _headerRowHeight,
        child: Row(
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
      );
    }

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
    required bool isMakeup,
  }) {
    final rightWidth = _slotColWidth * slots.length;
    final weekStarts = grouped.keys.toList()..sort();
    final weekNumbers = _stableWeekNumbers(
      weekStarts: weekStarts,
      semesterWeekMonday: semesterWeekMonday,
    );
    final dateFmt = DateFormat('dd MMM');
    final makeupDateFmt = DateFormat('dd MMM yyyy');

    return SizedBox(
      width: rightWidth,
      height: isMakeup ? _headerRowHeight : _headerRowHeight * 2,
      child: Column(
        children: [
          if (!isMakeup)
            ...[
              SizedBox(
                height: _headerRowHeight,
                child: Row(
                  children: [
                    for (final weekStart in weekStarts)
                      _headerCell(
                        context,
                        label: 'Week ${weekNumbers[weekStart]}\n${_weekRangeLabel(weekStart)}',
                        width: _slotColWidth * grouped[weekStart]!.length,
                        height: _headerRowHeight,
                      ),
                  ],
                ),
              ),
            ]
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
          if (!isMakeup)
            // Row 2: session headers for normal table.
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

  Widget _viewSwitcher() {
    Widget card({required _AttendanceViewType type, required String title, required IconData icon}) {
      final active = _activeView == type;
      return Expanded(
        child: InkWell(
          onTap: () {
            setState(() => _activeView = type);
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
        card(type: _AttendanceViewType.normal, title: 'Normal Attendance Table', icon: Icons.table_rows_outlined),
        const SizedBox(width: 10),
        card(type: _AttendanceViewType.makeup, title: 'Makeup Attendance Table', icon: Icons.event_repeat_outlined),
      ],
    );
  }

  Widget _attendanceSection({
    required BuildContext context,
    required CourseModel course,
    required AsyncValue<List<AttendanceSessionModel>> sessionsAsync,
    required bool isMakeup,
  }) {
    return sessionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load sessions: $e')),
      data: (sessions) {
        final bundle = _resolveSlotsBundle(course: course, sessions: sessions, isMakeup: isMakeup);
        final slots = bundle.slots;
        final grouped = bundle.grouped;
        final sourceMap = <String, Map<String, bool>>{for (final s in sessions) s.sessionId: s.attendanceMap};
        final edits = ref.watch(attendanceGridEditProvider);
        final draft = isMakeup ? edits.makeupDraft : edits.normalDraft;

        final semesterStart = DateTime(
          course.semesterStartDate.year,
          course.semesterStartDate.month,
          course.semesterStartDate.day,
        );
        final semesterWeekMonday = _mondayOfWeek(semesterStart);

        if (_lastCourseId != '${course.courseId}-${isMakeup ? 'makeup' : 'normal'}' || _lastSlotsLen != slots.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_leftVerticalController.hasClients) _leftVerticalController.jumpTo(0);
            if (_rightVerticalController.hasClients) _rightVerticalController.jumpTo(0);
          });
          _lastCourseId = '${course.courseId}-${isMakeup ? 'makeup' : 'normal'}';
          _lastSlotsLen = slots.length;
        }

        const leftWidth = _nameColWidth + _idColWidth;
        final rightWidth = _slotColWidth * slots.length;
        if (slots.isEmpty) {
          return const Center(child: Text('No attendance slots found for this table yet.'));
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isMakeup ? 'Makeup Attendance' : 'Normal Attendance',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  FilledButton.icon(
                    onPressed: _isSavingChanges
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            if (mounted) {
                              setState(() => _isSavingChanges = true);
                            }
                            try {
                              final latestEdits = ref.read(attendanceGridEditProvider);
                              final latestDraft = isMakeup ? latestEdits.makeupDraft : latestEdits.normalDraft;
                              final changedSessions = <String, Map<String, bool>>{};
                              final sessionIds = <String>{...sourceMap.keys, ...latestDraft.keys};
                              for (final sessionId in sessionIds) {
                                final base = Map<String, bool>.from(sourceMap[sessionId] ?? const <String, bool>{});
                                final overlay = latestDraft[sessionId];
                                if (overlay == null) continue;
                                final merged = Map<String, bool>.from(base)..addAll(overlay);
                                if (!mapEquals(base, merged)) {
                                  changedSessions[sessionId] = merged;
                                }
                              }
                              if (changedSessions.isEmpty) {
                                if (!context.mounted) return;
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('No attendance changes to save.')),
                                );
                                return;
                              }
                              await _attendanceService.saveAttendanceMapBatch(
                                courseId: course.courseId,
                                isMakeup: isMakeup,
                                sessions: changedSessions,
                              );
                              ref.read(attendanceGridEditProvider.notifier).clear();
                              await _refreshAttendanceViews(course.courseId);
                              if (!context.mounted) return;
                              messenger.showSnackBar(const SnackBar(content: Text('Attendance changes saved.')));
                            } catch (e) {
                              if (!context.mounted) return;
                              messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
                            } finally {
                              if (mounted) {
                                setState(() => _isSavingChanges = false);
                              }
                            }
                          },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save Changes'),
                  ),
                ],
              ),
            ),
            if (_isSavingChanges)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
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
                        _buildLeftHeader(context: context, isMakeup: isMakeup),
                        Expanded(
                          child: ListView.builder(
                            controller: _leftVerticalController,
                            itemCount: course.students.length,
                            itemBuilder: (context, index) {
                              final student = course.students[index];
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
                                  isMakeup: isMakeup,
                                ),
                                Expanded(
                                  child: Scrollbar(
                                    controller: _rightVerticalController,
                                    thumbVisibility: true,
                                    interactive: true,
                                    child: ListView.builder(
                                      controller: _rightVerticalController,
                                      itemCount: course.students.length,
                                      itemBuilder: (context, index) {
                                        final student = course.students[index];
                                        return SizedBox(
                                          height: _cellHeight,
                                          child: Row(
                                            children: [
                                              for (final slot in slots)
                                                _dataCell(
                                                  context,
                                                  width: _slotColWidth,
                                                  child: Checkbox(
                                                    value: (draft[slot.key]?[student.studentId] ??
                                                        sourceMap[slot.key]?[student.studentId] ??
                                                        false),
                                                    onChanged: _isSavingChanges
                                                        ? null
                                                        : (v) {
                                                      if (v == null) return;
                                                      ref.read(attendanceGridEditProvider.notifier).toggle(
                                                            isMakeup: isMakeup,
                                                            sessionId: slot.key,
                                                            studentId: student.studentId,
                                                            value: v,
                                                          );
                                                    },
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
      },
    );
  }

  Widget _unverifiedSection({required BuildContext context, required CourseModel course}) {
    final unverifiedAsync = ref.watch(unverifiedRecordsProvider(course.courseId));
    final normalAsync = ref.watch(normalAttendanceSessionsProvider(course.courseId));
    final makeupAsync = ref.watch(makeupAttendanceSessionsProvider(course.courseId));

    String sessionDisplayLabel(AttendanceSessionModel session) {
      if (session.isMakeup) {
        return 'Makeup • ${session.date} ${session.startTimeHHmm}-${session.endTimeHHmm}';
      }

      final parts = session.sessionId.split('_');
      final date = parts.isNotEmpty ? parts.first : session.date;
      final start = parts.length > 1 ? parts[1] : session.startTimeHHmm;
      if (date.isEmpty || start.isEmpty) {
        return 'Normal • ${session.sessionId}';
      }

      String end = session.endTimeHHmm;
      final dateParts = date.split('-');
      if (dateParts.length == 3) {
        final y = int.tryParse(dateParts[0]);
        final m = int.tryParse(dateParts[1]);
        final d = int.tryParse(dateParts[2]);
        if (y != null && m != null && d != null) {
          final weekday = DateTime(y, m, d).weekday;
          final matched = course.sessions.where(
            (s) => s.dayOfWeek == weekday && s.startTimeHHmm == start,
          );
          if (matched.isNotEmpty) {
            end = matched.first.endTimeHHmm;
          }
        }
      }
      if (end.isEmpty) end = start;
      return 'Normal • $date $start-$end';
    }

    Future<bool> confirmPermanentDelete(UnverifiedRecordModel record) async {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete unverified record?'),
          content: Text(
            'Ignore record for ${record.studentName} (${record.studentId})?\n\n'
            'This record will be permanently deleted and cannot be recovered.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      return result ?? false;
    }

    Future<String?> pickSessionId(
      List<AttendanceSessionModel> options,
      String title, {
      String? preferredSessionId,
    }) async {
      if (options.isEmpty) return null;
      String current = options.first.sessionId;
      if (preferredSessionId != null && preferredSessionId.isNotEmpty) {
        final matched = options.where((o) => o.sessionId == preferredSessionId);
        if (matched.isNotEmpty) {
          current = matched.first.sessionId;
        }
      }
      return showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: StatefulBuilder(
            builder: (ctx, setLocal) => DropdownButton<String>(
              value: current,
              isExpanded: true,
              items: options
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.sessionId,
                      child: Text(
                        sessionDisplayLabel(e),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setLocal(() => current = v);
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(current), child: const Text('Select')),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: unverifiedAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Failed to load unverified records: $e')),
          data: (records) {
            final allSessions = [...(normalAsync.valueOrNull ?? const <AttendanceSessionModel>[]), ...(makeupAsync.valueOrNull ?? const <AttendanceSessionModel>[])];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Unverified Records', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (records.isEmpty)
                  const Expanded(child: Center(child: Text('No unverified records.')))
                else
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Name')),
                            DataColumn(label: Text('ID')),
                            DataColumn(label: Text('Type')),
                            DataColumn(label: Text('Date')),
                            DataColumn(label: Text('Time')),
                            DataColumn(label: Text('Add Student')),
                            DataColumn(label: Text('Mark Present')),
                            DataColumn(label: Text('Delete')),
                          ],
                          rows: [
                            for (final r in records)
                              DataRow(
                                cells: [
                                  DataCell(Text(r.studentName)),
                                  DataCell(Text(r.studentId)),
                                  DataCell(Text(r.isMakeup ? 'Makeup' : 'Normal')),
                                  DataCell(Text(r.date)),
                                  DataCell(Text(r.time)),
                                  DataCell(
                                    FilledButton(
                                      onPressed: () async {
                                        final messenger = ScaffoldMessenger.of(context);
                                        try {
                                          var addedStudent = false;
                                          final exists = course.students.any((s) => s.studentId == r.studentId);
                                          if (!exists) {
                                            await _attendanceService.addStudentToCourse(
                                              courseId: course.courseId,
                                              student: StudentModel(studentName: r.studentName, studentId: r.studentId, department: ''),
                                            );
                                            addedStudent = true;
                                          }
                                          final selectedSession = await pickSessionId(
                                            allSessions,
                                            'Select session',
                                            preferredSessionId: r.rawSessionId,
                                          );
                                          if (selectedSession == null) return;
                                          final target = allSessions.where((s) => s.sessionId == selectedSession).toList();
                                          if (target.isEmpty) return;
                                          final picked = target.first;
                                          final map = Map<String, bool>.from(picked.attendanceMap)..[r.studentId] = true;
                                          await _attendanceService.saveAttendanceMapBatch(
                                            courseId: course.courseId,
                                            isMakeup: picked.isMakeup,
                                            sessions: {selectedSession: map},
                                          );
                                          await _attendanceService.deleteUnverifiedRecord(
                                            courseId: course.courseId,
                                            recordId: r.id,
                                          );
                                          if (addedStudent) {
                                            ref.invalidate(coursesProvider);
                                          }
                                          ref.read(attendanceGridEditProvider.notifier).clear();
                                          await _refreshAttendanceViews(course.courseId);
                                          if (!context.mounted) return;
                                          messenger.showSnackBar(const SnackBar(content: Text('Student added and marked present.')));
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          messenger.showSnackBar(SnackBar(content: Text(e.toString())));
                                        }
                                      },
                                      child: const Text('Add Student'),
                                    ),
                                  ),
                                  DataCell(
                                    FilledButton(
                                      onPressed: () async {
                                        final messenger = ScaffoldMessenger.of(context);
                                        final exists = course.students.any((s) => s.studentId == r.studentId);
                                        if (!exists) {
                                          messenger.showSnackBar(const SnackBar(content: Text('Student not in roster. Use Add Student first.')));
                                          return;
                                        }
                                        final selectedSession = await pickSessionId(
                                          allSessions,
                                          'Select session',
                                          preferredSessionId: r.rawSessionId,
                                        );
                                        if (selectedSession == null) return;
                                        try {
                                          final target = allSessions.where((s) => s.sessionId == selectedSession).toList();
                                          if (target.isEmpty) return;
                                          final picked = target.first;
                                          final map = Map<String, bool>.from(picked.attendanceMap)..[r.studentId] = true;
                                          await _attendanceService.saveAttendanceMapBatch(
                                            courseId: course.courseId,
                                            isMakeup: picked.isMakeup,
                                            sessions: {selectedSession: map},
                                          );
                                          await _attendanceService.deleteUnverifiedRecord(
                                            courseId: course.courseId,
                                            recordId: r.id,
                                          );
                                          ref.read(attendanceGridEditProvider.notifier).clear();
                                          await _refreshAttendanceViews(course.courseId);
                                          if (!context.mounted) return;
                                          messenger.showSnackBar(const SnackBar(content: Text('Marked present.')));
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          messenger.showSnackBar(SnackBar(content: Text(e.toString())));
                                        }
                                      },
                                      child: const Text('Mark Present'),
                                    ),
                                  ),
                                  DataCell(
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () async {
                                        final messenger = ScaffoldMessenger.of(context);
                                        final shouldDelete = await confirmPermanentDelete(r);
                                        if (!shouldDelete) return;
                                        try {
                                          await _attendanceService.deleteUnverifiedRecord(
                                            courseId: course.courseId,
                                            recordId: r.id,
                                          );
                                          ref.invalidate(unverifiedRecordsProvider(course.courseId));
                                          if (!context.mounted) return;
                                          messenger.showSnackBar(
                                            const SnackBar(content: Text('Unverified record deleted permanently.')),
                                          );
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          messenger.showSnackBar(SnackBar(content: Text(e.toString())));
                                        }
                                      },
                                      child: const Text('Ignore'),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedCourseProvider).courseId;
    final coursesAsync = ref.watch(coursesProvider);

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
        child: coursesAsync.when(
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

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: activeCourse.courseId,
                          decoration: const InputDecoration(labelText: 'Select course'),
                          items: courses
                              .map(
                                (c) => DropdownMenuItem<String>(
                                  value: c.courseId,
                                  child: Text(
                                    '${c.courseCode} • ${c.abbreviation} • ${c.courseName}${c.section.isNotEmpty ? ' • ${c.section}' : ''}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            ref.read(selectedCourseProvider.notifier).select(v);
                            ref.read(attendanceGridEditProvider.notifier).clear();
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
                  const SizedBox(height: 12),
                  _viewSwitcher(),
                  const SizedBox(height: 12),
                  Expanded(
                    flex: 7,
                    child: _attendanceSection(
                      context: context,
                      course: activeCourse,
                      sessionsAsync: _activeView == _AttendanceViewType.normal
                          ? ref.watch(normalAttendanceSessionsProvider(activeCourse.courseId))
                          : ref.watch(makeupAttendanceSessionsProvider(activeCourse.courseId)),
                      isMakeup: _activeView == _AttendanceViewType.makeup,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    flex: 3,
                    child: _unverifiedSection(context: context, course: activeCourse),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

