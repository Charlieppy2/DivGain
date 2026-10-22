import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/book.dart';
import 'portfolio_controller.dart';

final bookProvider = AsyncNotifierProvider<BookController, List<BookEntry>>(
  BookController.new,
);

class BookController extends AsyncNotifier<List<BookEntry>> {
  @override
  Future<List<BookEntry>> build() {
    return ref.read(databaseProvider).getBookEntries();
  }

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
    final trimmedCategory = category.trim();
    if (trimmedCategory.isEmpty) {
      throw const FormatException('請選擇分類');
    }
    final trimmedMethod = method.trim();
    if (trimmedMethod.isEmpty) {
      throw const FormatException('請選擇付款方式');
    }
    final database = ref.read(databaseProvider);
    final entry = BookEntry(
      id: id ?? 0,
      date: date,
      kind: kind,
      currency: currency,
      category: trimmedCategory,
      amount: amount,
      note: note.trim(),
      method: trimmedMethod,
    );
    if (id == null) {
      await database.insertBookEntry(entry);
    } else {
      await database.updateBookEntry(entry);
    }
    state = AsyncData(await database.getBookEntries());
  }

  Future<void> deleteEntry(int id) async {
    final database = ref.read(databaseProvider);
    await database.deleteBookEntry(id);
    state = AsyncData(await database.getBookEntries());
  }

  Future<void> reload() async {
    state = AsyncData(await ref.read(databaseProvider).getBookEntries());
  }
}

final walletFundsProvider =
    AsyncNotifierProvider<WalletFundsController, Map<String, double>>(
      WalletFundsController.new,
    );

class WalletFundsController extends AsyncNotifier<Map<String, double>> {
  @override
  Future<Map<String, double>> build() {
    return ref.read(databaseProvider).getWalletFunds();
  }

  Future<void> saveFund(String method, double amount) async {
    final trimmed = method.trim();
    if (trimmed.isEmpty || trimmed == '未填') {
      throw const FormatException('請選擇付款方式');
    }
    final database = ref.read(databaseProvider);
    await database.setWalletFund(trimmed, amount);
    state = AsyncData(await database.getWalletFunds());
  }

  Future<void> reload() async {
    state = AsyncData(await ref.read(databaseProvider).getWalletFunds());
  }
}

final bookLabelsProvider =
    AsyncNotifierProvider<BookLabelsController, BookLabels>(
      BookLabelsController.new,
    );

class BookLabelsController extends AsyncNotifier<BookLabels> {
  @override
  Future<BookLabels> build() {
    return ref.read(databaseProvider).getBookLabels();
  }

  Future<void> add({required String scope, required String name}) async {
    final database = ref.read(databaseProvider);
    await database.addBookLabel(scope: scope, name: name);
    state = AsyncData(await database.getBookLabels());
  }

  Future<void> rename({
    required String scope,
    required String from,
    required String to,
  }) async {
    final database = ref.read(databaseProvider);
    await database.renameBookLabel(scope: scope, from: from, to: to);
    state = AsyncData(await database.getBookLabels());
    await ref.read(bookProvider.notifier).reload();
    await ref.read(walletFundsProvider.notifier).reload();
  }
}
