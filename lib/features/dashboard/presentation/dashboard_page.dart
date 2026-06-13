import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/dashboard_card.dart';
import '../../../routes/app_routes.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../../attendance/presentation/providers/attendance_provider.dart';
import '../../courses/presentation/providers/course_provider.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  int _crossAxisCount(double width) {
    if (width >= 1200) return 4;
    if (width >= 800) return 3;
    if (width >= 520) return 2;
    return 1;
  }

  double _childAspectRatio(double width, int count) {
    if (count == 1) return 1.15;
    if (width >= 800) return 1.05;
    return 0.95;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref.read(authMutationProvider.notifier).logout();
                ref.invalidate(coursesProvider);
                ref.invalidate(courseMutationProvider);
                ref.invalidate(selectedCourseProvider);
                ref.invalidate(attendanceSelectionProvider);
                ref.invalidate(encryptedFileProvider);
                ref.invalidate(attendanceMutationProvider);
                if (!context.mounted) return;
                Navigator.of(context).pushNamedAndRemoveUntil(
                  AppRoutes.login,
                  (route) => false,
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Could not log out: $e')),
                );
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final count = _crossAxisCount(w);
            final ratio = _childAspectRatio(w, count);

            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: w >= 800 ? 32 : 16,
                vertical: 16,
              ),
              child: GridView.count(
                crossAxisCount: count,
                childAspectRatio: ratio,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: [
                  DashboardCard(
                    icon: Icons.add_box_outlined,
                    title: 'Add Courses',
                    description: 'Create courses, upload rosters, manage schedules.',
                    onTap: () => Navigator.of(context).pushNamed(AppRoutes.addCourse),
                  ),
                  DashboardCard(
                    icon: Icons.visibility_outlined,
                    title: 'View Attendance',
                    description: 'Select a course and review attendance.',
                    onTap: () => Navigator.of(context).pushNamed(AppRoutes.viewAttendance),
                  ),
                  DashboardCard(
                    icon: Icons.delete_outline,
                    title: 'Delete Course',
                    description: 'Permanently remove a course and its data.',
                    onTap: () => Navigator.of(context).pushNamed(AppRoutes.deleteCourse),
                  ),
                  DashboardCard(
                    icon: Icons.edit_note_outlined,
                    title: 'Update Attendance',
                    description: 'Upload Raspberry Pi attendance CSV or Excel.',
                    onTap: () => Navigator.of(context).pushNamed(AppRoutes.updateAttendance),
                  ),
                  DashboardCard(
                    icon: Icons.lock_open_outlined,
                    title: 'Decrypt Attendance',
                    description: 'Decrypt encrypted attendance files.',
                    onTap: () => Navigator.of(context).pushNamed(AppRoutes.decryptAttendance),
                  ),
                  DashboardCard(
                    icon: Icons.access_time_filled_outlined,
                    title: 'Makeup Attendance',
                    description: 'Record attendance for makeup sessions.',
                    onTap: () => Navigator.of(context).pushNamed(AppRoutes.makeupAttendance),
                  ),
                  DashboardCard(
                    icon: Icons.person_add_alt_1_outlined,
                    title: 'Add Student',
                    description: 'Add a student manually to a selected course.',
                    onTap: () => Navigator.of(context).pushNamed(AppRoutes.addStudent),
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
