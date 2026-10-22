import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/book_math.dart';
import '../models/book.dart';
import '../state/book_controller.dart';
import '../ui/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/hkd_rmb_text.dart';
import 'book_entry_form_screen.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(bookProvider);
    final funds = ref.watch(walletFundsProvider);
    final labels = ref.watch(bookLabelsProvider);
    final waiting = book.isLoading || funds.isLoading || labels.isLoading;
    final failure = book.hasError
        ? book.error
        : funds.hasError
        ? funds.error
        : labels.hasError
        ? labels.error
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('錢包')),
      body: waiting
          ? const Center(child: CircularProgressIndicator())
          : failure != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('讀取失敗'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      ref.invalidate(bookProvider);
                      ref.invalidate(walletFundsProvider);
                      ref.invalidate(bookLabelsProvider);
                    },
                    child: const Text('重試'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _WalletCard(
                  entries: book.requireValue,
                  opening: funds.requireValue,
                  methods: labels.requireValue.methods,
                  onOpen: (line) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) =>
                            WalletHistoryScreen(method: line.method),
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }
}

Future<void> _editOpening(
  BuildContext context,
  WidgetRef ref,
  MethodBalance line,
) async {
  final amount = await showDialog<double>(
    context: context,
    builder: (context) =>
        _OpeningDialog(method: line.method, opening: line.opening),
  );
  if (amount == null || !context.mounted) return;
  try {
    await ref.read(walletFundsProvider.notifier).saveFund(line.method, amount);
  } on FormatException catch (error) {
    if (context.mounted) showMessage(context, error.message);
  }
}

class _OpeningDialog extends StatefulWidget {
  const _OpeningDialog({required this.method, required this.opening});

  final String method;
  final double opening;

  @override
  State<_OpeningDialog> createState() => _OpeningDialogState();
}

class _OpeningDialogState extends State<_OpeningDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.opening.abs() > 0.004
          ? formatInputNumber(widget.opening)
          : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      Navigator.of(context).pop(0.0);
      return;
    }
    final parsed = parseUserNumber(text);
    if (parsed == null) {
      showMessage(context, '請輸入金額');
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.method}的原有資金'),
      content: TextField(
        key: const Key('wallet-opening-amount'),
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: const InputDecoration(
          labelText: '金額',
          helperText: '這筆不會計入日結、月結或年結',
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('儲存')),
      ],
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.entries,
    required this.opening,
    required this.methods,
    required this.onOpen,
  });

  final List<BookEntry> entries;
  final Map<String, double> opening;
  final List<String> methods;
  final ValueChanged<MethodBalance> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = walletBalances(
      entries,
      opening: opening,
      methods: methods,
    );
    final total = lines.fold<double>(0, (sum, line) => sum + line.balance);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '結餘',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                HkdRmbText(
                  BookCurrency.hkd.market,
                  total,
                  signed: true,
                  alignEnd: true,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '原有資金加記賬結餘',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '支出會從對應錢包扣除。點一種錢包，可以看每筆進出。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            for (final line in lines)
              if (line.method != '未填' || line.balance.abs() > 0.004) ...[
                const Divider(height: 1),
                InkWell(
                  key: Key('wallet-method-${line.method}'),
                  onTap: () => onOpen(line),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.method,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (line.opening.abs() > 0.004)
                                Text(
                                  '原有 ${formatMoney(BookCurrency.hkd.market, line.opening)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        HkdRmbText(
                          BookCurrency.hkd.market,
                          line.balance,
                          signed: true,
                          alignEnd: true,
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: theme.colorScheme.outline,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class WalletHistoryScreen extends ConsumerWidget {
  const WalletHistoryScreen({super.key, required this.method});

  final String method;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(bookProvider);
    final funds = ref.watch(walletFundsProvider);
    final waiting = book.isLoading || funds.isLoading;
    final failure = book.hasError
        ? book.error
        : funds.hasError
        ? funds.error
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(method)),
      body: waiting
          ? const Center(child: CircularProgressIndicator())
          : failure != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('讀取失敗'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      ref.invalidate(bookProvider);
                      ref.invalidate(walletFundsProvider);
                    },
                    child: const Text('重試'),
                  ),
                ],
              ),
            )
          : _HistoryBody(
              method: method,
              entries: book.requireValue,
              opening: funds.requireValue,
              onEditOpening: method == '未填'
                  ? null
                  : () => _editOpening(
                      context,
                      ref,
                      MethodBalance(
                        method: method,
                        opening: funds.requireValue[method] ?? 0,
                        balance: methodBalance(
                          book.requireValue,
                          method,
                          opening: funds.requireValue,
                        ),
                      ),
                    ),
              onOpenEntry: (entry) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) =>
                        BookEntryFormScreen(entryId: entry.id),
                  ),
                );
              },
            ),
    );
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({
    required this.method,
    required this.entries,
    required this.opening,
    required this.onEditOpening,
    required this.onOpenEntry,
  });

  final String method;
  final List<BookEntry> entries;
  final Map<String, double> opening;
  final VoidCallback? onEditOpening;
  final ValueChanged<BookEntry> onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balance = methodBalance(entries, method, opening: opening);
    final history = entriesForWallet(entries, method);
    final openingAmount = opening[method] ?? 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  '結餘',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                HkdRmbText(
                  BookCurrency.hkd.market,
                  balance,
                  signed: true,
                  alignEnd: true,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (onEditOpening != null) ...[
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('wallet-opening'),
              onTap: onEditOpening,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('原有資金', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            '不會計入日結、月結或年結',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    HkdRmbText(
                      BookCurrency.hkd.market,
                      openingAmount,
                      signed: true,
                      alignEnd: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text('每筆進出', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: Text('還沒有進出')),
          )
        else
          for (final entry in history) ...[
            _HistoryTile(entry: entry, onTap: () => onOpenEntry(entry)),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.onTap});

  final BookEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signedAmount = entry.kind == BookKind.expense
        ? -entry.amount
        : entry.amount;
    final note = entry.note.trim();
    final details = [
      entry.kind.label,
      formatDate(entry.date),
      if (note.isNotEmpty) note,
    ].join('  ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('wallet-entry-${entry.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.category, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(details, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              HkdRmbText(
                entry.currency.market,
                signedAmount,
                signed: true,
                alignEnd: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
