import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/download_bytes.dart';
import '../../data/models/attendance_session_model.dart';
import '../../data/models/unverified_record_model.dart';
import '../../data/services/attendance_service.dart';
import '../../data/services/backend_api_service.dart';
import '../../data/services/file_service.dart';

class AttendanceSelectionState {
  final String? courseId;
  final String? recordKey;
  const AttendanceSelectionState({required this.courseId, required this.recordKey});

  factory AttendanceSelectionState.initial() => const AttendanceSelectionState(courseId: null, recordKey: null);

  AttendanceSelectionState copyWith({String? courseId, String? recordKey}) {
    return AttendanceSelectionState(
      courseId: courseId ?? this.courseId,
      recordKey: recordKey ?? this.recordKey,
    );
  }
}

class AttendanceSelectionNotifier extends StateNotifier<AttendanceSelectionState> {
  AttendanceSelectionNotifier() : super(AttendanceSelectionState.initial());

  void selectCourse(String? courseId) => state = state.copyWith(courseId: courseId, recordKey: null);
  void selectRecordKey(String? recordKey) => state = state.copyWith(recordKey: recordKey);
}

final attendanceSelectionProvider = StateNotifierProvider<AttendanceSelectionNotifier, AttendanceSelectionState>(
  (ref) => AttendanceSelectionNotifier(),
);

class EncryptedFileState {
  final Uint8List? bytes;
  final String? fileName;
  final bool isLoaded;

  const EncryptedFileState({required this.bytes, required this.fileName, required this.isLoaded});

  factory EncryptedFileState.initial() => const EncryptedFileState(bytes: null, fileName: null, isLoaded: false);

