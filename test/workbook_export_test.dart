import 'dart:typed_data';

import 'package:divgain/logic/portfolio_math.dart';
import 'package:divgain/logic/workbook_export.dart';
import 'package:divgain/logic/workbook_import.dart';
import 'package:divgain/models/book.dart';
import 'package:divgain/models/ledger.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('匯出的 Excel 包含記賬、錢包和股票', () {
    final bytes = buildDivGainWorkbook(
      entries: [
        BookEntry(
          id: 2,
          date: DateTime(2026, 10, 2),
          kind: BookKind.expense,
          currency: BookCurrency.hkd,
          category: '飲食',
          amount: 40,
          note: '午餐',
          method: '現金',
        ),
        BookEntry(
          id: 1,
          date: DateTime(2026, 10, 1),
          kind: BookKind.income,
          currency: BookCurrency.hkd,
          category: '薪金',
          amount: 1000,
          note: '',
          method: '現金',
        ),
      ],
      opening: {'現金': 500},
      portfolio: PortfolioData(
        holdings: const [
          Holding(
            id: 1,
            market: Market.hk,
            symbol: '00005',
            name: '滙豐',
            currentPrice: 65,
          ),
        ],
        trades: [
          Trade(
            id: 1,
            holdingId: 1,
            date: DateTime(2026, 1, 2),
            side: TradeSide.buy,
            shares: 1000,
            price: 60,
            fee: 50,
          ),
        ],
        dividends: [
          Dividend(
            id: 1,
            holdingId: 1,
            date: DateTime(2026, 3, 1),
            amount: 2000,
            note: '中期息',
          ),
        ],
      ),
    );

    final excel = Excel.decodeBytes(bytes);
    expect(excel.sheets.keys, containsAll(workbookSheets));
    expect(excel.getDefaultSheet(), '記賬');

    final book = excel['記賬'];
    expect(_text(book, 0, 1), '2026-10-01');
    expect(_text(book, 1, 1), '收入');
    expect(_text(book, 3, 1), '現金');
    expect(_number(book, 4, 1), closeTo(1000, 0.001));
    expect(_text(book, 1, 2), '支出');
    expect(_number(book, 4, 2), closeTo(-40, 0.001));
    expect(_text(book, 5, 2), '午餐');

    final wallet = excel['錢包'];
    expect(_text(wallet, 0, 1), '現金');
    expect(_number(wallet, 1, 1), closeTo(500, 0.001));
    expect(_number(wallet, 3, 1), closeTo(1460, 0.001));

    final stock = excel['股票'];
    expect(_text(stock, 1, 1), '00005');
    expect(_text(stock, 2, 1), '滙豐');
    expect(_text(stock, 3, 1), '持有');
    expect(_number(stock, 11, 1), closeTo(6950, 0.001));

    final trade = excel['買賣'];
    expect(_text(trade, 4, 1), '買入');
    expect(_number(trade, 5, 1), closeTo(1000, 0.001));

    final dividend = excel['股息'];
    expect(_number(dividend, 4, 1), closeTo(2000, 0.001));
    expect(_text(dividend, 5, 1), '中期息');
  });

  test('匯入可以讀回同一份匯出檔', () {
    final bytes = buildDivGainWorkbook(
      entries: [
        BookEntry(
          id: 2,
          date: DateTime(2026, 10, 2),
          kind: BookKind.expense,
          currency: BookCurrency.hkd,
          category: '飲食',
          amount: 40,
          note: '午餐',
          method: '現金',
        ),
        BookEntry(
          id: 1,
          date: DateTime(2026, 10, 1),
          kind: BookKind.income,
          currency: BookCurrency.hkd,
          category: '薪金',
          amount: 1000,
          note: '',
          method: '',
        ),
      ],
      opening: {'現金': 500},
      portfolio: PortfolioData(
        holdings: const [
          Holding(
            id: 1,
            market: Market.hk,
            symbol: '00005',
            name: '滙豐',
            currentPrice: 65,
          ),
        ],
        trades: [
          Trade(
            id: 1,
            holdingId: 1,
            date: DateTime(2026, 1, 2),
            side: TradeSide.buy,
            shares: 1000,
            price: 60,
            fee: 50,
          ),
        ],
        dividends: [
          Dividend(
            id: 1,
            holdingId: 1,
            date: DateTime(2026, 3, 1),
            amount: 2000,
            note: '中期息',
          ),
        ],
      ),
    );

    final imported = readDivGainWorkbook(bytes);
    expect(imported.entries, hasLength(2));
    expect(imported.entries.first.kind, BookKind.income);
    expect(imported.entries.first.method, isEmpty);
    expect(imported.entries.first.amount, closeTo(1000, 0.001));
    expect(imported.entries.last.kind, BookKind.expense);
    expect(imported.entries.last.note, '午餐');
    expect(imported.opening, {'現金': 500});
    expect(imported.stocks.single.holding.symbol, '00005');
    expect(imported.stocks.single.holding.name, '滙豐');
    expect(imported.stocks.single.holding.currentPrice, closeTo(65, 0.001));
    expect(imported.stocks.single.trades.single.shares, closeTo(1000, 0.001));
    expect(imported.stocks.single.trades.single.fee, closeTo(50, 0.001));
    expect(imported.stocks.single.dividends.single.amount, closeTo(2000, 0.001));
    expect(imported.stocks.single.dividends.single.note, '中期息');
  });

  test('不是 DivGain 匯出檔時拒絕匯入', () {
    final excel = Excel.createExcel();
    expect(
      () => readDivGainWorkbook(Uint8List.fromList(excel.encode()!)),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          '這不是 DivGain 的匯出檔',
        ),
      ),
    );
  });
}

String _text(Sheet sheet, int column, int row) {
  final value = sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
      .value;
  expect(value, isA<TextCellValue>());
  return (value! as TextCellValue).value.toString();
}

double _number(Sheet sheet, int column, int row) {
  final value = sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
      .value;
  if (value is DoubleCellValue) return value.value;
  if (value is IntCellValue) return value.value.toDouble();
  fail('第 $row 列第 $column 欄不是數字：$value');
}
