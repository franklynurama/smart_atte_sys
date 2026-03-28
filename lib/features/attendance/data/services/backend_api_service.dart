import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

enum BackendProcessAction { update, download, both }
enum BackendDownloadFormat { csv, xlsx }

class BackendProcessResult {
  final List<Map<String, String>> updateRecords;
  final Uint8List? downloadBytes;
  final String? downloadFileName;

  const BackendProcessResult({
    required this.updateRecords,
    this.downloadBytes,
    this.downloadFileName,
  });
}

class BackendApiService {
  // For emulator/device in local dev, update this base URL if needed.
  final String baseUrl;

  const BackendApiService({
    this.baseUrl = 'http://127.0.0.1:8000',
  });

  Future<Map<String, dynamic>> decrypt({
    required Uint8List secBytes,
    required String secFileName,
    required Uint8List privateKeyBytes,
    required String privateKeyFileName,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/decrypt'))
      ..files.add(
        http.MultipartFile.fromBytes(
          'sec_file',
          secBytes,
          filename: secFileName,
        ),
      )
      ..files.add(
        http.MultipartFile.fromBytes(
          'private_key_file',
          privateKeyBytes,
          filename: privateKeyFileName,
        ),
      );

    final streamed = await req.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_extractError(response.body, fallback: 'Decrypt request failed.'));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final decrypted = data['decrypted_json'];
    if (decrypted is! Map<String, dynamic>) {
      throw StateError('Backend returned invalid decrypted payload.');
    }
    return decrypted;
  }

  Future<BackendProcessResult> process({
    required Map<String, dynamic> decryptedJson,
    required BackendProcessAction action,
    required BackendDownloadFormat downloadFormat,
  }) async {
    final actionStr = switch (action) {
      BackendProcessAction.update => 'update',
      BackendProcessAction.download => 'download',
      BackendProcessAction.both => 'both',
    };
    final formatStr = switch (downloadFormat) {
      BackendDownloadFormat.csv => 'csv',
      BackendDownloadFormat.xlsx => 'xlsx',
    };

    final res = await http.post(
      Uri.parse('$baseUrl/process'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'decrypted_json': decryptedJson,
        'action': actionStr,
        'download_format': formatStr,
      }),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError(_extractError(res.body, fallback: 'Process request failed.'));
    }

    if (action == BackendProcessAction.download) {
      final fileName = _fileNameFromDisposition(res.headers['content-disposition']) ??
          (downloadFormat == BackendDownloadFormat.csv
              ? 'decrypted_attendance.csv'
              : 'decrypted_attendance.xlsx');
      return BackendProcessResult(
        updateRecords: const [],
        downloadBytes: res.bodyBytes,
        downloadFileName: fileName,
      );
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final updateRaw = (data['update_records'] as List<dynamic>? ?? const []);
    final updateRecords = updateRaw
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (e) => <String, String>{
            'student_id': (e['student_id'] ?? '').toString(),
            'student_name': (e['student_name'] ?? '').toString(),
          },
        )
        .toList();

    if (action == BackendProcessAction.both) {
      final dl = data['download'] as Map<String, dynamic>?;
      final b64 = dl?['content_base64'] as String?;
      if (b64 == null) {
        throw StateError('Backend did not return download payload for "both".');
      }
      return BackendProcessResult(
        updateRecords: updateRecords,
        downloadBytes: base64Decode(b64),
        downloadFileName: (dl?['file_name'] as String?) ?? 'decrypted_attendance.csv',
      );
    }

    return BackendProcessResult(updateRecords: updateRecords);
  }

  String _extractError(String body, {required String fallback}) {
    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) {
        final detail = data['detail'];
        if (detail != null) return detail.toString();
      }
    } catch (_) {}
    return fallback;
  }

  String? _fileNameFromDisposition(String? disposition) {
    if (disposition == null) return null;
    final match = RegExp(r'filename="([^"]+)"').firstMatch(disposition);
    return match?.group(1);
  }
}
