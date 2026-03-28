import 'dart:typed_data';
import 'dart:convert';

import 'package:csv/csv.dart';

/// CSV parsing helpers used by courses + attendance update.
class CsvParser {
  static Future<List<List<String>>> parseCsvBytes(Uint8List bytes) async {
    final content = bytesToString(bytes);
    final rows = const CsvToListConverter().convert(content, eol: '\n');
    return rows
        .map((row) => row.map((cell) => cell.toString().trim()).toList())
        .toList();
  }

  static String bytesToString(Uint8List bytes) {
    return utf8.decode(bytes, allowMalformed: true);
  }
}

