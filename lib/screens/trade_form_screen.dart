import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/portfolio_math.dart';
import '../models/ledger.dart';
import '../state/portfolio_controller.dart';
import '../ui/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/hkd_rmb_text.dart';

class TradeFormScreen extends ConsumerStatefulWidget {
  const TradeFormScreen({super.key, required this.holdingId, this.tradeId});

  final int holdingId;
  final int? tradeId;

  @override
  ConsumerState<TradeFormScreen> createState() => _TradeFormScreenState();
}

class _TradeFormScreenState extends ConsumerState<TradeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sharesController = TextEditingController();
  final _priceController = TextEditingController();
  final _feeController = TextEditingController();
  var _side = TradeSide.buy;
  var _date = DateTime.now();
  var _saving = false;
  var _ready = false;
  var _lookingUpPrice = false;
  var _priceNote = '會按日期填上收市價';
  var _priceGeneration = 0;
  var _priceLookupStarted = false;
  var _suppressPriceListener = false;

  @override
  void initState() {
    super.initState();
    _date = DateTime(_date.year, _date.month, _date.day);
    final tradeId = widget.tradeId;
    if (tradeId != null) {
      final trades = ref.read(portfolioProvider).value?.tradesOf(widget.holdingId);
      final trade = trades?.where((item) => item.id == tradeId).firstOrNull;
      if (trade != null) {
        _side = trade.side;
        _date = trade.date;
        _sharesController.text = formatInputNumber(trade.shares);
        _priceController.text = formatInputNumber(trade.price);
        if (trade.fee != 0) {
          _feeController.text = formatInputNumber(trade.fee);
        }
      }
    }
    _ready = true;
    _priceController.addListener(_onPriceChanged);
  }

  void _onPriceChanged() {
    if (_suppressPriceListener || !mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _priceController.removeListener(_onPriceChanged);
    _sharesController.dispose();
    _priceController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(portfolioProvider).value?.summaryOf(widget.holdingId);
    if (!_ready || summary == null) {
      return const Scaffold(body: Center(child: Text('找不到這隻股票')));
    }
    if (widget.tradeId == null && !_priceLookupStarted) {
      _priceLookupStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _lookupPrice();
      });
    }
    final market = summary.holding.market;
    final typedPrice = parseUserNumber(_priceController.text);
    return Scaffold(
      appBar: AppBar(title: Text(widget.tradeId == null ? '記一筆買賣' : '編輯買賣')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<TradeSide>(
              segments: const [
                ButtonSegment(value: TradeSide.buy, label: Text('買入')),
                ButtonSegment(value: TradeSide.sell, label: Text('賣出')),
              ],
              selected: {_side},
              onSelectionChanged: _saving
                  ? null
                  : (selection) => setState(() => _side = selection.first),
            ),
            const SizedBox(height: 16),
            _DateTile(
              date: _date,
              enabled: !_saving,
              onPick: _pickDate,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _sharesController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '股數'),
              validator: (value) {
                final shares = parseUserNumber(value ?? '');
                if (shares == null) return '請輸入股數';
                if (shares <= 0) return '股數必須大於 0';
                return null;
              },
            ),
            const SizedBox(height: 12),
            RmbBeside(
              show: market == Market.hk,
              amount: typedPrice,
              child: TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '單價（${market.currencyLabel}）',
                  helperText: _priceNote,
                  suffixIcon: _lookingUpPrice
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                validator: (value) {
                  final price = parseUserNumber(value ?? '');
                  if (price == null) return '請輸入單價';
                  if (price < 0) return '單價不能是負數';
                  return null;
                },
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _feeController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '手續費（可留空）'),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return null;
                final fee = parseUserNumber(text);
                if (fee == null) return '請輸入有效手續費';
                if (fee < 0) return '手續費不能是負數';
                return null;
              },
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
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
      await _lookupPrice();
    }
  }

  Future<void> _lookupPrice() async {
    final summary = ref.read(portfolioProvider).value?.summaryOf(widget.holdingId);
    if (summary == null || !mounted) return;
    final generation = ++_priceGeneration;
    setState(() => _lookingUpPrice = true);
    final quote = await ref
        .read(stockDirectoryProvider)
        .closeOn(summary.holding.market, summary.holding.symbol, _date);
    if (!mounted || generation != _priceGeneration) return;
    setState(() {
      _lookingUpPrice = false;
      if (quote == null) {
        _priceNote = '找不到這天的收市價，可以自己填';
        return;
      }
      _suppressPriceListener = true;
      _priceController.text = formatInputNumber(quote.price);
      _suppressPriceListener = false;
      _priceNote = quote.usedEarlierSession
          ? '當日休市，沿用 ${formatDate(quote.date)} 收市價'
          : '${formatDate(quote.date)} 收市價';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final fee = parseUserNumber(_feeController.text) ?? 0;
    setState(() => _saving = true);
    try {
      await ref.read(portfolioProvider.notifier).saveTrade(
        id: widget.tradeId,
        holdingId: widget.holdingId,
        date: _date,
        side: _side,
        shares: parseUserNumber(_sharesController.text)!,
        price: parseUserNumber(_priceController.text)!,
        fee: fee,
      );
      if (mounted) Navigator.of(context).pop();
    } on ShareShortage catch (error) {
      if (mounted) showMessage(context, error.message);
    } catch (_) {
      if (mounted) showMessage(context, '儲存失敗');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.date,
    required this.enabled,
    required this.onPick,
  });

  final DateTime date;
  final bool enabled;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('日期'),
      subtitle: Text(formatDate(date)),
      trailing: const Icon(Icons.calendar_today_outlined),
      onTap: enabled ? onPick : null,
    );
  }
}
