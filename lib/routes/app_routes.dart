import 'package:flutter/material.dart';

import '../features/auth/presentation/pages/login_page.dart';
import '../features/auth/presentation/pages/signup_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/courses/presentation/pages/add_course_page.dart';
import '../features/courses/presentation/pages/view_courses_page.dart';
import '../features/courses/presentation/pages/course_detail_page.dart';
import '../features/attendance/presentation/pages/update_attendance_page.dart';
import '../features/attendance/presentation/pages/decrypt_attendance_page.dart';

class AppRoutes {
  static const String login = '/login';
  static const String signup = '/signup';
  static const String dashboard = '/dashboard';
  static const String addCourse = '/courses/add';
  static const String viewCourses = '/courses/view';
  static const String courseDetail = '/courses/detail';
  static const String updateAttendance = '/attendance/update';
  static const String decryptAttendance = '/attendance/decrypt';

  static RouteFactory router = (settings) {
    switch (settings.name) {
      case login:
        return MaterialPageRoute(builder: (_) => const LoginPage());
      case signup:
        return MaterialPageRoute(builder: (_) => const SignupPage());
      case dashboard:
        return MaterialPageRoute(builder: (_) => const DashboardPage());
      case addCourse:
        return MaterialPageRoute(builder: (_) => const AddCoursePage());
      case viewCourses:
        return MaterialPageRoute(builder: (_) => const ViewCoursesPage());
      case courseDetail:
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        final courseId = args['courseId'] as String?;
        if (courseId == null) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Missing courseId argument')),
            ),
          );
        }
        return MaterialPageRoute(
          builder: (_) => CourseDetailPage(courseId: courseId),
        );
      case updateAttendance:
        return MaterialPageRoute(builder: (_) => const UpdateAttendancePage());
      case decryptAttendance:
        return MaterialPageRoute(builder: (_) => const DecryptAttendancePage());
      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('Route not found')),
          ),
        );
    }
  };
}

