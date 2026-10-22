import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_database.dart';
import '../data/stock_directory.dart';
import '../logic/portfolio_math.dart';
import '../models/ledger.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(() {
    database.close();
  });
  return database;
});

final stockDirectoryProvider = Provider<StockDirectory>((ref) {
  return StockDirectory();
});

final hkdCnyProvider = FutureProvider<double?>((ref) async {
  return ref.watch(stockDirectoryProvider).hkdToCny();
});

final portfolioProvider =
    AsyncNotifierProvider<PortfolioController, PortfolioData>(
      PortfolioController.new,
    );

class PortfolioController extends AsyncNotifier<PortfolioData> {
  @override
  Future<PortfolioData> build() async {
    final data = await _load();
    unawaited(_refreshMarketPrices(data));
    return data;
  }

  Future<PortfolioData> _load() async {
    final database = ref.read(databaseProvider);
    final holdings = await database.getHoldings();
    final trades = await database.getTrades();
    final dividends = await database.getDividends();
    return PortfolioData(
      holdings: holdings,
      trades: trades,
      dividends: dividends,
    );
  }

  Future<void> _reload() async {
    state = AsyncData(await _load());
  }

  Future<bool> _applyLatestPrice(Holding holding) async {
    final quote = await ref
        .read(stockDirectoryProvider)
        .latestClose(holding.market, holding.symbol);
    if (quote == null) return false;
    final samePrice = (quote.price - holding.currentPrice).abs() < 0.0001;
    final asOf = holding.priceAsOf;
    final sameDay =
        asOf != null &&
        asOf.year == quote.date.year &&
        asOf.month == quote.date.month &&
        asOf.day == quote.date.day;
    if (samePrice && sameDay) return false;
    await ref.read(databaseProvider).updateMarketPrice(
      id: holding.id,
      price: quote.price,
      asOf: quote.date,
    );
    return true;
  }

  Future<void> _refreshMarketPrices(PortfolioData data) async {
    var changed = false;
    for (final holding in data.holdings) {
      if (await _applyLatestPrice(holding)) changed = true;
    }
    if (!changed) return;
    try {
      state = AsyncData(await _load());
    } catch (_) {
      // The screen may already have been closed.
    }
  }

  Future<void> saveHolding({
    int? id,
    required Market market,
    required String symbol,
    required String name,
    required double currentPrice,
  }) async {
    final normalized = normalizeSymbol(market, symbol);
    if (normalized.isEmpty) {
      throw const FormatException('請輸入代碼');
    }
    DateTime? priceAsOf;
    if (id != null) {
      final existing = state.value?.holdings
          .where((item) => item.id == id)
          .firstOrNull;
      if (existing != null &&
          (existing.currentPrice - currentPrice).abs() < 0.0001) {
        priceAsOf = existing.priceAsOf;
      }
    }
    final database = ref.read(databaseProvider);
    final holding = Holding(
      id: id ?? 0,
      market: market,
      symbol: normalized,
      name: name.trim(),
      currentPrice: currentPrice,
      priceAsOf: priceAsOf,
    );
    if (id == null) {
      await database.insertHolding(holding);
    } else {
      await database.updateHolding(holding);
    }
    await _reload();
    final saved = state.value?.holdings
        .where((item) => item.market == market && item.symbol == normalized)
        .firstOrNull;
    if (saved != null && await _applyLatestPrice(saved)) {
      await _reload();
    }
  }

  Future<void> deleteHolding(int id) async {
    await ref.read(databaseProvider).deleteHolding(id);
    await _reload();
  }

  Future<void> saveTrade({
    int? id,
    required int holdingId,
    required DateTime date,
    required TradeSide side,
    required double shares,
    required double price,
    required double fee,
  }) async {
    final current = state.requireValue;
    final others = current.trades.where(
      (trade) => trade.holdingId == holdingId && trade.id != id,
    );
    final draft = Trade(
      id: id ?? 0,
      holdingId: holdingId,
      date: date,
      side: side,
      shares: shares,
      price: price,
      fee: fee,
    );
    applyTrades([...others, draft]);
    final database = ref.read(databaseProvider);
    if (id == null) {
      await database.insertTrade(draft);
    } else {
      await database.updateTrade(draft);
    }
    await _reload();
  }

  Future<void> deleteTrade(Trade trade) async {
    final current = state.requireValue;
    final remaining = current.trades
        .where(
          (item) => item.holdingId == trade.holdingId && item.id != trade.id,
        )
        .toList();
    applyTrades(remaining);
    await ref.read(databaseProvider).deleteTrade(trade.id);
    await _reload();
  }

  Future<void> saveDividend({
    int? id,
    required int holdingId,
    required DateTime date,
    required double amount,
    required String note,
  }) async {
    final database = ref.read(databaseProvider);
    final dividend = Dividend(
      id: id ?? 0,
      holdingId: holdingId,
      date: date,
      amount: amount,
      note: note.trim(),
    );
    if (id == null) {
      await database.insertDividend(dividend);
    } else {
      await database.updateDividend(dividend);
    }
    await _reload();
  }

  Future<void> deleteDividend(int id) async {
    await ref.read(databaseProvider).deleteDividend(id);
    await _reload();
  }
}
