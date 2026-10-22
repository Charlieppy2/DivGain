import 'package:divgain/logic/portfolio_math.dart';
import 'package:divgain/models/ledger.dart';
import 'package:divgain/models/book.dart';
import 'package:divgain/screens/home_screen.dart';
import 'package:divgain/state/book_controller.dart';
import 'package:divgain/state/portfolio_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('首頁顯示港股買入加股息的總收益', (tester) async {
    final data = PortfolioData(
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
          note: '',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioProvider.overrideWith(() => _SeededPortfolio(data)),
          bookProvider.overrideWith(_EmptyBook.new),
          hkdCnyProvider.overrideWith((ref) async => 0.85),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+HK\$6,950.00'), findsOneWidget);
    expect(find.text('+HK\$4,950.00'), findsWidgets);
    expect(find.text('HK\$2,000.00'), findsWidgets);
    expect(find.text('US\$0.00'), findsWidgets);

    await tester.scrollUntilVisible(find.text('00005'), 300);
    expect(find.text('00005'), findsOneWidget);
    expect(find.text('滙豐'), findsOneWidget);
    expect(find.text('1,000 股'), findsOneWidget);
    expect(find.text('今年收到的股息'), findsWidgets);
    expect(find.text('已清倉（1）'), findsNothing);
  });

  testWidgets('賣光的股票收在已清倉，今年股息不含去年', (tester) async {
    final year = DateTime.now().year;
    final data = PortfolioData(
      holdings: const [
        Holding(
          id: 1,
          market: Market.hk,
          symbol: '00005',
          name: '滙豐',
          currentPrice: 10,
        ),
        Holding(
          id: 2,
          market: Market.hk,
          symbol: '00001',
          name: '長和',
          currentPrice: 40,
        ),
        Holding(
          id: 3,
          market: Market.hk,
          symbol: '00002',
          name: '新股',
          currentPrice: 1,
        ),
      ],
      trades: [
        Trade(
          id: 1,
          holdingId: 1,
          date: DateTime(year, 1, 2),
          side: TradeSide.buy,
          shares: 100,
          price: 10,
          fee: 0,
        ),
        Trade(
          id: 2,
          holdingId: 2,
          date: DateTime(year, 1, 2),
          side: TradeSide.buy,
          shares: 10,
          price: 10,
          fee: 0,
        ),
        Trade(
          id: 3,
          holdingId: 2,
          date: DateTime(year, 2, 2),
          side: TradeSide.sell,
          shares: 10,
          price: 10,
          fee: 0,
        ),
      ],
      dividends: [
        Dividend(
          id: 1,
          holdingId: 1,
          date: DateTime(year - 1, 12, 31),
          amount: 500,
          note: '',
        ),
        Dividend(
          id: 2,
          holdingId: 1,
          date: DateTime(year, 3, 1),
          amount: 2000,
          note: '',
        ),
        Dividend(
          id: 3,
          holdingId: 2,
          date: DateTime(year, 4, 1),
          amount: 300,
          note: '',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioProvider.overrideWith(() => _SeededPortfolio(data)),
          bookProvider.overrideWith(_EmptyBook.new),
          hkdCnyProvider.overrideWith((ref) async => 0.85),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('HK\$2,300.00'), findsOneWidget);
    expect(find.text('00001'), findsNothing);

    await tester.scrollUntilVisible(find.text('00005'), 300);
    expect(find.text('00005'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('00002'), 300);
    expect(find.text('00002'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('closed-holdings')), 300);
    expect(find.text('已清倉（1）'), findsOneWidget);

    await tester.tap(find.byKey(const Key('closed-holdings')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('00001'), 300);

    expect(find.text('00001'), findsOneWidget);
    expect(find.text('長和'), findsOneWidget);
  });
}

class _SeededPortfolio extends PortfolioController {
  _SeededPortfolio(this.seed);

  final PortfolioData seed;

  @override
  Future<PortfolioData> build() async => seed;
}

class _EmptyBook extends BookController {
  @override
  Future<List<BookEntry>> build() async => [];
}
