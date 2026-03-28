import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<String> downloadBytesToDeviceImpl(Uint8List bytes, String fileName) async {
  final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final blob = web.Blob([bytes.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = safeName
    ..style.display = 'none';

  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);

  return 'Browser download: $safeName';
}
