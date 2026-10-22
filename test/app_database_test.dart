import 'package:divgain/data/app_database.dart';
import 'package:divgain/logic/portfolio_math.dart';
import 'package:divgain/logic/workbook_import.dart';
import 'package:divgain/models/book.dart';
import 'package:divgain/models/ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('港股買賣和股息可以存進資料庫，刪除股票時一併清掉', () async {
    final database = await AppDatabase.openInMemory();
    addTearDown(database.close);

    final holdingId = await database.insertHolding(
      const Holding(
        id: 0,
        market: Market.hk,
        symbol: '00005',
        name: '滙豐',
        currentPrice: 65,
      ),
    );
    await database.insertTrade(
      Trade(
        id: 0,
        holdingId: holdingId,
        date: DateTime(2026, 1, 2),
        side: TradeSide.buy,
        shares: 1000,
        price: 60,
        fee: 50,
      ),
    );
    await database.insertDividend(
      Dividend(
        id: 0,
        holdingId: holdingId,
        date: DateTime(2026, 3, 1),
        amount: 2000,
        note: '中期息',
      ),
    );

    final holdings = await database.getHoldings();
    final trades = await database.getTrades();
    final dividends = await database.getDividends();
    final summary = summarizeHolding(
      holding: holdings.single,
      trades: trades,
      dividends: dividends,
    );

    expect(holdings.single.symbol, '00005');
    expect(summary.totalGain, closeTo(6950, 0.001));
    expect(dividends.single.note, '中期息');

    await database.deleteHolding(holdingId);
    expect(await database.getHoldings(), isEmpty);
    expect(await database.getTrades(), isEmpty);
    expect(await database.getDividends(), isEmpty);
  });

  test('記賬可以新增、修改和刪除，而且不影響股票', () async {
    final database = await AppDatabase.openInMemory();
    addTearDown(database.close);

    final id = await database.insertBookEntry(
      BookEntry(
        id: 0,
        date: DateTime(2026, 10, 22),
        kind: BookKind.expense,
        currency: BookCurrency.hkd,
        category: '飲食',
        amount: 48,
        note: '午餐',
        method: '現金',
      ),
    );
    await database.updateBookEntry(
      BookEntry(
        id: id,
        date: DateTime(2026, 10, 22),
        kind: BookKind.expense,
        currency: BookCurrency.hkd,
        category: '飲食',
        amount: 52,
        note: '午餐',
        method: 'AlipayHK',
      ),
    );

    final entries = await database.getBookEntries();
    expect(entries.single.amount, 52);
    expect(entries.single.note, '午餐');
    expect(entries.single.method, 'AlipayHK');
    expect(await database.getHoldings(), isEmpty);

    await database.deleteBookEntry(id);
    expect(await database.getBookEntries(), isEmpty);

    await database.setWalletFund('現金', 800);
    expect(await database.getWalletFunds(), {'現金': 800});
    await database.setWalletFund('現金', 0);
    expect(await database.getWalletFunds(), isEmpty);
  });

  test('匯入會整份取代記賬、錢包和股票', () async {
    final database = await AppDatabase.openInMemory();
    addTearDown(database.close);
    await database.insertHolding(
      const Holding(
        id: 0,
        market: Market.us,
        symbol: 'AAPL',
        name: '舊股票',
        currentPrice: 1,
      ),
    );
    await database.insertBookEntry(
      BookEntry(
        id: 0,
        date: DateTime(2026, 1, 1),
        kind: BookKind.expense,
        currency: BookCurrency.hkd,
        category: '其他',
        amount: 9,
        note: '舊資料',
        method: '現金',
      ),
    );
    await database.setWalletFund('現金', 1);

    await database.replaceWithImport(
      entries: [
        BookEntry(
          id: 0,
          date: DateTime(2026, 10, 2),
          kind: BookKind.income,
          currency: BookCurrency.hkd,
          category: '薪金',
          amount: 1000,
          note: '',
          method: '現金',
        ),
      ],
      opening: {'八達通': 88},
      stocks: [
        ImportedStock(
          holding: const Holding(
            id: 0,
            market: Market.hk,
            symbol: '00005',
            name: '滙豐',
            currentPrice: 65,
          ),
          trades: [
            Trade(
              id: 0,
              holdingId: 0,
              date: DateTime(2026, 1, 2),
              side: TradeSide.buy,
              shares: 1000,
              price: 60,
              fee: 50,
            ),
          ],
          dividends: [
            Dividend(
              id: 0,
              holdingId: 0,
              date: DateTime(2026, 3, 1),
              amount: 2000,
              note: '中期息',
            ),
          ],
        ),
      ],
    );

    final entries = await database.getBookEntries();
    expect(entries.single.amount, 1000);
    expect(entries.single.note, isEmpty);
    expect(await database.getWalletFunds(), {'八達通': 88});
    final holdings = await database.getHoldings();
    expect(holdings.single.symbol, '00005');
    expect(holdings.single.currentPrice, closeTo(65, 0.001));
    expect(holdings.single.priceAsOf, isNull);
    final trades = await database.getTrades();
    expect(trades.single.holdingId, holdings.single.id);
    expect(trades.single.fee, closeTo(50, 0.001));
    final dividends = await database.getDividends();
    expect(dividends.single.note, '中期息');
  });

  test('新增和改名會保存，改名會連同記賬和錢包一起改', () async {
    final database = await AppDatabase.openInMemory();
    addTearDown(database.close);
    await database.insertBookEntry(
      BookEntry(
        id: 0,
        date: DateTime(2026, 10, 2),
        kind: BookKind.expense,
        currency: BookCurrency.hkd,
        category: '飲食',
        amount: 40,
        note: '午餐',
        method: '現金',
      ),
    );
    await database.setWalletFund('現金', 20);
    await database.addBookLabel(scope: 'expense', name: '下午茶');
    expect((await database.getBookLabels()).expense, contains('下午茶'));
    expect(
      () => database.addBookLabel(scope: 'expense', name: '下午茶'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          '這個名稱已經有了',
        ),
      ),
    );

    await database.renameBookLabel(scope: 'expense', from: '飲食', to: '夜宵');
    await database.renameBookLabel(scope: 'method', from: '現金', to: '家用現金');
    final entries = await database.getBookEntries();
    expect(entries.single.category, '夜宵');
    expect(entries.single.method, '家用現金');
    expect(await database.getWalletFunds(), {'家用現金': 20});
    final labels = await database.getBookLabels();
    expect(labels.expense, contains('夜宵'));
    expect(labels.expense, isNot(contains('飲食')));
    expect(labels.methods, contains('家用現金'));
    expect(labels.methods, isNot(contains('現金')));
  });
}
