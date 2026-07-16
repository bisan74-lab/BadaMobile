import 'package:flutter/material.dart';

import '../../../../core/utils/mul_ttae.dart';

/// 연도 → 월 → 일 계층으로 날짜를 고르는 물때용 선택기.
///
/// - 연도 행: 탭하면 그 해로 이동 ([minDate]~[maxDate] 범위).
/// - 월 행: 탭하면 그 달로 이동, 선택된 달의 날짜가 아래 일 행에 나타난다.
/// - 일 행: 좌우 스크롤로 해당 달의 날짜를 훑고 탭해서 고른다. 날짜별로
///   물때(사리 등)를 함께 보여준다.
///
/// 세 행 모두 [date]가 바뀌면 선택된 항목이 중앙에 오도록 자동 스크롤된다.
class TideDatePicker extends StatefulWidget {
  const TideDatePicker({
    super.key,
    required this.date,
    required this.minDate,
    required this.maxDate,
    required this.system,
    required this.onChanged,
  });

  final DateTime date;
  final DateTime minDate;
  final DateTime maxDate;
  final MulTtaeSystem system;
  final ValueChanged<DateTime> onChanged;

  @override
  State<TideDatePicker> createState() => _TideDatePickerState();
}

class _TideDatePickerState extends State<TideDatePicker> {
  final _yearController = ScrollController();
  final _monthController = ScrollController();
  final _dayController = ScrollController();

  static const _yearExtent = 64.0;
  static const _monthExtent = 56.0;
  static const _dayExtent = 72.0;

  @override
  void initState() {
    super.initState();
    _scrollToSelection(animate: false);
  }

  @override
  void didUpdateWidget(covariant TideDatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date) {
      _scrollToSelection(animate: true);
    }
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    super.dispose();
  }

  static int daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  DateTime _clamp(DateTime d) {
    if (d.isBefore(widget.minDate)) return widget.minDate;
    if (d.isAfter(widget.maxDate)) return widget.maxDate;
    return d;
  }

  void _selectYear(int year) {
    final day = widget.date.day.clamp(1, daysInMonth(year, widget.date.month));
    widget.onChanged(_clamp(DateTime(year, widget.date.month, day)));
  }

  void _selectMonth(int month) {
    final day = widget.date.day.clamp(1, daysInMonth(widget.date.year, month));
    widget.onChanged(_clamp(DateTime(widget.date.year, month, day)));
  }

  void _selectDay(int day) {
    widget.onChanged(
      _clamp(DateTime(widget.date.year, widget.date.month, day)),
    );
  }

  void _scrollToSelection({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final years = _yearRange();
      _centerOn(
        _yearController,
        years.indexOf(widget.date.year),
        _yearExtent,
        animate,
      );
      _centerOn(_monthController, widget.date.month - 1, _monthExtent, animate);
      _centerOn(_dayController, widget.date.day - 1, _dayExtent, animate);
    });
  }

  void _centerOn(
    ScrollController controller,
    int index,
    double itemExtent,
    bool animate,
  ) {
    if (!controller.hasClients || index < 0) return;
    final viewport = controller.position.viewportDimension;
    final target = (index * itemExtent) - viewport / 2 + itemExtent / 2;
    final clamped = target.clamp(0.0, controller.position.maxScrollExtent);
    if (animate) {
      controller.animateTo(
        clamped,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      controller.jumpTo(clamped);
    }
  }

  List<int> _yearRange() => [
    for (var y = widget.minDate.year; y <= widget.maxDate.year; y++) y,
  ];

  bool _inRange(DateTime d) =>
      !d.isBefore(widget.minDate) && !d.isAfter(widget.maxDate);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final years = _yearRange();
    final dayCount = daysInMonth(widget.date.year, widget.date.month);

    Widget chip({
      required bool selected,
      required bool enabled,
      required String label,
      required VoidCallback? onTap,
      double? width,
    }) {
      return GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary
                : scheme.surfaceContainerLow.withValues(
                    alpha: enabled ? 1 : 0.5,
                  ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected
                  ? scheme.onPrimary
                  : enabled
                  ? scheme.onSurface
                  : scheme.onSurfaceVariant.withValues(alpha: 0.5),
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 연도 행
        SizedBox(
          height: 44,
          child: ListView.separated(
            controller: _yearController,
            scrollDirection: Axis.horizontal,
            itemCount: years.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => chip(
              selected: years[i] == widget.date.year,
              enabled: true,
              label: '${years[i]}년',
              onTap: () => _selectYear(years[i]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 월 행
        SizedBox(
          height: 40,
          child: ListView.separated(
            controller: _monthController,
            scrollDirection: Axis.horizontal,
            itemCount: 12,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final month = i + 1;
              final monthStart = DateTime(widget.date.year, month, 1);
              final monthEnd = DateTime(
                widget.date.year,
                month,
                daysInMonth(widget.date.year, month),
              );
              final enabled =
                  !monthEnd.isBefore(widget.minDate) &&
                  !monthStart.isAfter(widget.maxDate);
              return chip(
                selected: month == widget.date.month,
                enabled: enabled,
                label: '$month월',
                width: 48,
                onTap: () => _selectMonth(month),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // 일 행 (물때 배지 포함)
        SizedBox(
          height: 76,
          child: ListView.separated(
            controller: _dayController,
            scrollDirection: Axis.horizontal,
            itemCount: dayCount,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final day = i + 1;
              final d = DateTime(widget.date.year, widget.date.month, day);
              final enabled = _inRange(d);
              final selected = day == widget.date.day;
              final dayMulTtae = mulTtaeFor(d, system: widget.system);
              return GestureDetector(
                onTap: enabled ? () => _selectDay(day) : null,
                child: Container(
                  width: 64,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerLow.withValues(
                            alpha: enabled ? 1 : 0.5,
                          ),
                    borderRadius: BorderRadius.circular(12),
                    border: selected ? Border.all(color: scheme.primary) : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day일',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: enabled
                              ? null
                              : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dayMulTtae.label,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: !enabled
                              ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
                              : dayMulTtae.isSari
                              ? scheme.error
                              : scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
