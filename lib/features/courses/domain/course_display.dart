import '../data/models/course_model.dart';
import 'course_term.dart';

String courseTermYearSuffix(CourseModel c) {
  if (c.term == CourseTerm.unknown || c.academicYearLabel.trim().isEmpty) {
    return '• LEGACY';
  }
  return '• ${c.term.displayLabel} ${c.academicYearLabel}';
}

String courseDropdownLabel(CourseModel c, {bool includeSection = true}) {
  final section = includeSection && c.section.isNotEmpty ? ' • ${c.section}' : '';
  return '${c.courseCode} • ${c.abbreviation} • ${c.courseName}$section ${courseTermYearSuffix(c)}';
}

String courseExportPrefix(CourseModel c) {
  if (c.term == CourseTerm.unknown || c.academicYearLabel.trim().isEmpty) {
    return '${c.courseCode}_LEGACY';
  }
  final year = c.academicYearLabel.replaceAll('/', '-');
  return '${c.courseCode}_${c.term.name.toUpperCase()}_$year';
}
