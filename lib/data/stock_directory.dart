import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ledger.dart';
import 'price_history.dart';

enum NameLookupStatus { found, missing, unavailable }

class NameLookup {
  const NameLookup.found(this.name) : status = NameLookupStatus.found;
  const NameLookup.missing() : name = null, status = NameLookupStatus.missing;
  const NameLookup.unavailable()
    : name = null,
      status = NameLookupStatus.unavailable;

  final NameLookupStatus status;
  final String? name;
}

/// Yahoo Finance symbol. Hong Kong codes are queried as 4-digit `.HK` symbols.
String? quoteSymbol(Market market, String normalized) {
  if (normalized.isEmpty) return null;
  if (market == Market.us) {
    return normalized.replaceAll('.', '-');
  }
  if (!RegExp(r'^\d+$').hasMatch(normalized)) {
    return '$normalized.HK';
  }
  final stripped = normalized.replaceFirst(RegExp(r'^0+'), '');
  final core = stripped.isEmpty ? '0' : stripped;
  final code = core.length >= 4 ? core : core.padLeft(4, '0');
  return '$code.HK';
}

String? nameFromSearchBody(String body, String expectedSymbol) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final quotes = decoded['quotes'];
  if (quotes is! List<dynamic>) return null;
  final target = expectedSymbol.toUpperCase();
  for (final item in quotes) {
    if (item is! Map<String, dynamic>) continue;
    if (item['quoteType'] != 'EQUITY') continue;
    final symbol = (item['symbol'] as String?)?.toUpperCase();
    if (symbol != target) continue;
    final longName = (item['longname'] as String?)?.trim();
    if (longName != null && longName.isNotEmpty) return longName;
    final shortName = (item['shortname'] as String?)?.trim();
    if (shortName != null && shortName.isNotEmpty) return shortName;
  }
  return null;
}

double? cnyPerHkd(Object? decoded) {
  if (decoded is Map) {
    final rates = decoded['rates'];
    if (rates is Map) {
      final cny = rates['CNY'];
      if (cny is num && cny > 0) return cny.toDouble();
    }
  }
  if (decoded is List) {
    for (final item in decoded) {
      if (item is Map && item['quote'] == 'CNY') {
        final rate = item['rate'];
        if (rate is num && rate > 0) return rate.toDouble();
      }
    }
  }
  return null;
}

class StockDirectory {
  StockDirectory({this.client, this.findName, this.findClose, this.findLatest});

  final http.Client? client;
  final Future<NameLookup> Function(Market market, String symbol)? findName;
  final Future<PriceQuote?> Function(
    Market market,
    String symbol,
    DateTime date,
  )?
  findClose;
  final Future<DatedClose?> Function(Market market, String symbol)? findLatest;

  Future<NameLookup> lookup(Market market, String symbol) {
    final injected = findName;
    if (injected != null) return injected(market, symbol);
    return _lookupRemote(market, symbol);
  }

  Future<NameLookup> _lookupRemote(Market market, String symbol) async {
    final quote = quoteSymbol(market, symbol);
    if (quote == null) return const NameLookup.missing();
    final region = market == Market.hk ? 'HK' : 'US';
    final uri = Uri.https('query2.finance.yahoo.com', '/v1/finance/search', {
      'q': quote,
      'quotesCount': '8',
      'newsCount': '0',
      'lang': 'zh-Hant-HK',
      'region': region,
    });
    final client = this.client ?? http.Client();
    final closeClient = this.client == null;
    try {
      final response = await client
          .get(uri, headers: const {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const NameLookup.unavailable();
      final name = nameFromSearchBody(response.body, quote);
      if (name == null) return const NameLookup.missing();
      return NameLookup.found(name);
    } catch (_) {
      return const NameLookup.unavailable();
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<PriceQuote?> closeOn(Market market, String symbol, DateTime date) {
    final injected = findClose;
    if (injected != null) return injected(market, symbol, date);
    return _closeOnRemote(market, symbol, date);
  }

  Future<DatedClose?> latestClose(Market market, String symbol) {
    final injected = findLatest;
    if (injected != null) return injected(market, symbol);
    return _latestRemote(market, symbol);
  }

  Future<PriceQuote?> _closeOnRemote(
    Market market,
    String symbol,
    DateTime date,
  ) async {
    final quote = quoteSymbol(market, symbol);
    if (quote == null) return null;
    final day = DateTime(date.year, date.month, date.day);
    final start = DateTime.utc(
      day.year,
      day.month,
      day.day,
    ).subtract(const Duration(days: 14));
    final end = DateTime.utc(day.year, day.month, day.day).add(const Duration(days: 2));
    final chart = await _chart(quote, {
      'period1': '${start.millisecondsSinceEpoch ~/ 1000}',
      'period2': '${end.millisecondsSinceEpoch ~/ 1000}',
      'interval': '1d',
    });
    if (chart == null) return null;
    final match = closeOnOrBefore(closesFromChart(chart, market), day);
    if (match == null) return null;
    return PriceQuote(requested: day, date: match.date, price: match.price);
  }

  Future<DatedClose?> _latestRemote(Market market, String symbol) async {
    final quote = quoteSymbol(market, symbol);
    if (quote == null) return null;
    final chart = await _chart(quote, {'range': '5d', 'interval': '1d'});
    if (chart == null) return null;
    return latestFromChart(chart, market);
  }

  Future<double?> hkdToCny() async {
    final fromFrankfurter = await _frankfurterCny();
    if (fromFrankfurter != null) return fromFrankfurter;
    final chart = await _chart('HKDCNY=X', {'range': '5d', 'interval': '1d'});
    if (chart == null) return null;
    final price = latestFromChart(chart, Market.hk)?.price;
    if (price == null || price <= 0) return null;
    return price;
  }

  Future<double?> _frankfurterCny() async {
    final uri = Uri.https('api.frankfurter.dev', '/v2/rates', {
      'base': 'HKD',
      'quotes': 'CNY',
    });
    final client = this.client ?? http.Client();
    final closeClient = this.client == null;
    try {
      final response = await client
          .get(uri, headers: const {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      return cnyPerHkd(jsonDecode(response.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<Map<String, dynamic>?> _chart(
    String quote,
    Map<String, String> query,
  ) async {
    final uri = Uri.https(
      'query1.finance.yahoo.com',
      '/v8/finance/chart/$quote',
      query,
    );
    final client = this.client ?? http.Client();
    final closeClient = this.client == null;
    try {
      final response = await client
          .get(uri, headers: const {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      return chartResult(jsonDecode(response.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }
}
