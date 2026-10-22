import '../models/ledger.dart';

class DatedClose {
  const DatedClose({required this.date, required this.price});

  final DateTime date;
  final double price;
}

/// The session used for [requested]. On a holiday this is the previous session.
class PriceQuote {
  const PriceQuote({
    required this.requested,
    required this.date,
    required this.price,
  });

  final DateTime requested;
  final DateTime date;
  final double price;

  bool get usedEarlierSession {
    return date.year != requested.year ||
        date.month != requested.month ||
        date.day != requested.day;
  }
}

DateTime nthSundayUtc(int year, int month, int n) {
  final first = DateTime.utc(year, month, 1);
  final delta = (DateTime.sunday - first.weekday) % 7;
  return first.add(Duration(days: delta + (n - 1) * 7));
}

Duration easternOffset(DateTime utc) {
  final start = nthSundayUtc(utc.year, 3, 2).add(const Duration(hours: 7));
  final end = nthSundayUtc(utc.year, 11, 1).add(const Duration(hours: 6));
  final daylight = !utc.isBefore(start) && utc.isBefore(end);
  return Duration(hours: daylight ? -4 : -5);
}

DateTime tradingDate(int epochSeconds, Market market) {
  final utc = DateTime.fromMillisecondsSinceEpoch(
    epochSeconds * 1000,
    isUtc: true,
  );
  final local = market == Market.hk
      ? utc.add(const Duration(hours: 8))
      : utc.add(easternOffset(utc));
  return DateTime(local.year, local.month, local.day);
}

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

DatedClose? closeOnOrBefore(List<DatedClose> bars, DateTime day) {
  final target = _day(day);
  DatedClose? best;
  for (final bar in bars) {
    final barDay = _day(bar.date);
    if (barDay.isAfter(target)) continue;
    if (best == null || barDay.isAfter(_day(best.date))) best = bar;
  }
  return best;
}

List<DatedClose> closesFromChart(Map<String, dynamic> chart, Market market) {
  final timestamps = chart['timestamp'];
  final indicators = chart['indicators'];
  if (timestamps is! List || indicators is! Map) return const [];
  final quote = indicators['quote'];
  if (quote is! List || quote.isEmpty || quote.first is! Map) return const [];
  final closes = (quote.first as Map)['close'];
  if (closes is! List) return const [];
  final bars = <DatedClose>[];
  final count = timestamps.length < closes.length
      ? timestamps.length
      : closes.length;
  for (var i = 0; i < count; i++) {
    final stamp = timestamps[i];
    final close = closes[i];
    if (stamp is! num || close is! num) continue;
    bars.add(
      DatedClose(
        date: tradingDate(stamp.toInt(), market),
        price: close.toDouble(),
      ),
    );
  }
  return bars;
}

DatedClose? latestFromChart(Map<String, dynamic> chart, Market market) {
  final meta = chart['meta'];
  if (meta is Map) {
    final price = meta['regularMarketPrice'];
    final time = meta['regularMarketTime'];
    if (price is num && time is num && price > 0) {
      return DatedClose(
        date: tradingDate(time.toInt(), market),
        price: price.toDouble(),
      );
    }
  }
  final bars = closesFromChart(chart, market);
  if (bars.isEmpty) return null;
  return bars.last;
}

Map<String, dynamic>? chartResult(Object? decoded) {
  if (decoded is! Map) return null;
  final chart = decoded['chart'];
  if (chart is! Map) return null;
  final result = chart['result'];
  if (result is! List || result.isEmpty || result.first is! Map) return null;
  return Map<String, dynamic>.from(result.first as Map);
}
