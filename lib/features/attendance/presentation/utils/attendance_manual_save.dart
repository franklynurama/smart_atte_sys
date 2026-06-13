import '../../../courses/data/models/student_model.dart';
import '../../domain/attendance_merge.dart';

bool _sparseMapsEqual(Map<String, bool> a, Map<String, bool> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

/// Build sparse manual maps per session from draft overlay. Only changed sessions returned.
Map<String, Map<String, bool>> buildSparseManualMapsForSave({
  required List<StudentModel> students,
  required Map<String, Map<String, bool>> rawBySession,
  required Map<String, Map<String, bool>> manualBySession,
  required Map<String, Map<String, bool>> draft,
}) {
  final result = <String, Map<String, bool>>{};
  final sessionIds = <String>{...rawBySession.keys, ...manualBySession.keys, ...draft.keys};
  for (final sessionId in sessionIds) {
    final raw = rawBySession[sessionId] ?? const <String, bool>{};
    final storedManual = manualBySession[sessionId] ?? const <String, bool>{};
    final draftSession = draft[sessionId];
    if (draftSession == null && storedManual.isEmpty) continue;

    final sparse = <String, bool>{};
    for (final student in students) {
      final sid = student.studentId;
      final displayed = draftSession?[sid] ?? adjustmentsDisplay(storedManual, raw, sid);
      final rawVal = raw[sid] ?? false;
      if (displayed != rawVal) {
        sparse[sid] = displayed;
      }
    }
    if (!_sparseMapsEqual(storedManual, sparse)) {
      result[sessionId] = sparse;
    }
  }
  return result;
}
