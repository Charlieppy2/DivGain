enum Market {
  hk,
  us;

  String get storageCode => name;

  String get label => switch (this) {
    Market.hk => '港股',
    Market.us => '美股',
  };

  String get currencyLabel => switch (this) {
    Market.hk => '港元',
    Market.us => '美元',
  };

  static Market parse(String code) {
    return Market.values.firstWhere(
      (market) => market.storageCode == code,
      orElse: () => throw FormatException('未知市場：$code'),
    );
  }
}

/// Pads numeric Hong Kong codes to 5 digits (`5` becomes `00005`).
String normalizeSymbol(Market market, String raw) {
  var symbol = raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  if (market == Market.hk) {
    symbol = symbol.replaceAll(RegExp(r'\.HK$'), '');
    if (RegExp(r'^\d{1,5}$').hasMatch(symbol)) {
      symbol = symbol.padLeft(5, '0');
    }
  }
  return symbol;
}

class Holding {
  const Holding({
    required this.id,
    required this.market,
    required this.symbol,
    required this.name,
    required this.currentPrice,
    this.priceAsOf,
  });

  final int id;
  final Market market;
  final String symbol;
  final String name;
  final double currentPrice;
  final DateTime? priceAsOf;
}

enum TradeSide {
  buy,
  sell;

  String get storageCode => name;

  String get label => switch (this) {
    TradeSide.buy => '買入',
    TradeSide.sell => '賣出',
  };

  static TradeSide parse(String code) {
    return TradeSide.values.firstWhere(
      (side) => side.storageCode == code,
      orElse: () => throw FormatException('未知買賣方向：$code'),
    );
  }
}

class Trade {
  Trade({
    required this.id,
    required this.holdingId,
    required DateTime date,
    required this.side,
    required this.shares,
    required this.price,
    required this.fee,
  }) : date = DateTime(date.year, date.month, date.day);

  final int id;
  final int holdingId;
  final DateTime date;
  final TradeSide side;
  final double shares;
  final double price;
  final double fee;
}

class Dividend {
  Dividend({
    required this.id,
    required this.holdingId,
    required DateTime date,
    required this.amount,
    required this.note,
  }) : date = DateTime(date.year, date.month, date.day);

  final int id;
  final int holdingId;
  final DateTime date;
  final double amount;
  final String note;
}

String storeDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

DateTime parseDate(String value) {
  final parts = value.split('-');
  if (parts.length != 3) {
    throw FormatException('日期格式不正確：$value');
  }
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}
