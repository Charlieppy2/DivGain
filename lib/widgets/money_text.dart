import 'package:flutter/material.dart';

import '../models/ledger.dart';
import '../ui/format.dart';
import '../ui/gain_color.dart';

class MoneyText extends StatelessWidget {
  const MoneyText(
    this.market,
    this.amount, {
    super.key,
    this.signed = false,
    this.style,
  });

  final Market market;
  final double amount;
  final bool signed;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    return Text(
      formatMoney(market, amount, signed: signed),
      style: base.copyWith(
        color: signed ? GainColors.of(amount) : base.color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
