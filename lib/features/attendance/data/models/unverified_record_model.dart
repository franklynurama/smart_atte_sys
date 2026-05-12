class UnverifiedRecordModel {
  final String id;
  final String studentName;
  final String studentId;
  final String date;
  final String time;
  final String rawSessionId;
  final bool isMakeup;
  final bool processed;

  const UnverifiedRecordModel({
    required this.id,
    required this.studentName,
    required this.studentId,
    required this.date,
    required this.time,
    required this.rawSessionId,
    required this.isMakeup,
    required this.processed,
  });

  factory UnverifiedRecordModel.fromMap({
    required String id,
    required Map<String, dynamic> map,
  }) {
    return UnverifiedRecordModel(
      id: id,
      studentName: (map['studentName'] ?? '') as String,
      studentId: (map['studentId'] ?? '') as String,
      date: (map['date'] ?? '') as String,
      time: (map['time'] ?? '') as String,
      rawSessionId: (map['rawSessionId'] ?? '') as String,
      isMakeup: (map['isMakeup'] as bool?) ?? false,
      processed: (map['processed'] as bool?) ?? false,
    );
  }
}
