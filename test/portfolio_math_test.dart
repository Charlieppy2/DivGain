import 'package:divgain/logic/portfolio_math.dart';
import 'package:divgain/models/ledger.dart';
import 'package:divgain/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('港股買入加股息：總收益是未實現加股息', () {
    final summary = _hsbc(trades: [_buy()], dividends: [_dividend()]);

    expect(summary.shares, closeTo(1000, 0.001));
    expect(summary.averageCost, closeTo(60.05, 0.001));
    expect(summary.costBasis, closeTo(60050, 0.001));
    expect(summary.marketValue, closeTo(65000, 0.001));
    expect(summary.unrealizedPnl, closeTo(4950, 0.001));
    expect(summary.realizedPnl, closeTo(0, 0.001));
    expect(summary.dividends, closeTo(2000, 0.001));
    expect(summary.totalGain, closeTo(6950, 0.001));
    expect(formatMoney(Market.hk, summary.totalGain, signed: true), '+HK\$6,950.00');
  });

  test('賣出後保留均價，手續費從收入扣除', () {
    final summary = _hsbc(
      trades: [
        _buy(),
        Trade(
          id: 2,
          holdingId: 1,
          date: DateTime(2026, 6, 1),
          side: TradeSide.sell,
          shares: 200,
          price: 70,
          fee: 20,
        ),
      ],
      dividends: [_dividend()],
    );

    expect(summary.shares, closeTo(800, 0.001));
    expect(summary.averageCost, closeTo(60.05, 0.001));
    expect(summary.realizedPnl, closeTo(1970, 0.001));
    expect(summary.unrealizedPnl, closeTo(3960, 0.001));
    expect(summary.totalGain, closeTo(7930, 0.001));
  });

  test('清倉後再買入，已實現盈虧保留、均價重計', () {
    final applied = applyTrades([
      Trade(
        id: 1,
        holdingId: 1,
        date: DateTime(2026, 1, 1),
        side: TradeSide.buy,
        shares: 10,
        price: 10,
        fee: 0,
      ),
      Trade(
        id: 2,
        holdingId: 1,
        date: DateTime(2026, 2, 1),
        side: TradeSide.sell,
        shares: 10,
        price: 12,
        fee: 0,
      ),
      Trade(
        id: 3,
        holdingId: 1,
        date: DateTime(2026, 3, 1),
        side: TradeSide.buy,
        shares: 5,
        price: 8,
        fee: 0,
      ),
    ]);

    expect(applied.shares, closeTo(5, 0.001));
    expect(applied.averageCost, closeTo(8, 0.001));
    expect(applied.realizedPnl, closeTo(20, 0.001));
  });

  test('賣出超過持有股數會被拒絕', () {
    expect(
      () => applyTrades([
        Trade(
          id: 1,
          holdingId: 1,
          date: DateTime(2026, 1, 1),
          side: TradeSide.buy,
          shares: 10,
          price: 10,
          fee: 0,
        ),
        Trade(
          id: 2,
          holdingId: 1,
          date: DateTime(2026, 1, 2),
          side: TradeSide.sell,
          shares: 11,
          price: 10,
          fee: 0,
        ),
      ]),
      throwsA(isA<ShareShortage>()),
    );
  });

  test('同一天先按時間順序，未儲存的新交易排在當天最後', () {
    final buy = Trade(
      id: 1,
      holdingId: 1,
      date: DateTime(2026, 1, 1),
      side: TradeSide.buy,
      shares: 10,
      price: 10,
      fee: 0,
    );
    final sell = Trade(
      id: 0,
      holdingId: 1,
      date: DateTime(2026, 1, 1),
      side: TradeSide.sell,
      shares: 4,
      price: 12,
      fee: 0,
    );

    final applied = applyTrades([sell, buy]);
    expect(applied.shares, closeTo(6, 0.001));
    expect(applied.realizedPnl, closeTo(8, 0.001));
  });

  test('港股代碼補成 5 位，美股轉大寫', () {
    expect(normalizeSymbol(Market.hk, '5'), '00005');
    expect(normalizeSymbol(Market.hk, '0005'), '00005');
    expect(normalizeSymbol(Market.hk, '5.hk'), '00005');
    expect(normalizeSymbol(Market.hk, '00700'), '00700');
    expect(normalizeSymbol(Market.us, ' aapl '), 'AAPL');
  });

  test('今年股息只計當年，港元和美元分開', () {
    final today = DateTime(2026, 10, 20);
    final data = PortfolioData(
      holdings: const [
        Holding(
          id: 1,
          market: Market.hk,
          symbol: '00005',
          name: '滙豐',
          currentPrice: 65,
        ),
        Holding(
          id: 2,
          market: Market.us,
          symbol: 'AAPL',
          name: 'Apple',
          currentPrice: 200,
        ),
      ],
      trades: const [],
      dividends: [
        Dividend(
          id: 1,
          holdingId: 1,
          date: DateTime(2025, 12, 31),
          amount: 500,
          note: '',
        ),
        Dividend(
          id: 2,
          holdingId: 1,
          date: DateTime(2026, 3, 1),
          amount: 2000,
          note: '',
        ),
        Dividend(
          id: 3,
          holdingId: 2,
          date: DateTime(2026, 5, 1),
          amount: 80,
          note: '',
        ),
      ],
    );

    final hk = summarizeCurrency(
      Market.hk,
      data.summaries,
      dividends: data.dividends,
      today: today,
    );
    final us = summarizeCurrency(
      Market.us,
      data.summaries,
      dividends: data.dividends,
      today: today,
    );

    expect(hk.dividends, closeTo(2500, 0.001));
    expect(hk.dividendsThisYear, closeTo(2000, 0.001));
    expect(us.dividendsThisYear, closeTo(80, 0.001));
  });

  test('賣光的股票算已清倉，尚未買入的不算', () {
    final sold = summarizeHolding(
      holding: const Holding(
        id: 1,
        market: Market.hk,
        symbol: '00001',
        name: '長和',
        currentPrice: 40,
      ),
      trades: [
        Trade(
          id: 1,
          holdingId: 1,
          date: DateTime(2026, 1, 1),
          side: TradeSide.buy,
          shares: 10,
          price: 10,
          fee: 0,
        ),
        Trade(
          id: 2,
          holdingId: 1,
          date: DateTime(2026, 2, 1),
          side: TradeSide.sell,
          shares: 10,
          price: 12,
          fee: 0,
        ),
      ],
      dividends: const [],
    );
    final untouched = summarizeHolding(
      holding: const Holding(
        id: 2,
        market: Market.hk,
        symbol: '00002',
        name: '新股',
        currentPrice: 1,
      ),
      trades: const [],
      dividends: const [],
    );

    expect(sold.shares, closeTo(0, 0.001));
    expect(isSoldOut(sold, [
      Trade(
        id: 1,
        holdingId: 1,
        date: DateTime(2026, 1, 1),
        side: TradeSide.buy,
        shares: 10,
        price: 10,
        fee: 0,
      ),
    ]), isTrue);
    expect(isSoldOut(untouched, const []), isFalse);
    expect(isSoldOut(_hsbc(trades: [_buy()], dividends: [_dividend()]), [_buy()]), isFalse);
  });

  test('金額顯示紅漲方向的正負號', () {
    expect(formatMoney(Market.hk, 6950, signed: true), '+HK\$6,950.00');
    expect(formatMoney(Market.us, -12.5, signed: true), '-US\$12.50');
    expect(formatMoney(Market.hk, 0, signed: true), 'HK\$0.00');
  });
}

HoldingSummary _hsbc({
  required List<Trade> trades,
  required List<Dividend> dividends,
}) {
  return summarizeHolding(
    holding: const Holding(
      id: 1,
      market: Market.hk,
      symbol: '00005',
      name: '滙豐',
      currentPrice: 65,
    ),
    trades: trades,
    dividends: dividends,
  );
}

Trade _buy() {
  return Trade(
    id: 1,
    holdingId: 1,
    date: DateTime(2026, 1, 2),
    side: TradeSide.buy,
    shares: 1000,
    price: 60,
    fee: 50,
  );
}

Dividend _dividend() {
  return Dividend(
    id: 1,
    holdingId: 1,
    date: DateTime(2026, 3, 1),
    amount: 2000,
    note: '',
  );
}