  EncryptedFileState copyWith({Uint8List? bytes, String? fileName, bool? isLoaded}) {
    return EncryptedFileState(
      bytes: bytes ?? this.bytes,
      fileName: fileName ?? this.fileName,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

class EncryptedFileNotifier extends StateNotifier<EncryptedFileState> {
  EncryptedFileNotifier() : super(EncryptedFileState.initial());

  void setFile(Uint8List bytes, String? fileName) {
    state = EncryptedFileState(bytes: bytes, fileName: fileName, isLoaded: true);
  }

  void clear() => state = EncryptedFileState.initial();
}

final encryptedFileProvider =
    StateNotifierProvider<EncryptedFileNotifier, EncryptedFileState>((ref) => EncryptedFileNotifier());

class PrivateKeyFileState {
  final Uint8List? bytes;
  final String? fileName;
  final bool isLoaded;

  const PrivateKeyFileState({required this.bytes, required this.fileName, required this.isLoaded});

  factory PrivateKeyFileState.initial() => const PrivateKeyFileState(bytes: null, fileName: null, isLoaded: false);
}

class PrivateKeyFileNotifier extends StateNotifier<PrivateKeyFileState> {
  PrivateKeyFileNotifier() : super(PrivateKeyFileState.initial());

  void setFile(Uint8List bytes, String? fileName) {
    state = PrivateKeyFileState(bytes: bytes, fileName: fileName, isLoaded: true);
  }

  void clear() => state = PrivateKeyFileState.initial();
}

final privateKeyFileProvider =
    StateNotifierProvider<PrivateKeyFileNotifier, PrivateKeyFileState>((ref) => PrivateKeyFileNotifier());

class AttendanceMutationState {
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;
  final String? downloadPath;
  final Map<String, dynamic>? decryptedJson;
  final int? decryptedCount;

  const AttendanceMutationState({
    required this.isLoading,
    required this.errorMessage,
    required this.successMessage,
    required this.downloadPath,
    required this.decryptedJson,
    required this.decryptedCount,
  });

  factory AttendanceMutationState.initial() => const AttendanceMutationState(
        isLoading: false,
        errorMessage: null,
        successMessage: null,
        downloadPath: null,
        decryptedJson: null,
        decryptedCount: null,
      );

  AttendanceMutationState copyWith({
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    String? downloadPath,
    Map<String, dynamic>? decryptedJson,
    int? decryptedCount,
  }) {
    return AttendanceMutationState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      successMessage: successMessage,
      downloadPath: downloadPath,
      decryptedJson: decryptedJson ?? this.decryptedJson,
      decryptedCount: decryptedCount ?? this.decryptedCount,
    );
  }
}

enum DecryptAction { update, download, both }

/// Success copy for [ref.listen] / UI (keep in sync with notifier).
class AttendanceDecryptMessages {
  AttendanceDecryptMessages._();

  static const decryptOk = 'Decryption successful.';
  static const updateOk = 'Attendance updated successfully.';
  static const downloadOk = 'Decrypted file ready.';
  static const bothOk = 'Attendance updated and file generated successfully.';
}

class AttendanceMutationNotifier extends AsyncNotifier<AttendanceMutationState> {
  final FileService _fileService = FileService();
  final BackendApiService _backendApiService = const BackendApiService();
  final AttendanceService _attendanceService = AttendanceService();

  @override
  Future<AttendanceMutationState> build() async {
    return AttendanceMutationState.initial();
  }

  Future<void> updateAttendanceFromCsv({
    required String courseId,
    required String recordKey,
    required Uint8List bytes,
    required String? fileName,
  }) async {
    state = const AsyncValue.data(
      AttendanceMutationState(
        isLoading: true,
        errorMessage: null,
        successMessage: null,
        downloadPath: null,
        decryptedJson: null,
        decryptedCount: null,
      ),
    );
    try {
      final attendedIds = await _fileService.parseAttendedStudentIdsFromFileBytes(
        bytes: bytes,
        fileName: fileName,
      );
      developer.log(
        'Parsed attendance file=$fileName IDs=${attendedIds.length}',
        name: 'AttendanceMutationNotifier',
      );
      await _attendanceService.updateAttendanceRecord(
        courseId: courseId,
        recordKey: recordKey,
        attendedStudentIds: attendedIds,
      );
      state = AsyncValue.data(
        AttendanceMutationState.initial().copyWith(
          successMessage: 'Attendance updated successfully.',
        ),
      );
    } catch (e, st) {
      developer.log(
        'updateAttendanceFromCsv failed',
        name: 'AttendanceMutationNotifier',
        error: e,
        stackTrace: st,
      );
      state = AsyncValue.data(AttendanceMutationState.initial().copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> decryptWithBackend({
    required Uint8List secBytes,
    required String secFileName,
    required Uint8List privateKeyBytes,
    required String privateKeyFileName,
  }) async {
    state = const AsyncValue.data(
      AttendanceMutationState(
        isLoading: true,
        errorMessage: null,
        successMessage: null,
        downloadPath: null,
        decryptedJson: null,
        decryptedCount: null,
      ),
    );
    try {
      final decrypted = await _backendApiService.decrypt(
        secBytes: secBytes,
        secFileName: secFileName,
        privateKeyBytes: privateKeyBytes,
        privateKeyFileName: privateKeyFileName,
      );
      final students = (decrypted['students'] as List<dynamic>? ?? const []);
      state = AsyncValue.data(
        AttendanceMutationState.initial().copyWith(
          decryptedJson: decrypted,
          decryptedCount: students.length,
          successMessage: AttendanceDecryptMessages.decryptOk,
        ),
      );
    } catch (e, st) {
      developer.log(
        'decryptWithBackend failed',
        name: 'AttendanceMutationNotifier',
        error: e,
        stackTrace: st,
      );
      state = AsyncValue.data(AttendanceMutationState.initial().copyWith(errorMessage: e.toString()));
    }
  }

  Future<String?> processDecrypted({
    required String courseId,
    String? recordKey,
    required DecryptAction action,
    required BackendDownloadFormat downloadFormat,
  }) async {
    final decrypted = state.valueOrNull?.decryptedJson;
    if (decrypted == null) {
      state = AsyncValue.data(
        AttendanceMutationState.initial().copyWith(
          errorMessage: 'Decrypt a file first.',
        ),
      );
      return null;
    }

    state = const AsyncValue.data(
      AttendanceMutationState(
        isLoading: true,
        errorMessage: null,
        successMessage: null,
        downloadPath: null,
        decryptedJson: null,
        decryptedCount: null,
      ),
    );
    try {
      final backendAction = switch (action) {
        DecryptAction.update => BackendProcessAction.update,
        DecryptAction.download => BackendProcessAction.download,
        DecryptAction.both => BackendProcessAction.both,
      };
      final result = await _backendApiService.process(
        decryptedJson: decrypted,
        action: backendAction,
        downloadFormat: downloadFormat,
      );

      if (action == DecryptAction.update || action == DecryptAction.both) {
        if (recordKey == null || recordKey.trim().isEmpty) {
          throw StateError('Please select a session first.');
        }
        final attendedStudentIds =
            result.updateRecords.map((e) => (e['student_id'] ?? '').trim()).where((e) => e.isNotEmpty).toList();
        await _attendanceService.updateAttendanceRecord(
          courseId: courseId,
          recordKey: recordKey,
          attendedStudentIds: attendedStudentIds,
        );
      }

      String? path;
      if (action == DecryptAction.download || action == DecryptAction.both) {
        final bytes = result.downloadBytes;
        if (bytes == null) {
          throw StateError('Backend did not return download file.');
        }
        path = await _writeDownloadedBytesToFile(
          bytes,
          fileName: result.downloadFileName ?? 'decrypted_attendance.csv',
        );
      }

      state = AsyncValue.data(
        AttendanceMutationState.initial().copyWith(
          decryptedJson: decrypted,
          decryptedCount: (decrypted['students'] as List<dynamic>? ?? const []).length,
          successMessage: action == DecryptAction.update
              ? AttendanceDecryptMessages.updateOk
              : action == DecryptAction.download
                  ? AttendanceDecryptMessages.downloadOk
                  : AttendanceDecryptMessages.bothOk,
          downloadPath: path,
        ),
      );
      return path;
    } catch (e, st) {
      developer.log(
        'decryptAndAct failed',
        name: 'AttendanceMutationNotifier',
        error: e,
        stackTrace: st,
      );
      state = AsyncValue.data(AttendanceMutationState.initial().copyWith(errorMessage: e.toString()));
      return null;
    }
  }

  void clearFeedback() {
    final current = state.valueOrNull;
    state = AsyncValue.data(
      AttendanceMutationState.initial().copyWith(
        decryptedJson: current?.decryptedJson,
        decryptedCount: current?.decryptedCount,
      ),
    );
  }

  /// Full reset after a completed process action (update / download / both).
  void resetDecryptFlow() {
    state = AsyncValue.data(AttendanceMutationState.initial());
  }

  Future<String> _writeDownloadedBytesToFile(Uint8List bytes, {required String fileName}) async {
    return downloadBytesToDevice(bytes, fileName);
  }
}

final attendanceMutationProvider = AsyncNotifierProvider<AttendanceMutationNotifier, AttendanceMutationState>(
  AttendanceMutationNotifier.new,
);

final normalAttendanceSessionsProvider =
    FutureProvider.family<List<AttendanceSessionModel>, String>((ref, courseId) async {
  return AttendanceService().getNormalAttendanceSessions(courseId);
});

final makeupAttendanceSessionsProvider =
    FutureProvider.family<List<AttendanceSessionModel>, String>((ref, courseId) async {
  return AttendanceService().getMakeupAttendanceSessions(courseId);
});

final unverifiedRecordsProvider =
    FutureProvider.family<List<UnverifiedRecordModel>, String>((ref, courseId) async {
  return AttendanceService().getUnverifiedRecords(courseId);
});

class AttendanceGridEditState {
  final Map<String, Map<String, bool>> normalDraft;
  final Map<String, Map<String, bool>> makeupDraft;

  const AttendanceGridEditState({
    required this.normalDraft,
    required this.makeupDraft,
  });

  factory AttendanceGridEditState.initial() => const AttendanceGridEditState(
        normalDraft: {},
        makeupDraft: {},
      );
}

class AttendanceGridEditNotifier extends StateNotifier<AttendanceGridEditState> {
  AttendanceGridEditNotifier() : super(AttendanceGridEditState.initial());

  void seedIfMissing({
    required bool isMakeup,
    required Map<String, Map<String, bool>> source,
  }) {
    final target = isMakeup ? state.makeupDraft : state.normalDraft;
    if (target.isNotEmpty) return;
    if (isMakeup) {
      state = AttendanceGridEditState(
        normalDraft: state.normalDraft,
        makeupDraft: source,
      );
    } else {
      state = AttendanceGridEditState(
        normalDraft: source,
        makeupDraft: state.makeupDraft,
      );
    }
  }

  void toggle({
    required bool isMakeup,
    required String sessionId,
    required String studentId,
    required bool value,
  }) {
    final target = Map<String, Map<String, bool>>.from(isMakeup ? state.makeupDraft : state.normalDraft);
    final currentSession = Map<String, bool>.from(target[sessionId] ?? const <String, bool>{});
    currentSession[studentId] = value;
    target[sessionId] = currentSession;
    state = isMakeup
        ? AttendanceGridEditState(normalDraft: state.normalDraft, makeupDraft: target)
        : AttendanceGridEditState(normalDraft: target, makeupDraft: state.makeupDraft);
  }

  void clear() => state = AttendanceGridEditState.initial();
}

final attendanceGridEditProvider =
    StateNotifierProvider<AttendanceGridEditNotifier, AttendanceGridEditState>(
  (ref) => AttendanceGridEditNotifier(),
);

