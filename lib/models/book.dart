import 'ledger.dart';

enum BookKind {
  income,
  expense;

  String get storageCode => name;

  String get label => switch (this) {
    BookKind.income => '收入',
    BookKind.expense => '支出',
  };

  static BookKind parse(String code) {
    return BookKind.values.firstWhere(
      (kind) => kind.storageCode == code,
      orElse: () => throw FormatException('未知記賬類型：$code'),
    );
  }
}

enum BookCurrency {
  hkd,
  usd;

  String get storageCode => name;

  String get label => switch (this) {
    BookCurrency.hkd => '港元',
    BookCurrency.usd => '美元',
  };

  Market get market => switch (this) {
    BookCurrency.hkd => Market.hk,
    BookCurrency.usd => Market.us,
  };

  static BookCurrency parse(String code) {
    return BookCurrency.values.firstWhere(
      (currency) => currency.storageCode == code,
      orElse: () => throw FormatException('未知貨幣：$code'),
    );
  }
}

const expenseCategories = ['飲食', '交通', '購物', '居住', '娛樂', '醫療', '其他'];
const incomeCategories = ['薪金', '獎金', '紅包', '其他'];
const paymentMethods = [
  '現金',
  '信用卡',
  '微信',
  '支付寶',
  'AlipayHK',
  'BOC Pay',
  '八達通',
  'PayMe',
  '轉數快',
  '其他',
];

List<String> categoriesFor(BookKind kind) {
  return kind == BookKind.income ? incomeCategories : expenseCategories;
}

class BookLabels {
  const BookLabels({
    required this.expense,
    required this.income,
    required this.methods,
  });

  final List<String> expense;
  final List<String> income;
  final List<String> methods;

  static const defaults = BookLabels(
    expense: expenseCategories,
    income: incomeCategories,
    methods: paymentMethods,
  );

  List<String> categoriesFor(BookKind kind) {
    return kind == BookKind.income ? income : expense;
  }

  List<String> forScope(String scope) {
    return switch (scope) {
      'income' => income,
      'method' => methods,
      _ => expense,
    };
  }
}

/// Rejects a blank name, the reserved wallet name, and duplicates.
String normalizeBookLabel(
  String scope,
  String raw,
  List<String> existing, {
  String? replacing,
}) {
  final name = raw.trim();
  if (name.isEmpty) {
    throw const FormatException('請輸入名稱');
  }
  if (scope == 'method' && name == '未填') {
    throw const FormatException('請換一個名稱');
  }
  if (name != replacing && existing.contains(name)) {
    throw const FormatException('這個名稱已經有了');
  }
  return name;
}

class BookEntry {
  BookEntry({
    required this.id,
    required DateTime date,
    required this.kind,
    required this.currency,
    required this.category,
    required this.amount,
    required this.note,
    this.method = '',
  }) : date = DateTime(date.year, date.month, date.day);

  final int id;
  final DateTime date;
  final BookKind kind;
  final BookCurrency currency;
  final String category;
  final double amount;
  final String note;
  final String method;
}
