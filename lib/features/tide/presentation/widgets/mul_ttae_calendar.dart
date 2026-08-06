import 'package:flutter/material.dart';

import '../../../../core/utils/mul_ttae.dart';

/// 월 단위 물때 달력 팝업. 날짜별 물때(1물~사리·조금)를 한눈에 보여주고,
/// ◀▶로 달을 넘기며 연도 드롭다운으로 해를 바꾼다. 날짜를 탭하면 그 날짜를
/// 결과로 돌려주고 닫힌다(물때&날씨 화면의 날짜 선택 팝업 겸 물때달력).
Future<DateTime?> showMulTtaeCalendar(
  BuildContext context, {
  required DateTime initial,
  required DateTime minDate,
  required DateTime maxDate,
  required MulTtaeSystem system,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (context) => Dialog(
      child: MulTtaeCalendarView(
        initial: initial,
        minDate: minDate,
        maxDate: maxDate,
        system: system,
        onPicked: (d) => Navigator.pop(context, d),
      ),
    ),
  );
}

/// 물때달력 본체. 다이얼로그뿐 아니라 화면 중앙 패널에도 임베드해 쓴다
/// (물때&날씨 화면의 물때달력 버튼 — 그래프 자리에 그대로 그려진다).
class MulTtaeCalendarView extends StatefulWidget {
  const MulTtaeCalendarView({
    super.key,
    required this.initial,
    required this.minDate,
    required this.maxDate,
    required this.system,
    required this.onPicked,
  });

  final DateTime initial;
  final DateTime minDate;
  final DateTime maxDate;
  final MulTtaeSystem system;

  /// 날짜를 탭했을 때 호출된다(다이얼로그면 pop, 패널이면 날짜 선택).
  final ValueChanged<DateTime> onPicked;

  @override
  State<MulTtaeCalendarView> createState() => _MulTtaeCalendarState();
}

class _MulTtaeCalendarState extends State<MulTtaeCalendarView> {
  late int _year = widget.initial.year;
  late int _month = widget.initial.month;

  @override
  void didUpdateWidget(covariant MulTtaeCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 위 날짜 헤더/스트립에서 다른 달로 옮기면 달력도 그 달로 따라간다.
    if (!DateUtils.isSameDay(oldWidget.initial, widget.initial)) {
      _year = widget.initial.year;
      _month = widget.initial.month;
    }
  }

  bool get _canPrev => DateTime(
    _year,
    _month,
    1,
  ).isAfter(DateTime(widget.minDate.year, widget.minDate.month, 1));
  bool get _canNext => DateTime(
    _year,
    _month + 1,
    1,
  ).isBefore(DateTime(widget.maxDate.year, widget.maxDate.month + 1, 1));

  void _shiftMonth(int delta) {
    setState(() {
      final d = DateTime(_year, _month + delta, 1);
      _year = d.year;
      _month = d.month;
    });
  }

  bool _inRange(DateTime d) =>
      !d.isBefore(widget.minDate) && !d.isAfter(widget.maxDate);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final firstWeekday = DateTime(_year, _month, 1).weekday % 7; // 일=0
    final years = [
      for (var y = widget.minDate.year; y <= widget.maxDate.year; y++) y,
    ];

    // 소형 화면(테스트 뷰포트 포함)에서 넘치지 않게 스크롤을 허용하고,
    // 좌우 스와이프로 이전/다음 달로 넘길 수 있게 한다(사용자 요구).
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -150 && _canNext) _shiftMonth(1);
        if (v > 150 && _canPrev) _shiftMonth(-1);
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: _canPrev ? () => _shiftMonth(-1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DropdownButton<int>(
                        value: _year,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final y in years)
                            DropdownMenuItem(value: y, child: Text('$y년')),
                        ],
                        onChanged: (y) {
                          if (y != null) setState(() => _year = y);
                        },
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$_month월',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _canNext ? () => _shiftMonth(1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Row(
              children: [
                for (final (i, w) in const [
                  '일',
                  '월',
                  '화',
                  '수',
                  '목',
                  '금',
                  '토',
                ].indexed)
                  Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: i == 0
                              ? scheme.error
                              : i == 6
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // **칸 높이를 글자 배율에 맞춰 늘린다.** 한 칸에 날짜와 물때
              // 이름 두 줄이 들어가는데, 비율을 고정해 두면 큰 글자에서 글자가
              // 칸 밖으로 밀려 아랫줄 날짜와 겹친다(2026-08-06 사용자 제보
              // 스크린샷: 달력에서 "10물"이 "8" 위에 그려졌다).
              // 세로로만 길어지므로 가로 7칸 배치는 그대로다.
              childAspectRatio: _cellAspectRatio(context),
              children: [
                for (var i = 0; i < firstWeekday; i++) const SizedBox.shrink(),
                for (var day = 1; day <= daysInMonth; day++)
                  _dayCell(context, DateTime(_year, _month, day)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 날짜 칸의 가로:세로 비율. 배율이 오를수록 칸을 세로로 늘린다.
  static double _cellAspectRatio(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    return 0.82 / scale.clamp(1.0, 2.0);
  }

  Widget _dayCell(BuildContext context, DateTime d) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = _inRange(d);
    final selected = DateUtils.isSameDay(d, widget.initial);
    final today = DateUtils.isSameDay(d, DateTime.now());
    final mt = mulTtaeFor(d, system: widget.system);
    return InkWell(
      onTap: enabled ? () => widget.onPicked(d) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : null,
          border: today ? Border.all(color: scheme.primary) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${d.day}',
                maxLines: 1,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: selected ? FontWeight.bold : null,
                  color: !enabled
                      ? scheme.onSurfaceVariant.withValues(alpha: 0.35)
                      : d.weekday == DateTime.sunday
                      ? scheme.error
                      : null,
                ),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                mt.label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 9.5,
                  color: !enabled
                      ? scheme.onSurfaceVariant.withValues(alpha: 0.35)
                      : mt.isSari
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
