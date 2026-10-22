import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ledger.dart';
import '../state/portfolio_controller.dart';
import '../ui/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/hkd_rmb_text.dart';

class DividendFormScreen extends ConsumerStatefulWidget {
  const DividendFormScreen({
    super.key,
    required this.holdingId,
    this.dividendId,
  });

  final int holdingId;
  final int? dividendId;

  @override
  ConsumerState<DividendFormScreen> createState() => _DividendFormScreenState();
}

class _DividendFormScreenState extends ConsumerState<DividendFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  var _date = DateTime.now();
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _date = DateTime(_date.year, _date.month, _date.day);
    final dividendId = widget.dividendId;
    if (dividendId != null) {
      final dividends = ref
          .read(portfolioProvider)
          .value
          ?.dividendsOf(widget.holdingId);
      final dividend = dividends?.where((item) => item.id == dividendId).firstOrNull;
      if (dividend != null) {
        _date = dividend.date;
        _amountController.text = formatInputNumber(dividend.amount);
        _noteController.text = dividend.note;
      }
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
    final summary = ref.watch(portfolioProvider).value?.summaryOf(widget.holdingId);
    if (summary == null) {
      return const Scaffold(body: Center(child: Text('找不到這隻股票')));
    }
    final amount = parseUserNumber(_amountController.text);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.dividendId == null ? '記一筆股息' : '編輯股息'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('日期'),
              subtitle: Text(formatDate(_date)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _saving ? null : _pickDate,
            ),
            const SizedBox(height: 12),
            RmbBeside(
              show: summary.holding.market == Market.hk,
              amount: amount,
              child: TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '實收金額（${summary.holding.market.currencyLabel}）',
                ),
                validator: (value) {
                  final parsed = parseUserNumber(value ?? '');
                  if (parsed == null) return '請輸入金額';
                  if (parsed <= 0) return '金額必須大於 0';
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
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1980),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(portfolioProvider.notifier).saveDividend(
        id: widget.dividendId,
        holdingId: widget.holdingId,
        date: _date,
        amount: parseUserNumber(_amountController.text)!,
        note: _noteController.text,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) showMessage(context, '儲存失敗');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
