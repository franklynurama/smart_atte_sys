import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String> downloadBytesToDeviceImpl(Uint8List bytes, String fileName) async {
  final dir = await getTemporaryDirectory();
  final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final outPath = '${dir.path}/$safeName';
  await File(outPath).writeAsBytes(bytes);
  return outPath;
}
