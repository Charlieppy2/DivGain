import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models/book.dart';
import '../models/ledger.dart';
import 'book_math.dart';
import 'portfolio_math.dart';

const workbookSheets = ['記賬', '錢包', '股票', '買賣', '股息'];

/// One workbook covering the book, wallets, and stock ledger.
Uint8List buildDivGainWorkbook({
  required List<BookEntry> entries,
  required Map<String, double> opening,
  required PortfolioData portfolio,
  List<String>? methods,
}) {
  final excel = Excel.createExcel();
  _bookSheet(excel, entries);
  _walletSheet(excel, entries, opening, methods);
  _stockSheet(excel, portfolio);
  _tradeSheet(excel, portfolio);
  _dividendSheet(excel, portfolio);
  excel.setDefaultSheet('記賬');
  excel.delete('Sheet1');
  final bytes = excel.encode();
  if (bytes == null) {
    throw StateError('匯出失敗');
  }
  return Uint8List.fromList(bytes);
}

void _bookSheet(Excel excel, List<BookEntry> entries) {
  final sheet = excel['記賬'];
  sheet.appendRow([
    TextCellValue('日期'),
    TextCellValue('類型'),
    TextCellValue('分類'),
    TextCellValue('錢包'),
    TextCellValue('金額'),
    TextCellValue('備註'),
  ]);
  final ordered = [...entries]..sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    return a.id.compareTo(b.id);
  });
  for (final entry in ordered) {
    if (entry.currency != BookCurrency.hkd) continue;
    final signed = entry.kind == BookKind.expense ? -entry.amount : entry.amount;
    sheet.appendRow([
      TextCellValue(storeDate(entry.date)),
      TextCellValue(entry.kind.label),
      TextCellValue(entry.category),
      TextCellValue(entry.method.trim().isEmpty ? '未填' : entry.method.trim()),
      DoubleCellValue(signed),
      TextCellValue(entry.note),
    ]);
  }
}

void _walletSheet(
  Excel excel,
  List<BookEntry> entries,
  Map<String, double> opening,
  List<String>? methods,
) {
  final sheet = excel['錢包'];
  sheet.appendRow([
    TextCellValue('錢包'),
    TextCellValue('原有資金'),
    TextCellValue('記賬結餘'),
    TextCellValue('總結餘'),
  ]);
  for (final line in walletBalances(entries, opening: opening, methods: methods)) {
    if (line.method == '未填' && line.balance.abs() <= 0.004) continue;
    sheet.appendRow([
      TextCellValue(line.method),
      DoubleCellValue(line.opening),
      DoubleCellValue(line.balance - line.opening),
      DoubleCellValue(line.balance),
    ]);
  }
}

void _stockSheet(Excel excel, PortfolioData portfolio) {
  final sheet = excel['股票'];
  sheet.appendRow([
    TextCellValue('市場'),
    TextCellValue('代碼'),
    TextCellValue('名稱'),
    TextCellValue('狀態'),
    TextCellValue('股數'),
    TextCellValue('平均成本'),
    TextCellValue('現價'),
    TextCellValue('市值'),
    TextCellValue('已實現'),
    TextCellValue('未實現'),
    TextCellValue('股息'),
    TextCellValue('總收益'),
  ]);
  for (final summary in portfolio.summaries) {
    final soldOut = isSoldOut(summary, portfolio.trades);
    sheet.appendRow([
      TextCellValue(summary.holding.market.label),
      TextCellValue(summary.holding.symbol),
      TextCellValue(summary.holding.name),
      TextCellValue(soldOut ? '已清倉' : '持有'),
      DoubleCellValue(summary.shares),
      DoubleCellValue(summary.averageCost),
      DoubleCellValue(summary.holding.currentPrice),
      DoubleCellValue(summary.marketValue),
      DoubleCellValue(summary.realizedPnl),
      DoubleCellValue(summary.unrealizedPnl),
      DoubleCellValue(summary.dividends),
      DoubleCellValue(summary.totalGain),
    ]);
  }
}

void _tradeSheet(Excel excel, PortfolioData portfolio) {
  final sheet = excel['買賣'];
  sheet.appendRow([
    TextCellValue('日期'),
    TextCellValue('市場'),
    TextCellValue('代碼'),
    TextCellValue('名稱'),
    TextCellValue('方向'),
    TextCellValue('股數'),
    TextCellValue('單價'),
    TextCellValue('費用'),
  ]);
  final trades = [...portfolio.trades]..sort(compareTrades);
  for (final trade in trades) {
    final holding = _holding(portfolio, trade.holdingId);
    sheet.appendRow([
      TextCellValue(storeDate(trade.date)),
      TextCellValue(holding?.market.label ?? ''),
      TextCellValue(holding?.symbol ?? ''),
      TextCellValue(holding?.name ?? ''),
      TextCellValue(trade.side.label),
      DoubleCellValue(trade.shares),
      DoubleCellValue(trade.price),
      DoubleCellValue(trade.fee),
    ]);
  }
}

void _dividendSheet(Excel excel, PortfolioData portfolio) {
  final sheet = excel['股息'];
  sheet.appendRow([
    TextCellValue('日期'),
    TextCellValue('市場'),
    TextCellValue('代碼'),
    TextCellValue('名稱'),
    TextCellValue('金額'),
    TextCellValue('備註'),
  ]);
  final dividends = [...portfolio.dividends]..sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    return a.id.compareTo(b.id);
  });
  for (final dividend in dividends) {
    final holding = _holding(portfolio, dividend.holdingId);
    sheet.appendRow([
      TextCellValue(storeDate(dividend.date)),
      TextCellValue(holding?.market.label ?? ''),
      TextCellValue(holding?.symbol ?? ''),
      TextCellValue(holding?.name ?? ''),
      DoubleCellValue(dividend.amount),
      TextCellValue(dividend.note),
    ]);
  }
}

Holding? _holding(PortfolioData portfolio, int id) {
  for (final holding in portfolio.holdings) {
    if (holding.id == id) return holding;
  }
  return null;
}
