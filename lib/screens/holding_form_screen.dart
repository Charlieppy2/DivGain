import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/stock_directory.dart';
import '../models/ledger.dart';
import '../state/portfolio_controller.dart';
import '../ui/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/hkd_rmb_text.dart';

class HoldingFormScreen extends ConsumerStatefulWidget {
  const HoldingFormScreen({super.key, this.holdingId});

  final int? holdingId;

  @override
  ConsumerState<HoldingFormScreen> createState() => _HoldingFormScreenState();
}

class _HoldingFormScreenState extends ConsumerState<HoldingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _symbolController = TextEditingController();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  var _market = Market.hk;
  var _saving = false;
  var _lookingUp = false;
  var _lookupStatus = NameLookupStatus.missing;
  var _applyingAutoName = false;
  var _nameIsManual = false;
  String? _autoName;
  var _applyingAutoPrice = false;
  var _priceIsManual = false;
  var _autoPrice = '';
  String? _priceNote;
  Timer? _lookupTimer;
  var _lookupGeneration = 0;

  @override
  void initState() {
    super.initState();
    final id = widget.holdingId;
    if (id != null) {
      final holding = ref.read(portfolioProvider).value?.summaryOf(id)?.holding;
      if (holding != null) {
        _market = holding.market;
        _symbolController.text = holding.symbol;
        _nameController.text = holding.name;
        _priceController.text = formatInputNumber(holding.currentPrice);
        _nameIsManual = holding.name.trim().isNotEmpty;
      }
    }
    _symbolController.addListener(_scheduleLookup);
    _nameController.addListener(_onNameEdited);
    _priceController.addListener(_onPriceEdited);
  }

  @override
  void dispose() {
    _lookupTimer?.cancel();
    _symbolController.removeListener(_scheduleLookup);
    _nameController.removeListener(_onNameEdited);
    _priceController.removeListener(_onPriceEdited);
    _symbolController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.holdingId != null;
    final typedPrice = parseUserNumber(_priceController.text);
    return Scaffold(
      appBar: AppBar(title: Text(editing ? '編輯股票' : '新增股票')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('市場', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<Market>(
              segments: const [
                ButtonSegment(value: Market.hk, label: Text('港股')),
                ButtonSegment(value: Market.us, label: Text('美股')),
              ],
              selected: {_market},
              onSelectionChanged: _saving
                  ? null
                  : (selection) {
                      setState(() => _market = selection.first);
                      _scheduleLookup();
                    },
            ),
            const SizedBox(height: 8),
            Text(
              _market == Market.hk ? '港股以港元計價。' : '美股以美元計價。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('holding-symbol'),
              controller: _symbolController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: '代碼',
                hintText: '例如 5 或 AAPL',
              ),
              validator: (value) {
                if (normalizeSymbol(_market, value ?? '').isEmpty) {
                  return '請輸入代碼';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('holding-name'),
              controller: _nameController,
              decoration: InputDecoration(
                labelText: '名稱（可留空）',
                helperText: _nameHelper,
                suffixIcon: _lookingUp
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
            ),
            const SizedBox(height: 12),
            RmbBeside(
              show: _market == Market.hk,
              amount: typedPrice,
              child: TextFormField(
                key: const Key('holding-price'),
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: '現價', helperText: _priceHelper),
                validator: (value) {
                  final price = parseUserNumber(value ?? '');
                  if (price == null) return '請輸入現價';
                  if (price < 0) return '現價不能是負數';
                  return null;
                },
              ),
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

  String? get _nameHelper {
    if (_lookingUp) return '正在查找名稱…';
    if (_lookupStatus == NameLookupStatus.unavailable) {
      return '暫時連不上，可以自己填名稱';
    }
    if (_lookupStatus == NameLookupStatus.missing &&
        normalizeSymbol(_market, _symbolController.text).isNotEmpty &&
        !_nameIsManual) {
      return '找不到這隻股票，可以自己填名稱';
    }
    if (_nameController.text.trim().isEmpty) return '輸入代碼後會自動填上';
    return null;
  }

  String? get _priceHelper {
    if (_lookingUp) return '正在查找收市價…';
    if (_priceNote != null) return _priceNote;
    return '會填上最近收市價，找不到可以自己填';
  }

  void _onNameEdited() {
    if (_applyingAutoName) return;
    final text = _nameController.text.trim();
    _nameIsManual = text.isNotEmpty && text != _autoName;
    if (text.isEmpty) _nameIsManual = false;
  }

  void _onPriceEdited() {
    if (_applyingAutoPrice) return;
    final text = _priceController.text.trim();
    _priceIsManual = text.isNotEmpty && text != _autoPrice;
    if (text.isEmpty) _priceIsManual = false;
    if (mounted) setState(() {});
  }

  void _scheduleLookup() {
    _lookupTimer?.cancel();
    _lookupTimer = Timer(const Duration(milliseconds: 350), () {
      _lookupNow();
    });
  }

  Future<void> _lookupNow() async {
    final generation = ++_lookupGeneration;
    final symbol = normalizeSymbol(_market, _symbolController.text);
    if (symbol.isEmpty) {
      if (mounted) {
        setState(() {
          _lookingUp = false;
          _lookupStatus = NameLookupStatus.missing;
        });
      }
      return;
    }
    setState(() => _lookingUp = true);
    final directory = ref.read(stockDirectoryProvider);
    final resultFuture = directory.lookup(_market, symbol);
    final priceFuture = directory.latestClose(_market, symbol);
    final result = await resultFuture;
    final latest = await priceFuture;
    if (!mounted || generation != _lookupGeneration) return;
    setState(() {
      _lookingUp = false;
      _lookupStatus = result.status;
      if (!_priceIsManual) {
        if (latest == null) {
          _priceNote = '找不到最近收市價，可以自己填';
        } else {
          _autoPrice = formatInputNumber(latest.price);
          _priceNote = '截至 ${formatDate(latest.date)} 收市價';
          _applyAutoPrice(_autoPrice);
        }
      }
      if (_nameIsManual) return;
      if (result.name == null) {
        if (_nameController.text == _autoName) {
          _applyAutoName('');
        }
        _autoName = null;
        return;
      }
      _autoName = result.name;
      _applyAutoName(result.name!);
    });
  }

  void _applyAutoPrice(String price) {
    _applyingAutoPrice = true;
    _priceController.text = price;
    _applyingAutoPrice = false;
  }

  void _applyAutoName(String name) {
    _applyingAutoName = true;
    _nameController.text = name;
    _applyingAutoName = false;
  }

  Future<void> _save() async {
    _lookupTimer?.cancel();
    await _lookupNow();
    if (!mounted || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(portfolioProvider.notifier)
          .saveHolding(
            id: widget.holdingId,
            market: _market,
            symbol: _symbolController.text,
            name: _nameController.text,
            currentPrice: parseUserNumber(_priceController.text)!,
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
}
