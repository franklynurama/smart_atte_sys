import 'dart:typed_data';

import 'download_bytes_stub.dart'
    if (dart.library.html) 'download_bytes_web.dart'
    if (dart.library.io) 'download_bytes_io.dart';

/// Saves [bytes] for the user: filesystem path on IO, browser download on web.
Future<String> downloadBytesToDevice(Uint8List bytes, String fileName) =>
    downloadBytesToDeviceImpl(bytes, fileName);
