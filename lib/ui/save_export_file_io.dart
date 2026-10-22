import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

Future<void> saveExportFile(
  Uint8List bytes,
  String filename, {
  Rect? sharePositionOrigin,
}) {
  return SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          bytes,
          name: filename,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
      fileNameOverrides: [filename],
      subject: filename,
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
}
