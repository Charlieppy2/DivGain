import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models/book.dart';
import '../models/ledger.dart';
import 'workbook_export.dart';

class ImportedStock {
  const ImportedStock({
    required this.holding,
    required this.trades,
    required this.dividends,
  });

  final Holding holding;
  final List<Trade> trades;
  final List<Dividend> dividends;
}

class ImportedWorkbook {
  const ImportedWorkbook({
    required this.entries,
    required this.opening,
    required this.stocks,
  });

  final List<BookEntry> entries;
  final Map<String, double> opening;
  final List<ImportedStock> stocks;
}

/// Reads a workbook produced by [buildDivGainWorkbook].
ImportedWorkbook readDivGainWorkbook(Uint8List bytes) {
  final excel = Excel.decodeBytes(bytes);
  for (final name in workbookSheets) {
    if (!excel.sheets.containsKey(name)) {
      throw const FormatException('這不是 DivGain 的匯出檔');
    }
  }
  final stocks = _readStocks(excel);
  return ImportedWorkbook(
    entries: _readEntries(excel['記賬']),
    opening: _readOpening(excel['錢包']),
    stocks: stocks,
  );
}

List<BookEntry> _readEntries(Sheet sheet) {
  final entries = <BookEntry>[];
  final rows = sheet.rows;
  for (var index = 1; index < rows.length; index++) {
    if (_blank(rows[index])) continue;
    final rowNumber = index + 1;
    final dateText = _text(rows[index], 0);
    final kindText = _text(rows[index], 1);
    final category = _text(rows[index], 2);
    final methodText = _text(rows[index], 3);
    final signed = _number(rows[index], 4);
    if (dateText.isEmpty || signed == null) {
      throw FormatException('第 $rowNumber 行記賬資料不完整');
    }
    if (category.isEmpty) {
      throw FormatException('第 $rowNumber 行沒有分類');
    }
    final kind = switch (kindText) {
      '收入' => BookKind.income,
      '支出' => BookKind.expense,
      _ => signed < 0 ? BookKind.expense : BookKind.income,
    };
    final amount = signed.abs();
    if (amount <= 0.004) continue;
    DateTime date;
    try {
      date = parseDate(dateText);
    } on FormatException {
      throw FormatException('第 $rowNumber 行日期不正確');
    }
    entries.add(
      BookEntry(
        id: 0,
        date: date,
        kind: kind,
        currency: BookCurrency.hkd,
        category: category,
        amount: amount,
        note: _text(rows[index], 5),
        method: methodText == '未填' ? '' : methodText,
      ),
    );
  }
  return entries;
}

Map<String, double> _readOpening(Sheet sheet) {
  final opening = <String, double>{};
  final rows = sheet.rows;
  for (var index = 1; index < rows.length; index++) {
    if (_blank(rows[index])) continue;
    final method = _text(rows[index], 0);
    final amount = _number(rows[index], 1) ?? 0;
    if (method.isEmpty || method == '未填' || amount.abs() <= 0.004) continue;
    opening[method] = amount;
  }
  return opening;
}

