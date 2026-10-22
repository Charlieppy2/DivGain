import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/book_math.dart';
import '../models/book.dart';
import '../state/book_controller.dart';
import '../ui/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/hkd_rmb_text.dart';

class BookEntryFormScreen extends ConsumerStatefulWidget {
  const BookEntryFormScreen({super.key, this.entryId, this.initialDate});

  final int? entryId;
  final DateTime? initialDate;

  @override
  ConsumerState<BookEntryFormScreen> createState() =>
      _BookEntryFormScreenState();
}

class _BookEntryFormScreenState extends ConsumerState<BookEntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  var _kind = BookKind.expense;
  var _category = expenseCategories.first;
  var _method = paymentMethods.first;
  late DateTime _date;
  var _saving = false;
  var _ready = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDate ?? DateTime.now();
    _date = DateTime(initial.year, initial.month, initial.day);
    final entryId = widget.entryId;
    if (entryId == null) {
      _ready = true;
    } else {
      final entry = ref
          .read(bookProvider)
          .value
          ?.where((item) => item.id == entryId)
          .firstOrNull;
      if (entry != null) {
        _kind = entry.kind;
        _category = entry.category;
        if (entry.method.isNotEmpty) _method = entry.method;
        _date = entry.date;
        _amountController.text = formatInputNumber(entry.amount);
        _noteController.text = entry.note;
      }
      _ready = true;
    }
    _amountController.addListener(_onAmountChanged);
  }

  void _onAmountChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(bookProvider);
    final funds = ref.watch(walletFundsProvider);
    final labels =
        ref.watch(bookLabelsProvider).asData?.value ?? BookLabels.defaults;
    final editing = widget.entryId != null;
    final existing = editing
        ? book.value?.where((item) => item.id == widget.entryId).firstOrNull
        : null;
    if (!_ready || (editing && existing == null)) {
      return const Scaffold(body: Center(child: Text('找不到這筆記賬')));
    }
    final hkdAmount = parseUserNumber(_amountController.text);
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? '編輯記賬' : '記一筆'),
        actions: [
          if (editing)
            IconButton(
              tooltip: '刪除',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<BookKind>(
                segments: const [
                  ButtonSegment(value: BookKind.expense, label: Text('支出')),
                  ButtonSegment(value: BookKind.income, label: Text('收入')),
                ],
                selected: {_kind},
                onSelectionChanged: _saving
                    ? null
                    : (selection) => _setKind(selection.first),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('日期'),
                subtitle: Text(formatDate(_date)),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: _saving ? null : _pickDate,
              ),
              const SizedBox(height: 8),
              _LabelMenu(
                label: '分類',
                value: _category,
                options: _withCurrent(labels.categoriesFor(_kind), _category),
                dropdownKey: 'book-category',
                addKey: 'book-add-category',
                renameKey: 'book-rename-category',
                enabled: !_saving,
                onChanged: (value) => setState(() => _category = value),
                onAdd: () => _addLabel(
                  scope: _kind.storageCode,
                  title: '新增分類',
                  select: (name) => _category = name,
                ),
                onRename: () => _renameLabel(
                  scope: _kind.storageCode,
                  title: '改分類名稱',
                  current: _category,
                  select: (name) => _category = name,
                ),
              ),
              const SizedBox(height: 16),
              _LabelMenu(
                label: _kind == BookKind.expense ? '從錢包扣除' : '存入錢包',
                value: _method,
                options: _withCurrent(labels.methods, _method),
                dropdownKey: 'book-method',
                addKey: 'book-add-method',
                renameKey: 'book-rename-method',
                enabled: !_saving,
                onChanged: (value) => setState(() => _method = value),
                onAdd: () => _addLabel(
                  scope: 'method',
                  title: '新增錢包',
                  select: (name) => _method = name,
                ),
                onRename: () => _renameLabel(
                  scope: 'method',
                  title: '改錢包名稱',
                  current: _method,
                  select: (name) => _method = name,
                ),
              ),
              if (funds.asData != null)
                _WalletPreview(
                  current: methodBalance(
                    book.value ?? const [],
                    _method,
                    opening: funds.requireValue,
                    excludeEntryId: widget.entryId,
                  ),
                  amount: hkdAmount,
                  expense: _kind == BookKind.expense,
                ),
              const SizedBox(height: 12),
              RmbBeside(
                show: true,
                amount: hkdAmount,
                child: TextFormField(
                  key: const Key('book-amount'),
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '金額'),
                  validator: (value) {
                    final amount = parseUserNumber(value ?? '');
                    if (amount == null) return '請輸入金額';
                    if (amount <= 0) return '金額必須大於 0';
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: '備註（可留空）'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('儲存'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setKind(BookKind kind) {
    final categories =
        (ref.read(bookLabelsProvider).asData?.value ?? BookLabels.defaults)
            .categoriesFor(kind);
    setState(() {
      _kind = kind;
      if (categories.isNotEmpty && !categories.contains(_category)) {
        _category = categories.first;
      }
    });
  }

  Future<void> _addLabel({
    required String scope,
    required String title,
    required void Function(String name) select,
  }) async {
    final entered = await askForName(context, title: title);
    if (entered == null || !mounted) return;
    try {
      await ref.read(bookLabelsProvider.notifier).add(scope: scope, name: entered);
      if (mounted) setState(() => select(entered.trim()));
    } on FormatException catch (error) {
      if (mounted) showMessage(context, error.message);
    }
  }

  Future<void> _renameLabel({
    required String scope,
    required String title,
    required String current,
    required void Function(String name) select,
  }) async {
    final entered = await askForName(context, title: title, initial: current);
    if (entered == null || !mounted) return;
    try {
      await ref
          .read(bookLabelsProvider.notifier)
          .rename(scope: scope, from: current, to: entered);
      if (mounted) setState(() => select(entered.trim()));
    } on FormatException catch (error) {
      if (mounted) showMessage(context, error.message);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1980),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(bookProvider.notifier)
          .saveEntry(
            id: widget.entryId,
            date: _date,
            kind: _kind,
            currency: BookCurrency.hkd,
            category: _category,
            amount: parseUserNumber(_amountController.text)!,
            note: _noteController.text,
            method: _method,
          );
      if (mounted) Navigator.of(context).pop();
    } on FormatException catch (error) {
      if (mounted) showMessage(context, error.message);
    } catch (_) {
      if (mounted) showMessage(context, '儲存失敗');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final entryId = widget.entryId;
    if (entryId == null) return;
    final confirmed = await confirmDelete(context, '刪除這筆記賬？');
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(bookProvider.notifier).deleteEntry(entryId);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) showMessage(context, '刪除失敗');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _WalletPreview extends StatelessWidget {
  const _WalletPreview({
    required this.current,
    required this.amount,
    required this.expense,
  });

  final double current;
  final double? amount;
  final bool expense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typed = amount;
    final after = typed == null || typed <= 0
        ? null
        : current + (expense ? -typed : typed);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          _PreviewLine(label: '現有', amount: current),
          if (after != null)
            _PreviewLine(label: expense ? '扣除後' : '存入後', amount: after),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              expense ? '儲存後會從這個錢包扣走' : '儲存後會存入這個錢包',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          HkdRmbText(
            BookCurrency.hkd.market,
            amount,
            signed: true,
            alignEnd: true,
          ),
        ],
      ),
    );
  }
}

List<String> _withCurrent(List<String> options, String current) {
  if (current.isEmpty || options.contains(current)) return options;
  return [current, ...options];
}

class _LabelMenu extends StatelessWidget {
  const _LabelMenu({
    required this.label,
    required this.value,
    required this.options,
    required this.dropdownKey,
    required this.addKey,
    required this.renameKey,
    required this.enabled,
    required this.onChanged,
    required this.onAdd,
    required this.onRename,
  });

  final String label;
  final String value;
  final List<String> options;
  final String dropdownKey;
  final String addKey;
  final String renameKey;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onAdd;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final selected = options.contains(value) ? value : options.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        KeyedSubtree(
          key: ValueKey('$dropdownKey-$selected'),
          child: DropdownButtonFormField<String>(
            key: Key(dropdownKey),
            initialValue: selected,
            isExpanded: true,
            menuMaxHeight: 320,
            decoration: const InputDecoration(),
            items: [
              for (final option in options)
                DropdownMenuItem(value: option, child: Text(option)),
            ],
            onChanged: enabled
                ? (next) {
                    if (next != null) onChanged(next);
                  }
                : null,
          ),
        ),
        Row(
          children: [
            TextButton(
              key: Key(addKey),
              onPressed: enabled ? onAdd : null,
              child: const Text('新增'),
            ),
            TextButton(
              key: Key(renameKey),
              onPressed: enabled ? onRename : null,
              child: const Text('改名'),
            ),
          ],
        ),
      ],
    );
  }
}
