import '../models/book.dart';

enum BookClose {
  day,
  month,
  year;

  String get label => switch (this) {
    BookClose.day => '日結',
    BookClose.month => '月結',
    BookClose.year => '年結',
  };
}

class CurrencyMonth {
  const CurrencyMonth({
    required this.currency,
    required this.income,
    required this.expense,
  });

  final BookCurrency currency;
  final double income;
  final double expense;

  double get balance => income - expense;

  bool get hasActivity => income.abs() > 0.0001 || expense.abs() > 0.0001;
}

class EntryGroup {
  const EntryGroup({required this.date, required this.entries});

  final DateTime date;
  final List<BookEntry> entries;
}

class MethodBalance {
  const MethodBalance({
    required this.method,
    required this.balance,
    this.opening = 0,
  });

  final String method;
  final double balance;
  final double opening;
}

/// All-time Hong Kong dollar balance for each payment method.
/// Income adds, expense subtracts, and [opening] is money already on hand.
/// Empty methods are listed as 未填. Opening money is not added to 未填.
List<MethodBalance> walletBalances(
  List<BookEntry> entries, {
  Map<String, double> opening = const {},
  List<String>? methods,
}) {
  final totals = <String, double>{};
  for (final entry in entries) {
    if (entry.currency != BookCurrency.hkd) continue;
    final method = entry.method.trim().isEmpty ? '未填' : entry.method.trim();
    final signed = entry.kind == BookKind.expense ? -entry.amount : entry.amount;
    totals[method] = (totals[method] ?? 0) + signed;
  }
  final named = methods ?? paymentMethods;
  final lines = <MethodBalance>[
    for (final method in named)
      MethodBalance(
        method: method,
        opening: opening[method] ?? 0,
        balance: (totals.remove(method) ?? 0) + (opening[method] ?? 0),
      ),
  ];
  final extras = totals.keys.toList()..sort();
  for (final method in extras) {
    lines.add(MethodBalance(method: method, balance: totals[method] ?? 0));
  }
  return lines;
}

/// Balance of one wallet. [excludeEntryId] leaves out the entry being edited
/// so the old amount is not counted twice.
double methodBalance(
  List<BookEntry> entries,
  String method, {
  Map<String, double> opening = const {},
  int? excludeEntryId,
}) {
  final source = excludeEntryId == null
      ? entries
      : [
          for (final entry in entries)
            if (entry.id != excludeEntryId) entry,
        ];
  for (final line in walletBalances(source, opening: opening)) {
    if (line.method == method) return line.balance;
  }
  return 0;
}

/// Hong Kong dollar entries that belong to one wallet, newest first.
/// An empty method is the 未填 wallet.
List<BookEntry> entriesForWallet(List<BookEntry> entries, String method) {
  return _sortedNewest(
    entries.where((entry) {
      if (entry.currency != BookCurrency.hkd) return false;
      final name = entry.method.trim().isEmpty ? '未填' : entry.method.trim();
      return name == method;
    }),
  );
}

bool isSameMonth(DateTime date, DateTime month) {
  return date.year == month.year && date.month == month.month;
}

bool inClose(DateTime date, BookClose close, DateTime anchor) {
  return switch (close) {
    BookClose.day =>
      date.year == anchor.year &&
          date.month == anchor.month &&
          date.day == anchor.day,
    BookClose.month => date.year == anchor.year && date.month == anchor.month,
    BookClose.year => date.year == anchor.year,
  };
}

DateTime shiftClose(DateTime anchor, BookClose close, int delta) {
  return switch (close) {
    BookClose.day => DateTime(anchor.year, anchor.month, anchor.day + delta),
    BookClose.month => DateTime(anchor.year, anchor.month + delta),
    BookClose.year => DateTime(anchor.year + delta),
  };
}

String closeTitle(DateTime anchor, BookClose close) {
  return switch (close) {
    BookClose.day => '${anchor.year}年${anchor.month}月${anchor.day}日',
    BookClose.month => '${anchor.year}年${anchor.month}月',
    BookClose.year => '${anchor.year}年',
  };
}

String emptyCloseLabel(BookClose close) {
  return switch (close) {
    BookClose.day => '這天還沒有記賬',
    BookClose.month => '這個月還沒有記賬',
    BookClose.year => '今年還沒有記賬',
  };
}

String previousCloseLabel(BookClose close) {
  return switch (close) {
    BookClose.day => '上一天',
    BookClose.month => '上個月',
    BookClose.year => '上一年',
  };
}

String nextCloseLabel(BookClose close) {
  return switch (close) {
    BookClose.day => '下一天',
    BookClose.month => '下個月',
    BookClose.year => '下一年',
  };
}

List<BookEntry> _sortedNewest(Iterable<BookEntry> entries) {
  return entries.toList()..sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    return b.id.compareTo(a.id);
  });
}

/// Sunday-first cells for [month], with blanks before the 1st and after the last day.
List<DateTime?> monthCalendarDays(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final leading = first.weekday % 7;
  final count = DateTime(month.year, month.month + 1, 0).day;
  final cells = <DateTime?>[
    for (var index = 0; index < leading; index++) null,
    for (var day = 1; day <= count; day++) DateTime(month.year, month.month, day),
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return cells;
}

List<BookEntry> entriesInMonth(List<BookEntry> entries, DateTime month) {
  return entriesInClose(entries, BookClose.month, month);
}

List<BookEntry> entriesInClose(
  List<BookEntry> entries,
  BookClose close,
  DateTime anchor,
) {
  return _sortedNewest(
    entries.where((entry) => inClose(entry.date, close, anchor)),
  );
}

CurrencyMonth summarizeCurrencyMonth(
  List<BookEntry> entries,
  BookCurrency currency,
  DateTime month,
) {
  return summarizeClose(entries, currency, BookClose.month, month);
}

CurrencyMonth summarizeClose(
  List<BookEntry> entries,
  BookCurrency currency,
  BookClose close,
  DateTime anchor,
) {
  var income = 0.0;
  var expense = 0.0;
  for (final entry in entries) {
    if (!inClose(entry.date, close, anchor) || entry.currency != currency) {
      continue;
    }
    if (entry.kind == BookKind.income) {
      income += entry.amount;
    } else {
      expense += entry.amount;
    }
  }
  return CurrencyMonth(currency: currency, income: income, expense: expense);
}

List<EntryGroup> groupByDay(List<BookEntry> entries) {
  return _group(entries, (date) => DateTime(date.year, date.month, date.day));
}

List<EntryGroup> groupByMonth(List<BookEntry> entries) {
  return _group(entries, (date) => DateTime(date.year, date.month));
}

List<EntryGroup> _group(
  List<BookEntry> entries,
  DateTime Function(DateTime date) keyOf,
) {
  final groups = <EntryGroup>[];
  for (final entry in _sortedNewest(entries)) {
    final key = keyOf(entry.date);
    if (groups.isEmpty || groups.last.date != key) {
      groups.add(EntryGroup(date: key, entries: [entry]));
    } else {
      groups.last.entries.add(entry);
    }
  }
  return groups;
}
