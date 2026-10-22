import 'package:divgain/data/price_history.dart';
import 'package:divgain/data/stock_directory.dart';
import 'package:divgain/models/ledger.dart';
import 'package:divgain/screens/holding_form_screen.dart';
import 'package:divgain/state/portfolio_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('港股代碼轉成 Yahoo 的 4 位代碼', () {
    expect(quoteSymbol(Market.hk, '00005'), '0005.HK');
    expect(quoteSymbol(Market.hk, '00700'), '0700.HK');
    expect(quoteSymbol(Market.hk, '09618'), '9618.HK');
    expect(quoteSymbol(Market.us, 'AAPL'), 'AAPL');
    expect(quoteSymbol(Market.us, 'BRK.B'), 'BRK-B');
  });

  test('只採用代碼完全相符的股票名稱', () {
    const body = '''
{"quotes":[
  {"quoteType":"ETF","symbol":"AAPU","longname":"Direxion Daily AAPL Bull 2X Shares"},
  {"quoteType":"EQUITY","symbol":"0005.HK","shortname":"HSBC HOLDINGS","longname":"匯豐控股"},
  {"quoteType":"EQUITY","symbol":"AAPL","shortname":"Apple","longname":"Apple Inc."}
]}
''';

    expect(nameFromSearchBody(body, '0005.HK'), '匯豐控股');
    expect(nameFromSearchBody(body, 'AAPL'), 'Apple Inc.');
    expect(nameFromSearchBody(body, '0700.HK'), isNull);
  });

  testWidgets('輸入港股代碼後自動填上名稱', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hkdCnyProvider.overrideWith((ref) async => 0.85),
          stockDirectoryProvider.overrideWith((ref) {
            return StockDirectory(
              findName: (market, symbol) async {
                if (market == Market.hk && symbol == '00005') {
                  return const NameLookup.found('匯豐控股');
                }
                return const NameLookup.missing();
              },
              findLatest: (market, symbol) async {
                if (market == Market.hk && symbol == '00005') {
                  return DatedClose(date: DateTime(2026, 10, 16), price: 108.5);
                }
                return null;
              },
            );
          }),
        ],
        child: const MaterialApp(home: HoldingFormScreen()),
      ),
    );

    await tester.enterText(find.byKey(const Key('holding-symbol')), '5');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    final nameField = tester.widget<TextFormField>(
      find.byKey(const Key('holding-name')),
    );
    expect(nameField.controller?.text, '匯豐控股');
    final priceField = tester.widget<TextFormField>(
      find.byKey(const Key('holding-price')),
    );
    expect(priceField.controller?.text, '108.5');
    expect(find.textContaining('2026-10-16'), findsOneWidget);
  });
}
