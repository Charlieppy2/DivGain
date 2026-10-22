import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/book_math.dart';
import '../models/book.dart';
import '../state/book_controller.dart';
import '../ui/export_workbook.dart';
import '../ui/format.dart';
import '../ui/gain_color.dart';
import '../widgets/hkd_rmb_text.dart';
import 'book_entry_form_screen.dart';
import 'wallet_screen.dart';

class BookHomeCard extends ConsumerWidget {
  const BookHomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(bookProvider);
    final theme = Theme.of(context);
    final month = DateTime.now();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('open-book'),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => const CashbookScreen(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.edit_note_outlined,
                    size: 22,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '記賬',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: theme.colorScheme.outline),
                ],
              ),
              const SizedBox(height: 14),
              book.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, stackTrace) => const Text('讀取失敗'),
                data: (entries) {
                  final day = summarizeClose(
                    entries,
                    BookCurrency.hkd,
                    BookClose.day,
                    month,
                  ).balance;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HomeCloseFigure(
                        label: BookClose.day.label,
                        child: HkdRmbText(
                          BookCurrency.hkd.market,
                          day,
                          signed: true,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final close in [BookClose.month, BookClose.year])
                            Expanded(
                              child: _HomeCloseFigure(
                                label: close.label,
                                child: HkdRmbText(
                                  BookCurrency.hkd.market,
                                  summarizeClose(
                                    entries,
                                    BookCurrency.hkd,
                                    close,
                                    month,
                                  ).balance,
                                  signed: true,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeCloseFigure extends StatelessWidget {
  const _HomeCloseFigure({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class CashbookScreen extends ConsumerStatefulWidget {
  const CashbookScreen({super.key});

  @override
  ConsumerState<CashbookScreen> createState() => _CashbookScreenState();
}

class _CashbookScreenState extends ConsumerState<CashbookScreen> {
  var _close = BookClose.month;
  late DateTime _cursor;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _cursor = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(bookProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('記賬'),
        actions: [
          TextButton(
            key: const Key('import-workbook'),
            onPressed: () => importDivGain(context, ref),
            child: const Text('匯入'),
          ),
          TextButton(
            key: const Key('export-workbook'),
            onPressed: () => exportDivGain(context, ref),
            child: const Text('匯出'),
          ),
          Padding(
            padding: EdgeInsets.only(right: kDebugMode ? 48 : 4),
            child: Center(
              child: TextButton(
                key: const Key('open-wallet'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const WalletScreen(),
                    ),
                  );
                },
                child: const Text('錢包'),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('記一筆'),
      ),
      body: book.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('讀取失敗'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(bookProvider),
                child: const Text('重試'),
              ),
            ],
          ),
        ),
        data: (entries) => _CloseBody(
          close: _close,
          cursor: _cursor,
          entries: entries,
          selectedDay: _selectedDay,
          onClose: (close) => setState(() {
            _close = close;
            _selectedDay = null;
          }),
          onPrevious: () => setState(() {
            _cursor = shiftClose(_cursor, _close, -1);
            _selectedDay = null;
          }),
          onNext: () => setState(() {
            _cursor = shiftClose(_cursor, _close, 1);
            _selectedDay = null;
          }),
          onOpen: (entry) => _openForm(context, entryId: entry.id),
          onSelectDay: (date) => setState(() {
            final day = DateTime(date.year, date.month, date.day);
            _cursor = day;
            if (_close == BookClose.year) _close = BookClose.month;
            if (_close == BookClose.day) return;
            final selected = _selectedDay;
            final sameDay =
                selected != null &&
                selected.year == day.year &&
                selected.month == day.month &&
                selected.day == day.day;
            _selectedDay = sameDay ? null : day;
          }),
          onSelectMonth: (month) => setState(() {
            _close = BookClose.month;
            _cursor = DateTime(month.year, month.month);
          }),
        ),
      ),
    );
  }

  void _openForm(BuildContext context, {int? entryId}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => BookEntryFormScreen(
          entryId: entryId,
          initialDate: entryId == null ? _initialDate() : null,
        ),
      ),
    );
  }

  DateTime _initialDate() {
    final selected = _selectedDay;
    if (_close == BookClose.month && selected != null) return selected;
    final now = DateTime.now();
    return switch (_close) {
      BookClose.day => DateTime(_cursor.year, _cursor.month, _cursor.day),
      BookClose.month =>
        _cursor.year == now.year && _cursor.month == now.month
            ? DateTime(now.year, now.month, now.day)
            : DateTime(_cursor.year, _cursor.month),
      BookClose.year =>
        _cursor.year == now.year
            ? DateTime(now.year, now.month, now.day)
            : DateTime(_cursor.year),
    };
  }
}

class _CloseBody extends StatelessWidget {
  const _CloseBody({
    required this.close,
    required this.cursor,
    required this.selectedDay,
    required this.entries,
    required this.onClose,
    required this.onPrevious,
    required this.onNext,
    required this.onOpen,
    required this.onSelectDay,
    required this.onSelectMonth,
  });

  final BookClose close;
  final DateTime cursor;
  final DateTime? selectedDay;
  final List<BookEntry> entries;
  final ValueChanged<BookClose> onClose;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<BookEntry> onOpen;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<DateTime> onSelectMonth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showCalendar = close != BookClose.year;
    final detailDay = close == BookClose.day ? cursor : selectedDay;
    final periodEntries =
        (detailDay == null
                ? entriesInClose(entries, close, cursor)
                : entriesInClose(entries, BookClose.day, detailDay))
            .where((entry) => entry.currency == BookCurrency.hkd)
            .toList();
    final summaryClose = detailDay == null ? close : BookClose.day;
    final summaryAnchor = detailDay ?? cursor;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
              SegmentedButton<BookClose>(
                segments: const [
                  ButtonSegment(
                    value: BookClose.day,
                    label: Text('日結', key: Key('book-close-day')),
                  ),
                  ButtonSegment(
                    value: BookClose.month,
                    label: Text('月結', key: Key('book-close-month')),
                  ),
                  ButtonSegment(
                    value: BookClose.year,
                    label: Text('年結', key: Key('book-close-year')),
                  ),
                ],
                selected: {close},
                onSelectionChanged: (selection) => onClose(selection.first),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  IconButton(
                    key: const Key('book-previous-month'),
                    tooltip: previousCloseLabel(close),
                    onPressed: onPrevious,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      closeTitle(cursor, close),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const Key('book-next-month'),
                    tooltip: nextCloseLabel(close),
                    onPressed: onNext,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              if (showCalendar) ...[
                const SizedBox(height: 4),
                _MonthCalendar(
                  month: cursor,
                  selected: detailDay,
                  entries: entries,
                  onSelectDay: onSelectDay,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            key: ValueKey(
              '${close.name}-${summaryAnchor.year}-${summaryAnchor.month}-${summaryAnchor.day}',
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (detailDay != null && close != BookClose.day)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      closeTitle(detailDay, BookClose.day),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                _CurrencyMonthCard(
                  summary: summarizeClose(
                    entries,
                    BookCurrency.hkd,
                    summaryClose,
                    summaryAnchor,
                  ),
                ),
                const SizedBox(height: 12),
                if (periodEntries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        detailDay == null
                            ? emptyCloseLabel(close)
                            : emptyCloseLabel(BookClose.day),
                      ),
                    ),
                  )
                else if (close == BookClose.year)
                  for (final group in groupByMonth(periodEntries)) ...[
                    _MonthCloseCard(
                      month: group.date,
                      entries: group.entries,
                      onTap: () => onSelectMonth(group.date),
                    ),
                    const SizedBox(height: 8),
                  ]
                else if (detailDay == null)
                  for (final group in groupByDay(periodEntries)) ...[
                    _DayHeader(
                      date: group.date,
                      entries: group.entries,
                      onTap: () => onSelectDay(group.date),
                    ),
                    for (final entry in group.entries) ...[
                      _EntryTile(entry: entry, onTap: () => onOpen(entry)),
                      const SizedBox(height: 8),
                    ],
                  ]
                else
                  for (final entry in periodEntries) ...[
                    _EntryTile(entry: entry, onTap: () => onOpen(entry)),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.selected,
    required this.entries,
    required this.onSelectDay,
  });

  final DateTime month;
  final DateTime? selected;
  final List<BookEntry> entries;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final picked = selected;
    final days = monthCalendarDays(month);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
          children: [
            Row(
              children: [
                for (final label in const ['日', '一', '二', '三', '四', '五', '六'])
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (var index = 0; index < days.length; index += 7)
              Row(
                children: [
                  for (final date in days.sublist(index, index + 7))
                    Expanded(
                      child: SizedBox(
                        height: 64,
                        child: date == null
                            ? null
                            : _CalendarDay(
                                date: date,
                                entries: entries,
                                isToday:
                                    date.year == today.year &&
                                    date.month == today.month &&
                                    date.day == today.day,
                                isSelected:
                                    picked != null &&
                                    date.year == picked.year &&
                                    date.month == picked.month &&
                                    date.day == picked.day,
                                onTap: () => onSelectDay(date),
                              ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 4),
            Text('格內數字是當天支出', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.entries,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime date;
  final List<BookEntry> entries;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayExpense = summarizeClose(
      entries,
      BookCurrency.hkd,
      BookClose.day,
      date,
    ).expense;
    final spent = dayExpense > 0.004
        ? [formatMoney(BookCurrency.hkd.market, dayExpense)]
        : const <String>[];
    final hasSpend = spent.isNotEmpty;
    return InkWell(
      key: Key('book-calendar-${date.year}-${date.month}-${date.day}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: hasSpend && !isSelected
              ? GainColors.loss.withValues(alpha: 0.08)
              : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: isSelected
                ? BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  )
                : isToday
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 1.5,
                    ),
                  )
                : null,
            child: Text(
              '${date.day}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: isSelected ? theme.colorScheme.onPrimary : null,
                fontWeight: isSelected || isToday ? FontWeight.w700 : null,
              ),
            ),
          ),
          for (final amount in spent)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  amount,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: GainColors.loss,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
        ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.date,
    required this.entries,
    required this.onTap,
  });

  final DateTime date;
  final List<BookEntry> entries;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Row(
          children: [
            Text('${date.day}日', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(width: 12),
            if (summarizeClose(
              entries,
              BookCurrency.hkd,
              BookClose.day,
              date,
            ).hasActivity)
              HkdRmbText(
                BookCurrency.hkd.market,
                summarizeClose(
                  entries,
                  BookCurrency.hkd,
                  BookClose.day,
                  date,
                ).balance,
                signed: true,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        ),
      ),
    );
  }
}

class _MonthCloseCard extends StatelessWidget {
  const _MonthCloseCard({
    required this.month,
    required this.entries,
    required this.onTap,
  });

  final DateTime month;
  final List<BookEntry> entries;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${month.month}月', style: theme.textTheme.titleMedium),
              if (summarizeClose(
                entries,
                BookCurrency.hkd,
                BookClose.month,
                month,
              ).hasActivity)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: HkdRmbText(
                    BookCurrency.hkd.market,
                    summarizeClose(
                      entries,
                      BookCurrency.hkd,
                      BookClose.month,
                      month,
                    ).balance,
                    signed: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrencyMonthCard extends StatelessWidget {
  const _CurrencyMonthCard({required this.summary});

  final CurrencyMonth summary;

  @override
  Widget build(BuildContext context) {
    final market = summary.currency.market;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _Figure(
                    label: '收入',
                    child: HkdRmbText(market, summary.income),
                  ),
                ),
                Expanded(
                  child: _Figure(
                    label: '支出',
                    child: HkdRmbText(market, summary.expense),
                  ),
                ),
                Expanded(
                  child: _Figure(
                    label: '結餘',
                    child: HkdRmbText(market, summary.balance, signed: true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.child});

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

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final BookEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signedAmount = entry.kind == BookKind.expense
        ? -entry.amount
        : entry.amount;
    final note = entry.note.trim();
    final method = entry.method.trim();
    final details = [
      entry.kind.label,
      formatDate(entry.date),
      if (method.isNotEmpty) method,
      if (note.isNotEmpty) note,
    ].join('  ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('book-entry-${entry.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 36,
                decoration: BoxDecoration(
                  color: GainColors.of(signedAmount),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.category,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      details,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
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
