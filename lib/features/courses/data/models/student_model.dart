class StudentModel {
  final String studentName;
  final String studentId;
  final String department;

  const StudentModel({
    required this.studentName,
    required this.studentId,
    required this.department,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'studentName': studentName,
      'studentId': studentId,
      'department': department,
    };
  }

  static StudentModel fromMap(Map<String, dynamic> map) {
    return StudentModel(
      studentName: (map['studentName'] ?? '') as String,
      studentId: (map['studentId'] ?? '') as String,
      department: (map['department'] ?? '') as String,
    );
  }
}

