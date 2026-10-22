import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/portfolio_math.dart';
import '../models/ledger.dart';
import '../state/portfolio_controller.dart';
import '../ui/export_workbook.dart';
import '../widgets/holding_card.dart';
import '../widgets/money_text.dart';
import '../widgets/summary_card.dart';
import 'cashbook_screen.dart';
import 'holding_detail_screen.dart';
import 'holding_form_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolio = ref.watch(portfolioProvider);
    return portfolio.when(
      loading: () => const _ScaffoldFrame(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => _ScaffoldFrame(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('讀取失敗'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(portfolioProvider),
                child: const Text('重試'),
              ),
            ],
          ),
        ),
      ),
      data: (data) => _HomeBody(
        data: data,
        onImport: () => importDivGain(context, ref),
        onExport: () => exportDivGain(context, ref),
      ),
    );
  }
}

class _ScaffoldFrame extends StatelessWidget {
  const _ScaffoldFrame({
    required this.body,
    this.floatingActionButton,
    this.actions,
  });

  final Widget body;
  final Widget? floatingActionButton;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DivGain'), actions: actions),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({
    required this.data,
    required this.onImport,
    required this.onExport,
  });

  final PortfolioData data;
  final VoidCallback onImport;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final summaries = data.summaries;
    final open = [
      for (final summary in summaries)
        if (!isSoldOut(summary, data.trades)) summary,
    ];
    final closed = [
      for (final summary in summaries)
        if (isSoldOut(summary, data.trades)) summary,
    ];
    return _ScaffoldFrame(
      actions: [
        Padding(
          padding: EdgeInsets.only(right: kDebugMode ? 48 : 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                key: const Key('import-workbook'),
                onPressed: onImport,
                child: const Text('匯入'),
              ),
              TextButton(
                key: const Key('export-workbook'),
                onPressed: onExport,
                child: const Text('匯出'),
              ),
            ],
          ),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('新增股票'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          const BookHomeCard(),
          const SizedBox(height: 20),
          const _SectionLabel('股票'),
          const SizedBox(height: 4),
          Text(
            '總收益 = 已實現 + 未實現 + 股息。現價按最近收市價更新。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final summary in _currencyCards(summaries, data.dividends))
            if (_marketIsQuiet(summary))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _QuietMarket(summary: summary),
              )
            else ...[
              SummaryCard(summary: summary),
              const SizedBox(height: 12),
            ],
          if (summaries.isEmpty)
            const _EmptyHoldings()
          else ...[
            const _SectionLabel('持倉'),
            const SizedBox(height: 8),
            if (open.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '目前沒有持倉',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              for (final summary in open) ...[
                HoldingCard(
                  summary: summary,
                  onTap: () => _openHolding(context, summary),
                ),
                const SizedBox(height: 8),
              ],
            if (closed.isNotEmpty)
              _ClosedHoldings(
                summaries: closed,
                onOpen: (summary) => _openHolding(context, summary),
              ),
          ],
        ],
      ),
    );
  }

  void _openHolding(BuildContext context, HoldingSummary summary) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => HoldingDetailScreen(holdingId: summary.holding.id),
      ),
    );
  }

  void _openForm(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const HoldingFormScreen(),
      ),
    );
  }
}

List<CurrencySummary> _currencyCards(
  List<HoldingSummary> summaries,
  List<Dividend> dividends,
) {
  return [
    for (final market in [Market.hk, Market.us])
      summarizeCurrency(market, summaries, dividends: dividends),
  ];
}

bool _marketIsQuiet(CurrencySummary summary) {
  return summary.marketValue.abs() <= 0.004 &&
      summary.totalGain.abs() <= 0.004 &&
      summary.dividends.abs() <= 0.004 &&
      summary.dividendsThisYear.abs() <= 0.004 &&
      summary.realizedPnl.abs() <= 0.004 &&
      summary.unrealizedPnl.abs() <= 0.004;
}

class _QuietMarket extends StatelessWidget {
  const _QuietMarket({required this.summary});

  final CurrencySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _QuietPill(label: summary.market.label),
            const Spacer(),
            Text('總收益', style: theme.textTheme.labelMedium?.copyWith(color: muted)),
            const SizedBox(width: 8),
            MoneyText(
              summary.market,
              summary.totalGain,
              signed: true,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuietPill extends StatelessWidget {
  const _QuietPill({required this.label});

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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ClosedHoldings extends StatefulWidget {
  const _ClosedHoldings({required this.summaries, required this.onOpen});

  final List<HoldingSummary> summaries;
  final ValueChanged<HoldingSummary> onOpen;

  @override
  State<_ClosedHoldings> createState() => _ClosedHoldingsState();
}

class _ClosedHoldingsState extends State<_ClosedHoldings> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const Key('closed-holdings'),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Text(
                    '已清倉（${widget.summaries.length}）',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded)
          for (final summary in widget.summaries) ...[
            HoldingCard(
              summary: summary,
              onTap: () => widget.onOpen(summary),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _EmptyHoldings extends StatelessWidget {
  const _EmptyHoldings();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(
            Icons.show_chart,
            size: 40,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text('尚未加入股票', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '新增股票後，可以記錄買入、賣出和股息。',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
