import 'package:divgain/data/price_history.dart';
import 'package:divgain/data/stock_directory.dart';
import 'package:divgain/logic/portfolio_math.dart';
import 'package:divgain/models/ledger.dart';
import 'package:divgain/screens/trade_form_screen.dart';
import 'package:divgain/state/portfolio_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('港股收市日按香港時間計算', () {
    final stamp = DateTime.utc(2026, 10, 16, 1, 30).millisecondsSinceEpoch ~/ 1000;
    expect(tradingDate(stamp, Market.hk), DateTime(2026, 10, 16));
  });

  test('休市日沿用之前最近的收市價', () {
    final bars = [
      DatedClose(date: DateTime(2026, 10, 16), price: 417.8),
    ];
    final match = closeOnOrBefore(bars, DateTime(2026, 10, 17));
    expect(match?.price, 417.8);
    expect(match?.date, DateTime(2026, 10, 16));
    expect(
      PriceQuote(
        requested: DateTime(2026, 10, 17),
        date: match!.date,
        price: match.price,
      ).usedEarlierSession,
      isTrue,
    );
  });

  test('從行情資料讀出每日收市價，略過空值', () {
    final bars = closesFromChart({
      'timestamp': [
        DateTime.utc(2026, 10, 15, 1, 30).millisecondsSinceEpoch ~/ 1000,
        DateTime.utc(2026, 10, 16, 1, 30).millisecondsSinceEpoch ~/ 1000,
      ],
      'indicators': {
        'quote': [
          {
            'close': [417.8, null],
          },
        ],
      },
    }, Market.hk);

    expect(bars, hasLength(1));
    expect(bars.single.date, DateTime(2026, 10, 15));
    expect(bars.single.price, 417.8);
  });

  testWidgets('記買賣時按所選日期填上收市價', (tester) async {
    final data = PortfolioData(
      holdings: const [
        Holding(
          id: 1,
          market: Market.hk,
          symbol: '00700',
          name: '騰訊控股',
          currentPrice: 400,
        ),
      ],
      trades: const [],
      dividends: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioProvider.overrideWith(() => _SeededPortfolio(data)),
          hkdCnyProvider.overrideWith((ref) async => 0.85),
          stockDirectoryProvider.overrideWith((ref) {
            return StockDirectory(
              findClose: (market, symbol, date) async {
                return PriceQuote(requested: date, date: date, price: 417.8);
              },
            );
          }),
        ],
        child: const MaterialApp(home: TradeFormScreen(holdingId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('417.8'), findsOneWidget);
    expect(find.textContaining('收市價'), findsOneWidget);
  });
}

class _SeededPortfolio extends PortfolioController {
  _SeededPortfolio(this.seed);

  final PortfolioData seed;

  @override
  Future<PortfolioData> build() async => seed;
}
