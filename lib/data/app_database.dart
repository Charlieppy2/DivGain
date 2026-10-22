import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../logic/workbook_import.dart';
import '../models/book.dart';
import '../models/ledger.dart';

class AppDatabase {
  AppDatabase();

  AppDatabase.opened(this._db);

  @visibleForTesting
  static Future<AppDatabase> openInMemory() async {
    final opened = await openDatabase(
      inMemoryDatabasePath,
      version: 6,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return AppDatabase.opened(opened);
  }

  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final file = kIsWeb
        ? 'divgain.db'
        : p.join((await getApplicationDocumentsDirectory()).path, 'divgain.db');
    final opened = await openDatabase(
      file,
      version: 6,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    _db = opened;
    return opened;
  }

  Future<void> close() async {
    final existing = _db;
    if (existing == null) return;
    await existing.close();
    _db = null;
  }

  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE holdings ADD COLUMN price_as_of TEXT');
    }
    if (oldVersion < 3) {
      await _createBookEntries(db);
    }
    if (oldVersion >= 3 && oldVersion < 4) {
      await db.execute(
        "ALTER TABLE book_entries ADD COLUMN method TEXT NOT NULL DEFAULT ''",
      );
    }
    if (oldVersion < 5) {
      await _createWalletFunds(db);
    }
    if (oldVersion < 6) {
      await _createBookLabels(db);
      await _seedBookLabels(db);
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE holdings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        market TEXT NOT NULL,
        symbol TEXT NOT NULL,
        name TEXT NOT NULL DEFAULT '',
        current_price REAL NOT NULL,
        price_as_of TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE trades (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        holding_id INTEGER NOT NULL,
        trade_date TEXT NOT NULL,
        side TEXT NOT NULL,
        shares REAL NOT NULL,
        price REAL NOT NULL,
        fee REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (holding_id) REFERENCES holdings(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE dividends (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        holding_id INTEGER NOT NULL,
        dividend_date TEXT NOT NULL,
        amount REAL NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (holding_id) REFERENCES holdings(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_trades_holding ON trades(holding_id)');
    await db.execute(
      'CREATE INDEX idx_dividends_holding ON dividends(holding_id)',
    );
    await _createBookEntries(db);
    await _createWalletFunds(db);
    await _createBookLabels(db);
    await _seedBookLabels(db);
  }

  static Future<void> _createBookEntries(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS book_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_date TEXT NOT NULL,
        kind TEXT NOT NULL,
        currency TEXT NOT NULL,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        method TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  static Future<void> _createWalletFunds(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS wallet_funds (
        method TEXT PRIMARY KEY,
        amount REAL NOT NULL
      )
    ''');
  }

  static Future<void> _createBookLabels(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS book_labels (
        scope TEXT NOT NULL,
        name TEXT NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (scope, name)
      )
    ''');
  }

  static Future<void> _seedBookLabels(DatabaseExecutor db) async {
    Future<void> insertAll(String scope, List<String> names) async {
      for (var index = 0; index < names.length; index++) {
        await db.insert('book_labels', {
          'scope': scope,
          'name': names[index],
          'position': index,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }

    await insertAll('expense', expenseCategories);
    await insertAll('income', incomeCategories);
    await insertAll('method', paymentMethods);
  }

  Future<List<Holding>> getHoldings() async {
    final db = await database;
    final rows = await db.query('holdings');
    return rows.map(_holdingFromRow).toList();
  }

  Future<int> insertHolding(Holding holding) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return db.insert('holdings', {
      'market': holding.market.storageCode,
      'symbol': holding.symbol,
      'name': holding.name,
      'current_price': holding.currentPrice,
      'price_as_of': holding.priceAsOf == null
          ? null
          : storeDate(holding.priceAsOf!),
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateHolding(Holding holding) async {
    final db = await database;
    await db.update(
      'holdings',
      {
        'market': holding.market.storageCode,
        'symbol': holding.symbol,
        'name': holding.name,
        'current_price': holding.currentPrice,
        'price_as_of': holding.priceAsOf == null
            ? null
            : storeDate(holding.priceAsOf!),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [holding.id],
    );
  }

  Future<void> updateMarketPrice({
    required int id,
    required double price,
    required DateTime asOf,
  }) async {
    final db = await database;
    await db.update(
      'holdings',
      {
        'current_price': price,
        'price_as_of': storeDate(asOf),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteHolding(int id) async {
    final db = await database;
    await db.delete('holdings', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Trade>> getTrades() async {
    final db = await database;
    final rows = await db.query('trades');
    return rows.map(_tradeFromRow).toList();
  }

  Future<int> insertTrade(Trade trade) async {
    final db = await database;
    return db.insert('trades', {
      'holding_id': trade.holdingId,
      'trade_date': storeDate(trade.date),
      'side': trade.side.storageCode,
      'shares': trade.shares,
      'price': trade.price,
      'fee': trade.fee,
    });
  }

  Future<void> updateTrade(Trade trade) async {
    final db = await database;
    await db.update(
      'trades',
      {
        'holding_id': trade.holdingId,
        'trade_date': storeDate(trade.date),
        'side': trade.side.storageCode,
        'shares': trade.shares,
        'price': trade.price,
        'fee': trade.fee,
      },
      where: 'id = ?',
      whereArgs: [trade.id],
    );
  }

  Future<void> deleteTrade(int id) async {
    final db = await database;
    await db.delete('trades', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Dividend>> getDividends() async {
    final db = await database;
    final rows = await db.query('dividends');
    return rows.map(_dividendFromRow).toList();
  }

  Future<int> insertDividend(Dividend dividend) async {
    final db = await database;
    return db.insert('dividends', {
      'holding_id': dividend.holdingId,
      'dividend_date': storeDate(dividend.date),
      'amount': dividend.amount,
      'note': dividend.note,
    });
  }

  Future<void> updateDividend(Dividend dividend) async {
    final db = await database;
    await db.update(
      'dividends',
      {
        'holding_id': dividend.holdingId,
        'dividend_date': storeDate(dividend.date),
        'amount': dividend.amount,
        'note': dividend.note,
      },
      where: 'id = ?',
      whereArgs: [dividend.id],
    );
  }

  Future<void> deleteDividend(int id) async {
    final db = await database;
    await db.delete('dividends', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<BookEntry>> getBookEntries() async {
    final db = await database;
    final rows = await db.query('book_entries');
    return rows.map(_bookEntryFromRow).toList();
  }

  Future<int> insertBookEntry(BookEntry entry) async {
    final db = await database;
    return db.insert('book_entries', {
      'entry_date': storeDate(entry.date),
      'kind': entry.kind.storageCode,
      'currency': entry.currency.storageCode,
      'category': entry.category,
      'amount': entry.amount,
      'note': entry.note,
      'method': entry.method,
    });
  }

  Future<void> updateBookEntry(BookEntry entry) async {
    final db = await database;
    await db.update(
      'book_entries',
      {
        'entry_date': storeDate(entry.date),
        'kind': entry.kind.storageCode,
        'currency': entry.currency.storageCode,
        'category': entry.category,
        'amount': entry.amount,
        'note': entry.note,
        'method': entry.method,
      },
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<void> deleteBookEntry(int id) async {
    final db = await database;
    await db.delete('book_entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, double>> getWalletFunds() async {
    final db = await database;
    final rows = await db.query('wallet_funds');
    return {
      for (final row in rows)
        row['method']! as String: (row['amount']! as num).toDouble(),
    };
  }

  Future<void> setWalletFund(String method, double amount) async {
    final db = await database;
    if (amount.abs() <= 0.004) {
      await db.delete('wallet_funds', where: 'method = ?', whereArgs: [method]);
      return;
    }
    await db.insert('wallet_funds', {
      'method': method,
      'amount': amount,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<BookLabels> getBookLabels() async {
    final db = await database;
    final rows = await db.query('book_labels', orderBy: 'position ASC, name ASC');
    final expense = <String>[];
    final income = <String>[];
    final methods = <String>[];
    for (final row in rows) {
      final name = row['name']! as String;
      switch (row['scope']) {
        case 'income':
          income.add(name);
        case 'method':
          methods.add(name);
        default:
          expense.add(name);
      }
    }
    if (expense.isEmpty && income.isEmpty && methods.isEmpty) {
      return BookLabels.defaults;
    }
    return BookLabels(
      expense: expense.isEmpty ? expenseCategories : expense,
      income: income.isEmpty ? incomeCategories : income,
      methods: methods.isEmpty ? paymentMethods : methods,
    );
  }

  Future<void> addBookLabel({required String scope, required String name}) async {
    final db = await database;
    final existing = await getBookLabels();
    final label = normalizeBookLabel(scope, name, existing.forScope(scope));
    final rows = await db.query(
      'book_labels',
      columns: ['position'],
      where: 'scope = ?',
      whereArgs: [scope],
      orderBy: 'position DESC',
      limit: 1,
    );
    final position = rows.isEmpty ? 0 : (rows.first['position']! as int) + 1;
    await db.insert('book_labels', {
      'scope': scope,
      'name': label,
      'position': position,
    });
  }

  Future<void> renameBookLabel({
    required String scope,
    required String from,
    required String to,
  }) async {
    final previous = from.trim();
    final db = await database;
    final existing = await getBookLabels();
    final label = normalizeBookLabel(
      scope,
      to,
      existing.forScope(scope),
      replacing: previous,
    );
    if (label == previous) return;
    await db.transaction((txn) async {
      final updated = await txn.update(
        'book_labels',
        {'name': label},
        where: 'scope = ? AND name = ?',
        whereArgs: [scope, previous],
      );
      if (updated == 0) {
        throw const FormatException('找不到這個選項');
      }
      if (scope == 'method') {
        await txn.update(
          'book_entries',
          {'method': label},
          where: 'method = ?',
          whereArgs: [previous],
        );
        await txn.update(
          'wallet_funds',
          {'method': label},
          where: 'method = ?',
          whereArgs: [previous],
        );
      } else {
        await txn.update(
          'book_entries',
          {'category': label},
          where: 'kind = ? AND category = ?',
          whereArgs: [scope, previous],
        );
      }
    });
  }

  Future<void> replaceWithImport({
    required List<BookEntry> entries,
    required Map<String, double> opening,
    required List<ImportedStock> stocks,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete('book_entries');
      await txn.delete('wallet_funds');
      await txn.delete('dividends');
      await txn.delete('trades');
      await txn.delete('holdings');
      for (final entry in entries) {
        await txn.insert('book_entries', {
          'entry_date': storeDate(entry.date),
          'kind': entry.kind.storageCode,
          'currency': entry.currency.storageCode,
          'category': entry.category,
          'amount': entry.amount,
          'note': entry.note,
          'method': entry.method,
        });
      }
      for (final item in opening.entries) {
        if (item.value.abs() <= 0.004) continue;
        await txn.insert('wallet_funds', {
          'method': item.key,
          'amount': item.value,
        });
        await _ensureBookLabel(txn, 'method', item.key);
      }
      for (final entry in entries) {
        await _ensureBookLabel(txn, entry.kind.storageCode, entry.category);
        await _ensureBookLabel(txn, 'method', entry.method);
      }
      for (final stock in stocks) {
        final holdingId = await txn.insert('holdings', {
          'market': stock.holding.market.storageCode,
          'symbol': stock.holding.symbol,
          'name': stock.holding.name,
          'current_price': stock.holding.currentPrice,
          'price_as_of': null,
          'created_at': now,
          'updated_at': now,
        });
        for (final trade in stock.trades) {
          await txn.insert('trades', {
            'holding_id': holdingId,
            'trade_date': storeDate(trade.date),
            'side': trade.side.storageCode,
            'shares': trade.shares,
            'price': trade.price,
            'fee': trade.fee,
          });
        }
        for (final dividend in stock.dividends) {
          await txn.insert('dividends', {
            'holding_id': holdingId,
            'dividend_date': storeDate(dividend.date),
            'amount': dividend.amount,
            'note': dividend.note,
          });
        }
      }
    });
  }
}

Future<void> _ensureBookLabel(
  Transaction txn,
  String scope,
  String raw,
) async {
  final name = raw.trim();
  if (name.isEmpty || name == '未填') return;
  final existing = await txn.query(
    'book_labels',
    where: 'scope = ? AND name = ?',
    whereArgs: [scope, name],
    limit: 1,
  );
  if (existing.isNotEmpty) return;
  final rows = await txn.query(
    'book_labels',
    columns: ['position'],
    where: 'scope = ?',
    whereArgs: [scope],
    orderBy: 'position DESC',
    limit: 1,
  );
  final position = rows.isEmpty ? 0 : (rows.first['position']! as int) + 1;
  await txn.insert('book_labels', {
    'scope': scope,
    'name': name,
    'position': position,
  });
}

Holding _holdingFromRow(Map<String, Object?> row) {
  return Holding(
    id: row['id']! as int,
    market: Market.parse(row['market']! as String),
    symbol: row['symbol']! as String,
    name: row['name']! as String,
    currentPrice: (row['current_price']! as num).toDouble(),
    priceAsOf: row['price_as_of'] == null
        ? null
        : parseDate(row['price_as_of']! as String),
  );
}

Trade _tradeFromRow(Map<String, Object?> row) {
  return Trade(
    id: row['id']! as int,
    holdingId: row['holding_id']! as int,
    date: parseDate(row['trade_date']! as String),
    side: TradeSide.parse(row['side']! as String),
    shares: (row['shares']! as num).toDouble(),
    price: (row['price']! as num).toDouble(),
    fee: (row['fee']! as num).toDouble(),
  );
}

Dividend _dividendFromRow(Map<String, Object?> row) {
  return Dividend(
    id: row['id']! as int,
    holdingId: row['holding_id']! as int,
    date: parseDate(row['dividend_date']! as String),
    amount: (row['amount']! as num).toDouble(),
    note: row['note']! as String,
  );
}

BookEntry _bookEntryFromRow(Map<String, Object?> row) {
  return BookEntry(
    id: row['id']! as int,
    date: parseDate(row['entry_date']! as String),
    kind: BookKind.parse(row['kind']! as String),
    currency: BookCurrency.parse(row['currency']! as String),
    category: row['category']! as String,
    amount: (row['amount']! as num).toDouble(),
    note: row['note']! as String,
    method: row['method'] as String? ?? '',
  );
}
