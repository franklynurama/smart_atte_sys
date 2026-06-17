enum CourseTerm { fall, spring, summer, unknown }

enum CourseStatus { active, archived }

extension CourseTermX on CourseTerm {
  String toFirestore() => name;

  String get displayLabel {
    switch (this) {
      case CourseTerm.fall:
        return 'FALL';
      case CourseTerm.spring:
        return 'SPRING';
      case CourseTerm.summer:
        return 'SUMMER';
      case CourseTerm.unknown:
        return 'LEGACY';
    }
  }
}

extension CourseStatusX on CourseStatus {
  String toFirestore() => name;
}

CourseTerm courseTermFromFirestore(String? raw) {
  switch ((raw ?? '').toLowerCase().trim()) {
    case 'fall':
      return CourseTerm.fall;
    case 'spring':
      return CourseTerm.spring;
    case 'summer':
      return CourseTerm.summer;
    default:
      return CourseTerm.unknown;
  }
}

CourseStatus courseStatusFromFirestore(String? raw) {
  switch ((raw ?? '').toLowerCase().trim()) {
    case 'archived':
      return CourseStatus.archived;
    case 'active':
    default:
      return CourseStatus.active;
  }
}
