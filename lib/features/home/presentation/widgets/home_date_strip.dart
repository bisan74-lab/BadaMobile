import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';

/// 홈 화면 상단의 좌우 스크롤 날짜 띠. [minDate]~[maxDate] 범위(기본 과거
/// 2주~미래 2주, 총 4주)를 좌우로 넘기며 날짜를 고를 수 있다.
class HomeDateStrip extends StatefulWidget {
  const HomeDateStrip({
    super.key,
    required this.date,
    required this.minDate,
    required this.maxDate,
    required this.onChanged,
  });

  final DateTime date;
  final DateTime minDate;
  final DateTime maxDate;
  final ValueChanged<DateTime> onChanged;

  @override
  State<HomeDateStrip> createState() => _HomeDateStripState();
}

class _HomeDateStripState extends State<HomeDateStrip> {
  final _controller = ScrollController();
  static const _itemWidth = 52.0;

  int get _totalDays => widget.maxDate.difference(widget.minDate).inDays + 1;

  int _indexFor(DateTime d) => DateUtils.dateOnly(
    d,
  ).difference(DateUtils.dateOnly(widget.minDate)).inDays;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _centerOn(widget.date, animate: false),
    );
  }

  @override
  void didUpdateWidget(covariant HomeDateStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!DateUtils.isSameDay(oldWidget.date, widget.date)) {
      _centerOn(widget.date, animate: true);
    }
  }

  void _centerOn(DateTime date, {required bool animate}) {
    if (!_controller.hasClients) return;
    final index = _indexFor(date);
    final viewport = _controller.position.viewportDimension;
    final target = index * _itemWidth - viewport / 2 + _itemWidth / 2;
    final clamped = target.clamp(0.0, _controller.position.maxScrollExtent);
    if (animate) {
      _controller.animateTo(
        clamped,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _controller.jumpTo(clamped);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: ListView.builder(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        itemCount: _totalDays,
        itemBuilder: (context, i) {
          final d = DateUtils.dateOnly(widget.minDate).add(Duration(days: i));
          final isSelected = DateUtils.isSameDay(d, widget.date);
          final isToday = DateUtils.isSameDay(d, DateTime.now());
          return GestureDetector(
            onTap: () => widget.onChanged(d),
            child: Container(
              width: _itemWidth - 6,
              margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: isToday && !isSelected
                    ? Border.all(color: Colors.white70)
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    weekdayKo(d),
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected
                          ? const Color(0xFF0E3454)
                          : Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${d.day}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? const Color(0xFF0E3454)
                          : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
