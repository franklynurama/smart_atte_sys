import 'package:flutter/material.dart';

import '../../../../core/widgets/dashboard_card.dart';
import '../../../../routes/app_routes.dart';
import '../models/attendance_view_mode.dart';

class AttendanceModePage extends StatelessWidget {
  final String courseId;

  const AttendanceModePage({super.key, required this.courseId});

  int _crossAxisCount(double width) {
    if (width >= 1200) return 3;
    if (width >= 800) return 3;
    if (width >= 520) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance View')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final count = _crossAxisCount(w);
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: w >= 800 ? 32 : 16, vertical: 16),
              child: GridView.count(
                crossAxisCount: count,
                childAspectRatio: w >= 800 ? 1.05 : 0.95,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: [
                  for (final mode in AttendanceViewMode.values)
                    DashboardCard(
                      icon: mode.icon,
                      title: mode.title,
                      description: mode.description,
                      onTap: () => Navigator.of(context).pushNamed(
                        AppRoutes.attendanceGrid,
                        arguments: {'courseId': courseId, 'mode': mode.name},
                      ),
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
