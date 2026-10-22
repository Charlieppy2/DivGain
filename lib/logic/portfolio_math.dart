import '../models/ledger.dart';

const shareEpsilon = 1e-8;

class ShareShortage implements Exception {
  const ShareShortage();

  String get message => '賣出股數不能超過持有股數';
}

class AppliedTrades {
  const AppliedTrades({
    required this.shares,
    required this.averageCost,
    required this.realizedPnl,
  });

  final double shares;
  final double averageCost;
  final double realizedPnl;
}

int compareTrades(Trade a, Trade b) {
  final byDate = a.date.compareTo(b.date);
  if (byDate != 0) return byDate;
  return _sortId(a.id).compareTo(_sortId(b.id));
}

int _sortId(int id) => id == 0 ? 1 << 30 : id;

/// Average-cost ledger. Buy fees increase cost; sell fees reduce proceeds.
/// Selling does not change the average cost of the shares that remain.
AppliedTrades applyTrades(List<Trade> trades) {
  final ordered = [...trades]..sort(compareTrades);
  var shares = 0.0;
  var averageCost = 0.0;
  var realizedPnl = 0.0;

  for (final trade in ordered) {
    if (trade.side == TradeSide.buy) {
      final nextShares = shares + trade.shares;
      final nextCost = shares * averageCost + trade.shares * trade.price + trade.fee;
      shares = nextShares;
      averageCost = shares <= shareEpsilon ? 0 : nextCost / shares;
    } else {
      if (trade.shares - shares > shareEpsilon) {
        throw const ShareShortage();
      }
      final proceeds = trade.shares * trade.price - trade.fee;
      realizedPnl += proceeds - trade.shares * averageCost;
      shares -= trade.shares;
      if (shares <= shareEpsilon) {
        shares = 0;
        averageCost = 0;
      }
    }
  }

  return AppliedTrades(
    shares: shares,
    averageCost: averageCost,
    realizedPnl: realizedPnl,
  );
}

class HoldingSummary {
  const HoldingSummary({
    required this.holding,
    required this.shares,
    required this.averageCost,
    required this.costBasis,
    required this.marketValue,
    required this.unrealizedPnl,
    required this.realizedPnl,
    required this.dividends,
    required this.totalGain,
  });

  final Holding holding;
  final double shares;
  final double averageCost;
  final double costBasis;
  final double marketValue;
  final double unrealizedPnl;
  final double realizedPnl;
  final double dividends;
  final double totalGain;

  double get pricePnl => realizedPnl + unrealizedPnl;
}

class CurrencySummary {
  const CurrencySummary({
    required this.market,
    required this.marketValue,
    required this.totalGain,
    required this.dividends,
    required this.dividendsThisYear,
    required this.realizedPnl,
    required this.unrealizedPnl,
  });

  final Market market;
  final double marketValue;
  final double totalGain;
  final double dividends;
  final double dividendsThisYear;
  final double realizedPnl;
  final double unrealizedPnl;
}

HoldingSummary summarizeHolding({
  required Holding holding,
  required List<Trade> trades,
  required List<Dividend> dividends,
}) {
  final applied = applyTrades(trades);
  final costBasis = applied.shares * applied.averageCost;
  final marketValue = applied.shares * holding.currentPrice;
  final unrealizedPnl = marketValue - costBasis;
  final dividendTotal = dividends.fold<double>(
    0,
    (sum, dividend) => sum + dividend.amount,
  );
  return HoldingSummary(
    holding: holding,
    shares: applied.shares,
    averageCost: applied.averageCost,
    costBasis: costBasis,
    marketValue: marketValue,
    unrealizedPnl: unrealizedPnl,
    realizedPnl: applied.realizedPnl,
    dividends: dividendTotal,
    totalGain: applied.realizedPnl + unrealizedPnl + dividendTotal,
  );
}

CurrencySummary summarizeCurrency(
  Market market,
  List<HoldingSummary> holdings, {
  List<Dividend> dividends = const [],
  DateTime? today,
}) {
  final rows = holdings.where((item) => item.holding.market == market);
  final year = (today ?? DateTime.now()).year;
  final ids = <int>{
    for (final item in rows) item.holding.id,
  };
  var dividendsThisYear = 0.0;
  for (final dividend in dividends) {
    if (dividend.date.year == year && ids.contains(dividend.holdingId)) {
      dividendsThisYear += dividend.amount;
    }
  }
  return CurrencySummary(
    market: market,
    marketValue: rows.fold(0, (sum, item) => sum + item.marketValue),
    totalGain: rows.fold(0, (sum, item) => sum + item.totalGain),
    dividends: rows.fold(0, (sum, item) => sum + item.dividends),
    dividendsThisYear: dividendsThisYear,
    realizedPnl: rows.fold(0, (sum, item) => sum + item.realizedPnl),
    unrealizedPnl: rows.fold(0, (sum, item) => sum + item.unrealizedPnl),
  );
}

/// A position is sold out only after it has been traded down to zero shares.
/// A new stock with no trades stays with the open holdings.
bool isSoldOut(HoldingSummary summary, List<Trade> trades) {
  if (summary.shares > shareEpsilon) return false;
  for (final trade in trades) {
    if (trade.holdingId == summary.holding.id) return true;
  }
  return false;
}

class PortfolioData {
  const PortfolioData({
    required this.holdings,
    required this.trades,
    required this.dividends,
  });

  final List<Holding> holdings;
  final List<Trade> trades;
  final List<Dividend> dividends;

  List<HoldingSummary> get summaries {
    final list = [
      for (final holding in holdings)
        summarizeHolding(
          holding: holding,
          trades: trades.where((trade) => trade.holdingId == holding.id).toList(),
          dividends: dividends
              .where((dividend) => dividend.holdingId == holding.id)
              .toList(),
        ),
    ]..sort((a, b) {
        final byMarket = a.holding.market.index.compareTo(b.holding.market.index);
        if (byMarket != 0) return byMarket;
        return a.holding.symbol.compareTo(b.holding.symbol);
      });
    return list;
  }

  HoldingSummary? summaryOf(int id) {
    for (final summary in summaries) {
      if (summary.holding.id == id) return summary;
    }
    return null;
  }

  List<Trade> tradesOf(int holdingId) {
    return trades.where((trade) => trade.holdingId == holdingId).toList()
      ..sort((a, b) => compareTrades(b, a));
  }

  List<Dividend> dividendsOf(int holdingId) {
    return dividends.where((dividend) => dividend.holdingId == holdingId).toList()
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        if (byDate != 0) return byDate;
        return b.id.compareTo(a.id);
      });
  }
}
