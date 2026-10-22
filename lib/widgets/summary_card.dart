import 'package:flutter/material.dart';

import '../logic/portfolio_math.dart';
import 'money_text.dart';

class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.summary});

  final CurrencySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final market = summary.market;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MarketPill(label: market.label),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('市值', style: theme.textTheme.labelMedium?.copyWith(color: muted)),
                    const SizedBox(height: 2),
                    MoneyText(
                      market,
                      summary.marketValue,
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('總收益', style: theme.textTheme.labelMedium?.copyWith(color: muted)),
            const SizedBox(height: 2),
            MoneyText(
              market,
              summary.totalGain,
              key: ValueKey('total-gain-${market.name}'),
              signed: true,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF6F8F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: _Breakdown(
                        label: '股息',
                        child: MoneyText(market, summary.dividends),
                      ),
                    ),
                    Expanded(
                      child: _Breakdown(
                        label: '已實現',
                        child: MoneyText(market, summary.realizedPnl, signed: true),
                      ),
                    ),
                    Expanded(
                      child: _Breakdown(
                        label: '未實現',
                        child: MoneyText(market, summary.unrealizedPnl, signed: true),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '今年收到的股息',
                  style: theme.textTheme.labelMedium?.copyWith(color: muted),
                ),
                const Spacer(),
                MoneyText(market, summary.dividendsThisYear),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketPill extends StatelessWidget {
  const _MarketPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 2),
        child,
      ],
    );
  }
}
