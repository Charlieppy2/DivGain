import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/workbook_export.dart';
import '../logic/workbook_import.dart';
import '../models/ledger.dart';
import '../state/book_controller.dart';
import '../state/portfolio_controller.dart';
import '../widgets/dialogs.dart';
import 'save_export_file.dart';

Future<void> exportDivGain(BuildContext context, WidgetRef ref) async {
  final portfolio = ref.read(portfolioProvider).asData?.value;
  final entries = ref.read(bookProvider).asData?.value;
  final opening = ref.read(walletFundsProvider).asData?.value;
  final labels = ref.read(bookLabelsProvider).asData?.value;
  if (portfolio == null || entries == null || opening == null || labels == null) {
    showMessage(context, '資料還在讀取');
    return;
  }
  try {
    final bytes = buildDivGainWorkbook(
      entries: entries,
      opening: opening,
      portfolio: portfolio,
      methods: labels.methods,
    );
    final filename = 'DivGain-${storeDate(DateTime.now())}.xlsx';
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await saveExportFile(bytes, filename, sharePositionOrigin: origin);
    if (context.mounted) showMessage(context, '已匯出 $filename');
  } catch (_) {
    if (context.mounted) showMessage(context, '匯出失敗');
  }
}

Future<void> importDivGain(BuildContext context, WidgetRef ref) async {
  PlatformFile? file;
  try {
    file = await FilePicker.pickFile(
      dialogTitle: '選擇 DivGain 匯出檔',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
  } catch (_) {
    if (context.mounted) showMessage(context, '匯入失敗');
    return;
  }
  if (file == null || !context.mounted) return;

  late final ImportedWorkbook imported;
  try {
    imported = readDivGainWorkbook(await file.readAsBytes());
  } on FormatException catch (error) {
    if (context.mounted) showMessage(context, error.message);
    return;
  } catch (_) {
    if (context.mounted) showMessage(context, '這不是 DivGain 的匯出檔');
    return;
  }
  if (!context.mounted) return;

  final confirmed = await confirmReplace(
    context,
    '記賬 ${imported.entries.length} 筆、錢包 ${imported.opening.length} 個、股票 ${imported.stocks.length} 隻。現有資料會被這份檔案取代。',
  );
  if (!confirmed || !context.mounted) return;

  try {
    await ref.read(databaseProvider).replaceWithImport(
      entries: imported.entries,
      opening: imported.opening,
      stocks: imported.stocks,
    );
    ref.invalidate(bookProvider);
    ref.invalidate(walletFundsProvider);
    ref.invalidate(portfolioProvider);
    if (context.mounted) showMessage(context, '已匯入');
  } catch (_) {
    if (context.mounted) showMessage(context, '匯入失敗');
  }
}
