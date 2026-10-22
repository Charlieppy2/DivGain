import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ledger.dart';
import '../state/portfolio_controller.dart';
import '../ui/format.dart';
import 'money_text.dart';

/// Hong Kong dollar amount with the renminbi equivalent fixed on its right.
class RmbBeside extends ConsumerWidget {
  const RmbBeside({
    super.key,
    required this.show,
    required this.amount,
    required this.child,
  });

  final bool show;
  final double? amount;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!show) return child;
    final rate = ref.watch(hkdCnyProvider);
    final value = rate.asData?.value;
    final text = rate.isLoading
        ? '換算中'
        : value == null
        ? '未能換算'
        : (rmbBeside(amount ?? 0, value) ?? '—');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: child),
        const SizedBox(width: 8),
        SizedBox(
          width: 136,
          child: InputDecorator(
            decoration: const InputDecoration(labelText: '人民幣'),
            child: SizedBox(
              height: 24,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(text, key: const Key('rmb-beside')),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class HkdRmbText extends ConsumerWidget {
  const HkdRmbText(
    this.market,
    this.amount, {
    super.key,
    this.signed = false,
    this.style,
    this.alignEnd = false,
  });

  final Market market;
  final double amount;
  final bool signed;
  final TextStyle? style;
  final bool alignEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rate = ref.watch(hkdCnyProvider).asData?.value;
    final caption = market == Market.hk ? rmbBeside(amount, rate, signed: signed) : null;
    final money = MoneyText(market, amount, signed: signed, style: style);
    if (caption == null) return money;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        money,
        Text(caption, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
