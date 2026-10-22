import 'package:divgain/data/stock_directory.dart';
import 'package:divgain/logic/book_math.dart';
import 'package:divgain/logic/portfolio_math.dart';
import 'package:divgain/models/book.dart';
import 'package:divgain/screens/book_entry_form_screen.dart';
import 'package:divgain/screens/home_screen.dart';
import 'package:divgain/state/book_controller.dart';
import 'package:divgain/state/portfolio_controller.dart';
import 'package:divgain/ui/format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('港元旁邊換算成人民幣', () {
    expect(
      cnyPerHkd({
        'rates': {'CNY': 0.85},
      }),
      0.85,
    );
    expect(
      cnyPerHkd([
        {'quote': 'CNY', 'rate': 0.84961},
      ]),
      0.84961,
    );
    expect(cnyPerHkd({'rates': {}}), isNull);
    expect(rmbBeside(100, 0.85), '約 ¥85.00');
    expect(rmbBeside(-48, 0.85), '約 -¥40.80');
    expect(rmbBeside(0, 0.85), isNull);
    expect(rmbBeside(10, null), isNull);
  });

  test('本月結餘只計港元，上個月不算', () {
    final month = DateTime(2026, 10);
    final entries = [
      BookEntry(
        id: 1,
        date: DateTime(2026, 10, 1),
        kind: BookKind.income,
        currency: BookCurrency.hkd,
        category: '薪金',
        amount: 1500,
        note: '',
      ),
      BookEntry(
        id: 2,
        date: DateTime(2026, 10, 2),
        kind: BookKind.expense,
        currency: BookCurrency.hkd,
        category: '飲食',
        amount: 300,
        note: '',
      ),
      BookEntry(
        id: 3,
        date: DateTime(2026, 9, 30),
        kind: BookKind.income,
        currency: BookCurrency.hkd,
        category: '紅包',
        amount: 800,
        note: '',
      ),
    ];

    final hkd = summarizeCurrencyMonth(entries, BookCurrency.hkd, month);

    expect(hkd.income, closeTo(1500, 0.001));
    expect(hkd.expense, closeTo(300, 0.001));
    expect(hkd.balance, closeTo(1200, 0.001));
    expect(entriesInMonth(entries, month).map((entry) => entry.id), [2, 1]);
  });

  test('錢包按付款方式分開計算結餘', () {
    final entries = [
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
      BookEntry(
        id: 2,
        date: DateTime(2026, 10, 2),
        kind: BookKind.expense,
        currency: BookCurrency.hkd,
        category: '飲食',
        amount: 40,
        note: '',
        method: '現金',
      ),
      BookEntry(
        id: 3,
        date: DateTime(2026, 10, 3),
        kind: BookKind.expense,
        currency: BookCurrency.hkd,
        category: '購物',
        amount: 80,
        note: '',
        method: 'AlipayHK',
      ),
      BookEntry(
        id: 4,
        date: DateTime(2026, 9, 1),
        kind: BookKind.expense,
        currency: BookCurrency.hkd,
        category: '交通',
        amount: 12,
        note: '',
      ),
    ];

    final lines = walletBalances(entries);
    expect(lines.first.method, '現金');
    expect(lines.first.balance, closeTo(960, 0.001));
    expect(
      lines.firstWhere((line) => line.method == 'AlipayHK').balance,
      closeTo(-80, 0.001),
    );
    expect(
      lines.firstWhere((line) => line.method == '信用卡').balance,
      closeTo(0, 0.001),
    );
    expect(lines.last.method, '未填');
    expect(lines.last.balance, closeTo(-12, 0.001));
    expect(
      lines.fold<double>(0, (sum, line) => sum + line.balance),
      closeTo(868, 0.001),
    );

    final withOpening = walletBalances(
      entries,
      opening: {'現金': 500, '信用卡': 20},
    );
    expect(
      withOpening.firstWhere((line) => line.method == '現金').balance,
      closeTo(1460, 0.001),
    );
    expect(
      withOpening.firstWhere((line) => line.method == '信用卡').balance,
      closeTo(20, 0.001),
    );
    expect(
      withOpening.fold<double>(0, (sum, line) => sum + line.balance),
      closeTo(1388, 0.001),
    );
    expect(
      methodBalance(entries, '現金', opening: {'現金': 500}, excludeEntryId: 2),
      closeTo(1500, 0.001),
    );
    expect(entriesForWallet(entries, '現金').map((entry) => entry.id), [2, 1]);
    expect(entriesForWallet(entries, 'AlipayHK').single.id, 3);
    expect(entriesForWallet(entries, '未填').single.id, 4);
  });

  test('日結和年結不會把其他日子混進來', () {
    final entries = [
      BookEntry(
        id: 1,
        date: DateTime(2026, 10, 1),
        kind: BookKind.income,
        currency: BookCurrency.hkd,
        category: '薪金',
        amount: 1500,
        note: '',
      ),
      BookEntry(
        id: 2,
        date: DateTime(2026, 10, 2),
        kind: BookKind.expense,
        currency: BookCurrency.hkd,
        category: '飲食',
        amount: 300,
        note: '',
      ),
      BookEntry(
        id: 4,
        date: DateTime(2026, 9, 30),
        kind: BookKind.income,
        currency: BookCurrency.hkd,
        category: '紅包',
        amount: 800,
        note: '',
      ),
    ];

    final day = summarizeClose(
      entries,
      BookCurrency.hkd,
      BookClose.day,
      DateTime(2026, 10, 2),
    );
    final year = summarizeClose(
      entries,
      BookCurrency.hkd,
      BookClose.year,
      DateTime(2026, 10, 2),
    );

    expect(day.expense, closeTo(300, 0.001));
    expect(day.income, closeTo(0, 0.001));
    expect(year.income, closeTo(2300, 0.001));
    expect(year.expense, closeTo(300, 0.001));
    expect(year.balance, closeTo(2000, 0.001));
    expect(
      groupByMonth(entriesInClose(entries, BookClose.year, DateTime(2026)))
          .map((group) => group.date.month),
      [10, 9],
    );
    final october = monthCalendarDays(DateTime(2026, 10));
    expect(october.whereType<DateTime>().length, 31);
    expect(october[4], DateTime(2026, 10, 1));
    expect(october.first, isNull);
  });

  testWidgets('可以從首頁記一筆支出，並按月份查看', (tester) async {
    final book = _MemoryBook();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioProvider.overrideWith(() => _EmptyPortfolio()),
          bookProvider.overrideWith(() => book),
          hkdCnyProvider.overrideWith((ref) async => 0.85),
          walletFundsProvider.overrideWith(_MemoryFunds.new),
          bookLabelsProvider.overrideWith(_MemoryLabels.new),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('記賬'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-book')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('這個月還沒有記賬'), 200);
    expect(find.text('這個月還沒有記賬'), findsOneWidget);
    await tester.tap(find.text('記一筆'));
    await tester.pumpAndSettle();
    expect(find.text('人民幣'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('book-method')));
    await tester.pumpAndSettle();
    expect(find.text('從錢包扣除'), findsOneWidget);
    await tester.tap(find.byKey(const Key('book-method')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AlipayHK').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('book-amount')), '48');
    await tester.pump();
    expect(find.text('約 ¥40.80'), findsOneWidget);
    expect(find.text('扣除後'), findsOneWidget);
    expect(find.text('-HK\$48.00'), findsWidgets);
    await tester.ensureVisible(find.text('儲存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('飲食'), 300);
    expect(find.text('飲食'), findsWidgets);
    expect(find.textContaining('AlipayHK'), findsWidgets);
    expect(find.text('HK\$48.00'), findsWidgets);
    await tester.tap(find.byKey(const Key('open-wallet')));
    await tester.pumpAndSettle();
    expect(find.text('原有資金加記賬結餘'), findsOneWidget);
    expect(find.text('AlipayHK'), findsOneWidget);
    expect(find.text('現金'), findsOneWidget);
    expect(find.text('-HK\$48.00'), findsWidgets);

    await tester.tap(find.byKey(const Key('wallet-method-AlipayHK')));
    await tester.pumpAndSettle();
    expect(find.text('每筆進出'), findsOneWidget);
    expect(find.text('飲食'), findsOneWidget);
    expect(find.text('-HK\$48.00'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('wallet-method-現金')));
    await tester.pumpAndSettle();
    expect(find.text('還沒有進出'), findsOneWidget);
    await tester.tap(find.byKey(const Key('wallet-opening')));
    await tester.pumpAndSettle();
    expect(find.text('現金的原有資金'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('wallet-opening-amount')), '500');
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();
    expect(find.text('+HK\$500.00'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('這個月還沒有記賬'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const Key('book-previous-month')),
      -300,
    );
    await tester.tap(find.byKey(const Key('book-previous-month')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('這個月還沒有記賬'), 200);
    expect(find.text('這個月還沒有記賬'), findsOneWidget);
    expect(find.text('飲食'), findsNothing);
  });

  testWidgets('日結只計當天，年結計入當年各月', (tester) async {
    final today = DateTime.now();
    final otherDay = DateTime(today.year, today.month, today.day == 1 ? 2 : 1);
    final book = _MemoryBook([
      BookEntry(
        id: 1,
        date: today,
        kind: BookKind.expense,
        currency: BookCurrency.hkd,
        category: '飲食',
        amount: 48,
        note: '',
      ),
      BookEntry(
        id: 2,
        date: otherDay,
        kind: BookKind.income,
        currency: BookCurrency.hkd,
        category: '薪金',
        amount: 200,
        note: '',
      ),
      BookEntry(
        id: 3,
        date: DateTime(today.year - 1, 6, 1),
        kind: BookKind.income,
        currency: BookCurrency.hkd,
        category: '紅包',
        amount: 1000,
        note: '',
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioProvider.overrideWith(_EmptyPortfolio.new),
          bookProvider.overrideWith(() => book),
          hkdCnyProvider.overrideWith((ref) async => 0.85),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-book')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('飲食'), 300);
    expect(find.text('飲食'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('薪金'), 200);
    expect(find.text('薪金'), findsOneWidget);
    expect(find.text('紅包'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const Key('book-close-day')),
      -300,
    );

    await tester.tap(find.byKey(const Key('book-close-day')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('飲食'), 200);
    expect(find.text('飲食'), findsOneWidget);
    expect(find.text('薪金'), findsNothing);
    expect(
      find.text('${today.year}年${today.month}月${today.day}日'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('book-close-year')));
    await tester.pumpAndSettle();
    expect(find.text('${today.year}年'), findsWidgets);
    expect(find.text('${today.month}月'), findsOneWidget);
    expect(find.text('飲食'), findsNothing);
    expect(find.text('紅包'), findsNothing);

    await tester.tap(find.byKey(const Key('book-previous-month')));
    await tester.pumpAndSettle();
    expect(find.text('+HK\$1,000.00'), findsWidgets);
    expect(find.text('飲食'), findsNothing);
  });

  testWidgets('月曆點一天就看到當天支出', (tester) async {
    final today = DateTime.now();
    final otherDay = DateTime(today.year, today.month, today.day == 1 ? 2 : 1);
    final book = _MemoryBook([
      BookEntry(
        id: 1,
        date: today,
        kind: BookKind.expense,
        currency: BookCurrency.hkd,
        category: '飲食',
        amount: 48,
        note: '',
      ),
      BookEntry(
        id: 2,
        date: otherDay,
        kind: BookKind.income,
        currency: BookCurrency.hkd,
        category: '薪金',
        amount: 200,
        note: '',
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioProvider.overrideWith(_EmptyPortfolio.new),
          bookProvider.overrideWith(() => book),
          hkdCnyProvider.overrideWith((ref) async => 0.85),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-book')));
    await tester.pumpAndSettle();

    final todayKey = Key(
      'book-calendar-${today.year}-${today.month}-${today.day}',
    );
    await tester.ensureVisible(find.byKey(todayKey));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(todayKey),
        matching: find.text('HK\$48.00'),
      ),
      findsOneWidget,
    );
    final otherKey = Key(
      'book-calendar-${otherDay.year}-${otherDay.month}-${otherDay.day}',
    );
    expect(
      find.descendant(
        of: find.byKey(otherKey),
        matching: find.text('HK\$200.00'),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(todayKey));
    await tester.pumpAndSettle();
    expect(find.byKey(todayKey), findsOneWidget);
    expect(find.text('${today.year}年${today.month}月'), findsOneWidget);
    expect(
      find.text('${today.year}年${today.month}月${today.day}日'),
      findsOneWidget,
    );
    expect(find.text('支出'), findsWidgets);
    await tester.scrollUntilVisible(find.text('飲食'), 200);
    expect(find.text('飲食'), findsOneWidget);
    expect(find.text('薪金'), findsNothing);
  });

  testWidgets('分類可以新增，也可以改名', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookProvider.overrideWith(_MemoryBook.new),
          walletFundsProvider.overrideWith(_MemoryFunds.new),
          bookLabelsProvider.overrideWith(_MemoryLabels.new),
          hkdCnyProvider.overrideWith((ref) async => 0.85),
        ],
        child: const MaterialApp(home: BookEntryFormScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book-add-category')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('book-label-name')), '下午茶');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('儲存'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('下午茶'), findsOneWidget);

    await tester.tap(find.byKey(const Key('book-rename-category')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('book-label-name')), '夜宵');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('儲存'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('夜宵'), findsOneWidget);
    expect(find.text('下午茶'), findsNothing);
  });
}

class _EmptyPortfolio extends PortfolioController {
  @override
  Future<PortfolioData> build() async {
    return const PortfolioData(holdings: [], trades: [], dividends: []);
  }
}

class _MemoryBook extends BookController {
  _MemoryBook([List<BookEntry>? seed]) : entries = [...?seed];

  final List<BookEntry> entries;

  @override
  Future<List<BookEntry>> build() async => [...entries];

  @override
  Future<void> saveEntry({
    int? id,
    required DateTime date,
    required BookKind kind,
    required BookCurrency currency,
    required String category,
    required double amount,
    required String note,
    required String method,
  }) async {
    final nextId =
        entries.fold<int>(
          0,
          (maxId, entry) => entry.id > maxId ? entry.id : maxId,
        ) +
        1;
    entries.add(
      BookEntry(
        id: id ?? nextId,
        date: date,
        kind: kind,
        currency: currency,
        category: category,
        amount: amount,
        note: note,
        method: method,
      ),
    );
    state = AsyncData([...entries]);
  }
}

class _MemoryFunds extends WalletFundsController {
  final funds = <String, double>{};

  @override
  Future<Map<String, double>> build() async => {...funds};

  @override
  Future<void> saveFund(String method, double amount) async {
    if (amount.abs() <= 0.004) {
      funds.remove(method);
    } else {
      funds[method] = amount;
    }
    state = AsyncData({...funds});
  }
}

class _MemoryLabels extends BookLabelsController {
  @override
  Future<BookLabels> build() async => BookLabels.defaults;

  @override
  Future<void> add({required String scope, required String name}) async {
    final current = state.value ?? BookLabels.defaults;
    final label = normalizeBookLabel(scope, name, current.forScope(scope));
    state = AsyncData(
      _replaceLabels(current, scope, [...current.forScope(scope), label]),
    );
  }

  @override
  Future<void> rename({
    required String scope,
    required String from,
    required String to,
  }) async {
    final current = state.value ?? BookLabels.defaults;
    final previous = from.trim();
    final label = normalizeBookLabel(
      scope,
      to,
      current.forScope(scope),
      replacing: previous,
    );
    state = AsyncData(
      _replaceLabels(current, scope, [
        for (final item in current.forScope(scope))
          if (item == previous) label else item,
      ]),
    );
  }
}

BookLabels _replaceLabels(
  BookLabels current,
  String scope,
  List<String> names,
) {
  return switch (scope) {
    'income' => BookLabels(
      expense: current.expense,
      income: names,
      methods: current.methods,
    ),
    'method' => BookLabels(
      expense: current.expense,
      income: current.income,
      methods: names,
    ),
    _ => BookLabels(
      expense: names,
      income: current.income,
      methods: current.methods,
    ),
  };
}
