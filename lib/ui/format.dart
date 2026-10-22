import 'package:intl/intl.dart';

import '../models/ledger.dart';

final _hkMoney = NumberFormat.currency(
  locale: 'en_US',
  symbol: r'HK$',
  decimalDigits: 2,
);
final _usMoney = NumberFormat.currency(
  locale: 'en_US',
  symbol: r'US$',
  decimalDigits: 2,
);
final _shares = NumberFormat('#,##0.####', 'en_US');
final _day = DateFormat('yyyy-MM-dd');
final _cny = NumberFormat.currency(
  locale: 'en_US',
  symbol: '¥',
  decimalDigits: 2,
);

String formatMoney(Market market, double amount, {bool signed = false}) {
  final format = market == Market.hk ? _hkMoney : _usMoney;
  if (signed && amount > 0.004) {
    return '+${format.format(amount)}';
  }
  return format.format(amount);
}

String formatShares(double shares) {
  return _shares.format(shares);
}

String formatDate(DateTime date) {
  return _day.format(date);
}

String formatCny(double amount, {bool signed = false}) {
  if (signed && amount > 0.004) {
    return '+${_cny.format(amount)}';
  }
  return _cny.format(amount);
}

/// RMB shown beside a Hong Kong dollar amount. Empty when there is no rate
/// or the amount is zero.
String? rmbBeside(double hkd, double? hkdToCny, {bool signed = false}) {
  if (hkdToCny == null || hkd.abs() <= 0.004) return null;
  return '約 ${formatCny(hkd * hkdToCny, signed: signed)}';
}

String formatInputNumber(double value) {
  final text = value.toStringAsFixed(6);
  return text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}

double? parseUserNumber(String raw) {
  final text = raw.trim().replaceAll(',', '').replaceAll('，', '');
  if (text.isEmpty) return null;
  return double.tryParse(text);
}
