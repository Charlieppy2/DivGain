import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/portfolio_math.dart';
import '../models/ledger.dart';
import '../state/portfolio_controller.dart';
import '../ui/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/money_text.dart';
import 'dividend_form_screen.dart';
import 'holding_form_screen.dart';
import 'trade_form_screen.dart';

class HoldingDetailScreen extends ConsumerWidget {
  const HoldingDetailScreen({super.key, required this.holdingId});

  final int holdingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolio = ref.watch(portfolioProvider);
    return portfolio.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => const Scaffold(
        body: Center(child: Text('讀取失敗')),
      ),
      data: (data) {
        final summary = data.summaryOf(holdingId);
        if (summary == null) {
          return const Scaffold(body: Center(child: Text('找不到這隻股票')));
        }
        return _DetailBody(summary: summary, data: data);
      },
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.summary, required this.data});

  final HoldingSummary summary;
  final PortfolioData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holding = summary.holding;
    final market = holding.market;
    final trades = data.tradesOf(holding.id);
    final dividends = data.dividendsOf(holding.id);
    final name = holding.name.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? holding.symbol : '${holding.symbol}  $name'),
        actions: [
          IconButton(
            tooltip: '編輯',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) =>
                      HoldingFormScreen(holdingId: holding.id),
                ),
              );
            },
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '刪除',
            onPressed: () => _deleteHolding(context, ref),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _Stat(
                    label: '總收益',
                    value: MoneyText(
                      market,
                      summary.totalGain,
                      signed: true,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  _Stat(label: '持有股數', value: Text('${formatShares(summary.shares)} 股')),
                  _Stat(
                    label: '平均成本',
                    value: Text(
                      summary.shares <= shareEpsilon
                          ? '—'
                          : formatMoney(market, summary.averageCost),
                    ),
                  ),
                  _Stat(
                    label: '成本',
                    value: MoneyText(market, summary.costBasis),
                  ),
                  _Stat(
                    label: '現價',
                    value: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MoneyText(market, holding.currentPrice),
                        if (holding.priceAsOf != null)
                          Text(
                            '截至 ${formatDate(holding.priceAsOf!)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  _Stat(
                    label: '市值',
                    value: MoneyText(market, summary.marketValue),
                  ),
                  _Stat(
                    label: '未實現',
                    value: MoneyText(market, summary.unrealizedPnl, signed: true),
                  ),
                  _Stat(
                    label: '已實現',
                    value: MoneyText(market, summary.realizedPnl, signed: true),
                  ),
                  _Stat(
                    label: '股息',
                    value: MoneyText(market, summary.dividends),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader(
            title: '買賣',
            action: '記一筆',
            onAction: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => TradeFormScreen(holdingId: holding.id),
                ),
              );
            },
          ),
          if (trades.isEmpty)
            const _EmptyLine('還沒有買賣紀錄')
          else
            Card(
              child: Column(
                children: [
                  for (final trade in trades)
                    ListTile(
                      title: Text('${trade.side.label}  ${formatDate(trade.date)}'),
                      subtitle: Text(_tradeSubtitle(market, trade)),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => TradeFormScreen(
                              holdingId: holding.id,
                              tradeId: trade.id,
                            ),
                          ),
                        );
                      },
                      trailing: IconButton(
                        tooltip: '刪除',
                        onPressed: () => _deleteTrade(context, ref, trade),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          _SectionHeader(
            title: '股息',
            action: '記一筆',
            onAction: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) =>
                      DividendFormScreen(holdingId: holding.id),
                ),
              );
            },
          ),
          if (dividends.isEmpty)
            const _EmptyLine('還沒有股息紀錄')
          else
            Card(
              child: Column(
                children: [
                  for (final dividend in dividends)
                    ListTile(
                      title: Text(formatDate(dividend.date)),
                      subtitle: Text(
                        dividend.note.trim().isEmpty
                            ? formatMoney(market, dividend.amount)
                            : '${formatMoney(market, dividend.amount)}\n${dividend.note.trim()}',
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => DividendFormScreen(
                              holdingId: holding.id,
                              dividendId: dividend.id,
                            ),
                          ),
                        );
                      },
                      trailing: IconButton(
                        tooltip: '刪除',
                        onPressed: () => _deleteDividend(context, ref, dividend.id),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _deleteHolding(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDelete(
      context,
      '刪除這隻股票？買賣和股息紀錄會一併刪除。',
    );
    if (!confirmed || !context.mounted) return;
    await ref.read(portfolioProvider.notifier).deleteHolding(summary.holding.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _deleteTrade(
    BuildContext context,
    WidgetRef ref,
    Trade trade,
  ) async {
    final confirmed = await confirmDelete(context, '刪除這筆買賣？');
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(portfolioProvider.notifier).deleteTrade(trade);
    } on ShareShortage catch (error) {
      if (context.mounted) showMessage(context, error.message);
    } catch (_) {
      if (context.mounted) showMessage(context, '刪除失敗');
    }
  }

  Future<void> _deleteDividend(
    BuildContext context,
    WidgetRef ref,
    int id,
  ) async {
    final confirmed = await confirmDelete(context, '刪除這筆股息？');
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(portfolioProvider.notifier).deleteDividend(id);
    } catch (_) {
      if (context.mounted) showMessage(context, '刪除失敗');
    }
  }
}

String _tradeSubtitle(Market market, Trade trade) {
  final line =
      '${formatShares(trade.shares)} 股 × ${formatMoney(market, trade.price)}';
  if (trade.fee <= 0) return line;
  return '$line\n手續費 ${formatMoney(market, trade.fee)}';
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.action,
    required this.onAction,
  });

  final String title;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        TextButton(onPressed: onAction, child: Text(action)),
      ],
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}
