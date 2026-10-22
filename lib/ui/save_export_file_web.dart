import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart';

Future<void> saveExportFile(
  Uint8List bytes,
  String filename, {
  Rect? sharePositionOrigin,
}) async {
  final blob = Blob(
    [bytes.toJS].toJS,
    BlobPropertyBag(
      type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ),
  );
  final url = URL.createObjectURL(blob);
  final anchor = HTMLAnchorElement()
    ..href = url
    ..download = filename;
  document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}