List<ImportedStock> _readStocks(Excel excel) {
  final byKey = <String, _StockBuilder>{};
  _StockBuilder builderFor(String marketText, String symbolText, String name) {
    final market = _market(marketText);
    final symbol = normalizeSymbol(market, symbolText);
    if (symbol.isEmpty) {
      throw const FormatException('股票代碼是空的');
    }
    final key = '${market.storageCode}|$symbol';
    return byKey.putIfAbsent(
      key,
      () => _StockBuilder(market: market, symbol: symbol, name: name),
    );
  }

  final stockRows = excel['股票'].rows;
  for (var index = 1; index < stockRows.length; index++) {
    if (_blank(stockRows[index])) continue;
    final marketText = _text(stockRows[index], 0);
    final symbolText = _text(stockRows[index], 1);
    if (marketText.isEmpty && symbolText.isEmpty) continue;
    final builder = builderFor(marketText, symbolText, _text(stockRows[index], 2));
    final price = _number(stockRows[index], 6);
    if (price != null) builder.price = price;
    final name = _text(stockRows[index], 2);
    if (name.isNotEmpty) builder.name = name;
  }

  final tradeRows = excel['買賣'].rows;
  for (var index = 1; index < tradeRows.length; index++) {
    if (_blank(tradeRows[index])) continue;
    final rowNumber = index + 1;
    final dateText = _text(tradeRows[index], 0);
    final shares = _number(tradeRows[index], 5);
    final price = _number(tradeRows[index], 6);
    final sideText = _text(tradeRows[index], 4);
    if (dateText.isEmpty || shares == null || price == null || shares <= 0) {
      throw FormatException('第 $rowNumber 行買賣資料不完整');
    }
    final side = switch (sideText) {
      '買入' => TradeSide.buy,
      '賣出' => TradeSide.sell,
      _ => throw FormatException('第 $rowNumber 行買賣方向不正確'),
    };
    DateTime date;
    try {
      date = parseDate(dateText);
    } on FormatException {
      throw FormatException('第 $rowNumber 行日期不正確');
    }
    final builder = builderFor(
      _text(tradeRows[index], 1),
      _text(tradeRows[index], 2),
      _text(tradeRows[index], 3),
    );
    builder.trades.add(
      Trade(
        id: 0,
        holdingId: 0,
        date: date,
        side: side,
        shares: shares,
        price: price,
        fee: _number(tradeRows[index], 7) ?? 0,
      ),
    );
  }

  final dividendRows = excel['股息'].rows;
  for (var index = 1; index < dividendRows.length; index++) {
    if (_blank(dividendRows[index])) continue;
    final rowNumber = index + 1;
    final dateText = _text(dividendRows[index], 0);
    final amount = _number(dividendRows[index], 4);
    if (dateText.isEmpty || amount == null) {
      throw FormatException('第 $rowNumber 行股息資料不完整');
    }
    DateTime date;
    try {
      date = parseDate(dateText);
    } on FormatException {
      throw FormatException('第 $rowNumber 行日期不正確');
    }
    final builder = builderFor(
      _text(dividendRows[index], 1),
      _text(dividendRows[index], 2),
      _text(dividendRows[index], 3),
    );
    builder.dividends.add(
      Dividend(
        id: 0,
        holdingId: 0,
        date: date,
        amount: amount,
        note: _text(dividendRows[index], 5),
      ),
    );
  }

  final keys = byKey.keys.toList()..sort();
  return [
    for (final key in keys) byKey[key]!.build(),
  ];
}

class _StockBuilder {
  _StockBuilder({
    required this.market,
    required this.symbol,
    required String name,
  }) : name = name;

  final Market market;
  final String symbol;
  String name;
  double price = 0;
  final trades = <Trade>[];
  final dividends = <Dividend>[];

  ImportedStock build() {
    return ImportedStock(
      holding: Holding(
        id: 0,
        market: market,
        symbol: symbol,
        name: name,
        currentPrice: price,
      ),
      trades: trades,
      dividends: dividends,
    );
  }
}

Market _market(String label) {
  return switch (label.trim()) {
    '港股' => Market.hk,
    '美股' => Market.us,
    _ => throw FormatException('未知市場：$label'),
  };
}

bool _blank(List<Data?> row) {
  for (final cell in row) {
    final value = cell?.value;
    if (value == null) continue;
    if (value is TextCellValue && value.value.toString().trim().isEmpty) {
      continue;
    }
    return false;
  }
  return true;
}

String _text(List<Data?> row, int column) {
  if (column >= row.length) return '';
  final value = row[column]?.value;
  if (value is TextCellValue) return value.value.toString().trim();
  if (value is IntCellValue) return value.value.toString();
  if (value is DoubleCellValue) {
    final number = value.value;
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number.toString();
  }
  return '';
}

double? _number(List<Data?> row, int column) {
  if (column >= row.length) return null;
  final value = row[column]?.value;
  if (value is DoubleCellValue) return value.value;
  if (value is IntCellValue) return value.value.toDouble();
  if (value is TextCellValue) {
    return double.tryParse(value.value.toString().trim().replaceAll(',', ''));
  }
  return null;
}
