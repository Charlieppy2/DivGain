import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'save_export_file_io.dart'
    if (dart.library.js_interop) 'save_export_file_web.dart'
    as impl;

Future<void> saveExportFile(
  Uint8List bytes,
  String filename, {
  Rect? sharePositionOrigin,
}) {
  return impl.saveExportFile(
    bytes,
    filename,
    sharePositionOrigin: sharePositionOrigin,
  );
}
