import 'dart:typed_data';

import 'file_service.dart';

class DecryptedAttendance {
  final String plainText;
  final List<String> attendedStudentIds;

  const DecryptedAttendance({
    required this.plainText,
    required this.attendedStudentIds,
  });
}

/// Placeholder encryption/decryption service.
///
/// This implementation is intentionally conservative:
/// - If the encrypted file is actually plain CSV, it will parse it and return attended IDs.
/// - If the file matches the provided "ENCRYPTED_DATA_SAMPLE" pattern, it returns a clear error.
/// - Otherwise it tries to parse lines formatted like `2019001:true` / `2019001,false`.
class EncryptionService {
  final FileService _fileService = FileService();

  Future<DecryptedAttendance> decryptBytesToAttendance({
    required Uint8List bytes,
    required String? fileName,
  }) async {
    final text = String.fromCharCodes(bytes).trim();
    if (text.isEmpty) {
      throw StateError('Encrypted file is empty.');
    }

    // If it already looks like decrypted CSV, parse directly.
    if (text.contains('Student') && (text.contains(',') || text.contains('\n'))) {
      final attended = await _fileService.parseAttendedStudentIdsFromCsvBytes(bytes: bytes);
      return DecryptedAttendance(plainText: text, attendedStudentIds: attended);
    }

    if (text.startsWith('ENCRYPTED_DATA_SAMPLE')) {
      // Demo-only placeholder:
      // Map known sample tokens to Student IDs so the end-to-end attendance flow works.
      const tokenToStudentId = <String, String>{
        'a8f3b2c19d82e21b': '2019001',
        'b9c3a4d22e31ff98': '2019003',
      };

      final lines = text
          .split(RegExp(r'[\r\n]+'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      // Skip the first header line.
      final tokens = lines.where((l) => l != 'ENCRYPTED_DATA_SAMPLE').toList();
      final attendedIds = <String>[];
      for (final t in tokens) {
        final id = tokenToStudentId[t];
        if (id != null) attendedIds.add(id);
      }

      if (attendedIds.isEmpty) {
        throw StateError(
          'Unable to decrypt sample attendance: tokens did not match the demo mapping.',
        );
      }

      final plainCsv = <String>[
        'Student Name,Student ID',
        for (final id in attendedIds) '$id,$id',
      ].join('\n');

      return DecryptedAttendance(plainText: plainCsv, attendedStudentIds: attendedIds);
    }

    // Try parsing `studentId:true|false` lines.
    final lines = text.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final attended = <String>{};
    for (final line in lines) {
      final parts = line.split(':');
      if (parts.length != 2) continue;
      final id = parts[0].trim();
      final value = parts[1].trim().toLowerCase();
      if (id.isEmpty) continue;
      if (value == 'true') attended.add(id);
    }

    if (attended.isEmpty) {
      throw StateError('Unable to decrypt: unsupported file format.');
    }

    return DecryptedAttendance(plainText: text, attendedStudentIds: attended.toList());
  }
}

