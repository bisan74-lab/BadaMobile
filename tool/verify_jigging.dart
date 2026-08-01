// 추정 지수(쭈꾸미·갑오징어·문어) 자체 검증.
//
//   dart run tool/verify_jigging.dart
//
// 전국 대표 지점(사리 조차가 크게 다른 곳들) × 15개 물때 × 12개월을 훑어
// 등급 분포를 뽑고, 아래 불변식을 확인한다. 하나라도 깨지면 종료 코드 1.
//
//   1. 물때 변별력 — 성수기(10월) 조류를 뚜렷하게 타는 쭈꾸미·갑오징어가
//      물때에 따라 최소 2단계(조차가 큰 서해는 3단계)로 갈려야 한다.
//      (예전엔 절대 조차로 정규화해 서해가 전 물때 "매우나쁨" 한 칸이었다.)
//   2. **"매우나쁨"은 날씨가 나쁠 때만** — 바람·파고가 잔잔하거나 정보가 없으면
//      어떤 지점·달·물때·어종도 매우나쁨이 나오면 안 된다. 반대로 강풍+높은
//      파고에서는 나와야 한다(안 나오면 경고 기능이 죽은 것).
//   3. 조차가 작은 곳(동해권)도 전 물때 "매우좋음"이면 안 된다
//      — 1의 반대 방향 실패(세기 상한이 최적에 눌러앉는 경우).
//   4. 어종별 조류 선호 방향 — 쭈꾸미는 조금 > 사리, 갑오징어는
//      약한중간 > 조금 > 중간 > 사리, 셋 다 조금 > 사리.
//   5. 제철 흐름(쭈꾸미·갑오징어) — 9월(금어기 해제) ≈ 10월 > 8월,
//      그리고 11월은 10월보다 확실히 낮다(개체수 급감).
//   6. 바람 정보가 없으면 감점이 없다 — null로 넘긴 결과가 "잔잔한 날"과 같다.
//   7. 실측 대조 — 사용자 제보 사례(무창포 2026-08-20 조금, 조차 376cm)에서
//      쭈꾸미·갑오징어가 "매우나쁨"으로 떨어지지 않는다.
//
// 문어는 원래 조류를 크게 타지 않아 변별력 조건에서 뺀다(같은 등급이 이어져도
// 그게 맞다).

// 결과를 사람이 읽는 콘솔 스크립트라 print가 곧 출력이다(앱 코드가 아니다).
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:bada_mobile/core/utils/mul_ttae.dart';
import 'package:bada_mobile/features/fishing/data/models/fishing_index.dart';
import 'package:bada_mobile/features/fishing/data/models/jigging_estimate.dart';

/// 검증용 대표 지점. [springRangeCm]은 그 지점의 대략적인 대조기 조차로,
/// 조위 데이터 대신 물때별 하루 조차를 만들어 내는 데 쓴다.
typedef Site = ({String name, MulTtaeSystem system, double springRangeCm});

const sites = <Site>[
  (name: '인천', system: MulTtaeSystem.west7, springRangeCm: 900),
  (name: '무창포(보령)', system: MulTtaeSystem.west7, springRangeCm: 750),
  (name: '군산', system: MulTtaeSystem.west7, springRangeCm: 650),
  (name: '목포', system: MulTtaeSystem.south8, springRangeCm: 450),
  (name: '여수', system: MulTtaeSystem.south8, springRangeCm: 330),
  (name: '통영', system: MulTtaeSystem.south8, springRangeCm: 270),
  (name: '부산', system: MulTtaeSystem.south8, springRangeCm: 130),
  (name: '포항', system: MulTtaeSystem.south8, springRangeCm: 40),
];

/// 그 지점·물때의 하루 조차(cm)를 만든다.
///
/// 앱의 [relativeTideStrength]가 쓰는 역산식(0.45 + 0.55·phase)과 **일부러
/// 다른 계수**(0.40 + 0.60·phase)를 쓴다 — 같은 식을 쓰면 사리 조차 역산이
/// 정확히 맞아떨어져 검증이 자기 자신을 검증하는 꼴이 된다.
double dayRangeFor(Site site, MulTtae mulTtae) =>
    site.springRangeCm * (0.40 + 0.60 * springNeapPhase(mulTtae));

/// 그 물때식의 15단계 물때 전부.
List<MulTtae> allMulTtae(MulTtaeSystem system) => [
  for (var i = 0; i < 15; i++) MulTtae(index: i, lunarDay: 1, system: system),
];

String label(MulTtae m) => m.label;

FishingGrade gradeFor(
  String species,
  Site site,
  MulTtae mulTtae,
  int month, {
  double? windMs,
  double? gustMs,
  double? waveM,
}) => estimateJiggingGrade(
  species: species,
  tideStrength: relativeTideStrength(
    mulTtae: mulTtae,
    dayRangeCm: dayRangeFor(site, mulTtae),
  ),
  windMs: windMs,
  gustMs: gustMs,
  waveM: waveM,
  month: month,
);

final failures = <String>[];

void check(bool ok, String what) {
  if (!ok) failures.add(what);
}

void main() {
  // ── 1. 성수기(10월) 등급표 ────────────────────────────────────────────
  print('■ 10월 물때별 추정 등급 (바람 정보 없음 = 물때·제철만)\n');
  for (final site in sites) {
    final muls = allMulTtae(site.system);
    print('· ${site.name} (사리 조차 ${site.springRangeCm.toInt()}cm)');
    for (final species in estimatedSpeciesCatalog) {
      final row = [for (final m in muls) gradeFor(species, site, m, 10)];
      final cells = [
        for (var i = 0; i < muls.length; i++)
          '${label(muls[i])}:${row[i].label}',
      ];
      print('    ${species.padRight(5)} ${cells.join(' ')}');

      // 불변식 1: 성수기엔 물때로 등급이 갈려야 한다. 조차가 큰 서해는
      // 위상 전 구간을 쓰므로 3단계, 조차가 작은 곳은 2단계까지 요구한다.
      // (문어는 원래 조류를 크게 안 타므로 뺀다.)
      if (species != '문어') {
        final want = site.springRangeCm >= 450 ? 3 : 2;
        check(
          row.toSet().length >= want,
          '${site.name} 10월 $species: 물때 변별력 부족 '
          '(${row.toSet().map((g) => g.label).join('/')})',
        );
      }
    }
    print('');
  }

  // ── 2·3. "매우나쁨"은 날씨가 나쁠 때만 ───────────────────────────────
  for (final site in sites) {
    for (final species in estimatedSpeciesCatalog) {
      for (var month = 1; month <= 12; month++) {
        for (final m in allMulTtae(site.system)) {
          // 바람 정보가 없을 때(= 물때·제철만)와 잔잔할 때는 아무리 나빠도
          // "나쁨"에서 멈춰야 한다.
          check(
            gradeFor(species, site, m, month) != FishingGrade.veryBad,
            '${site.name} $month월 ${label(m)} $species: 날씨가 나쁘지도 않은데 '
            '"매우나쁨"',
          );
          check(
            gradeFor(
                  species,
                  site,
                  m,
                  month,
                  windMs: 2,
                  gustMs: 4,
                  waveM: 0.3,
                ) !=
                FishingGrade.veryBad,
            '${site.name} $month월 ${label(m)} $species: 잔잔한 날인데 "매우나쁨"',
          );
        }
        final row = [
          for (final m in allMulTtae(site.system))
            gradeFor(species, site, m, month),
        ];
        // 조차가 작은 곳에서 반대로 전부 "매우좋음"이 되는 것도 막는다.
        // (문어는 원래 조류를 크게 안 타서 제철엔 대체로 좋은 게 맞다.)
        if (species != '문어') {
          check(
            !row.every((g) => g == FishingGrade.veryGood),
            '${site.name} $month월 $species: 15개 물때가 전부 "매우좋음" '
            '— 세기 상한이 최적에 눌러앉았다',
          );
        }
      }
    }
  }

  // 반대 방향: 강풍 + 높은 파고면 "매우나쁨"이 나와야 한다(경고가 죽으면 안 됨).
  for (final species in estimatedSpeciesCatalog) {
    check(
      gradeFor(
            species,
            sites[1],
            allMulTtae(MulTtaeSystem.west7)[13], // 조금
            10,
            windMs: 15,
            gustMs: 23,
            waveM: 3.0,
          ) ==
          FishingGrade.veryBad,
      '$species: 강풍·높은 파고에서도 "매우나쁨"이 안 나온다',
    );
  }

  // ── 4. 어종별 조류 선호 방향 ─────────────────────────────────────────
  const west = MulTtaeSystem.west7;
  final jogeum = MulTtae(index: 13, lunarDay: 8, system: west); // 조금
  final weakMid = MulTtae(index: 1, lunarDay: 11, system: west); // 2물
  final mid = MulTtae(index: 2, lunarDay: 12, system: west); // 3물
  final sari = MulTtae(index: 6, lunarDay: 16, system: west); // 7물(사리)
  final site = sites[1]; // 무창포

  double score(String s, MulTtae m, int month) => estimateJiggingScore(
    species: s,
    tideStrength: relativeTideStrength(
      mulTtae: m,
      dayRangeCm: dayRangeFor(site, m),
    ),
    month: month,
  );

  print('■ 조류 선호 (무창포 10월, 바람 정보 없음)\n');
  print('   어종     조금   2물   3물   사리');
  for (final s in estimatedSpeciesCatalog) {
    String f(MulTtae m) => score(s, m, 10).toStringAsFixed(2).padLeft(6);
    print('   ${s.padRight(6)}${f(jogeum)}${f(weakMid)}${f(mid)}${f(sari)}');
  }
  print('');

  check(
    score('쭈꾸미', jogeum, 10) > score('쭈꾸미', sari, 10),
    '쭈꾸미: 조금이 사리보다 높아야 한다',
  );
  check(
    score('갑오징어', weakMid, 10) > score('갑오징어', jogeum, 10) &&
        score('갑오징어', jogeum, 10) > score('갑오징어', mid, 10) &&
        score('갑오징어', mid, 10) > score('갑오징어', sari, 10),
    '갑오징어: 약한중간 > 조금 > 중간 > 사리 순이어야 한다',
  );
  for (final s in estimatedSpeciesCatalog) {
    check(score(s, jogeum, 10) > score(s, sari, 10), '$s: 조금 > 사리여야 한다');
  }

  // ── 5. 제철 흐름 (쭈꾸미·갑오징어) ───────────────────────────────────
  print('■ 월별 추정 점수 (무창포 조금, 바람 정보 없음)\n');
  print('   어종      1월  2월  3월  4월  5월  6월  7월  8월  9월 10월 11월 12월');
  for (final s in estimatedSpeciesCatalog) {
    final cells = [
      for (var m = 1; m <= 12; m++)
        score(s, jogeum, m).toStringAsFixed(2).padLeft(5),
    ];
    print('   ${s.padRight(7)}${cells.join()}');
  }
  print('');

  for (final s in ['쭈꾸미', '갑오징어']) {
    check(
      score(s, jogeum, 9) > score(s, jogeum, 8) * 1.5,
      '$s: 9월이 8월보다 확실히 높아야 한다(금어기 해제)',
    );
    check(
      (score(s, jogeum, 9) - score(s, jogeum, 10)).abs() < 0.05,
      '$s: 9월과 10월이 비슷해야 한다',
    );
    check(
      score(s, jogeum, 11) < score(s, jogeum, 10) * 0.7,
      '$s: 11월은 10월보다 확실히 낮아야 한다(개체수 급감)',
    );
  }

  // ── 6. 바람 정보가 없으면 감점하지 않는다 ────────────────────────────
  for (final s in estimatedSpeciesCatalog) {
    final noWind = gradeFor(s, site, jogeum, 10);
    final calm = gradeFor(s, site, jogeum, 10, windMs: 0, gustMs: 0, waveM: 0);
    final blow = gradeFor(
      s,
      site,
      jogeum,
      10,
      windMs: 14,
      gustMs: 22,
      waveM: 3,
    );
    check(noWind == calm, '$s: 바람 정보 없음이 "잔잔"과 같아야 한다');
    check(blow.score < noWind.score, '$s: 바람 정보가 있고 강풍이면 등급이 내려가야 한다');
  }

  // ── 7. 실측 대조 (사용자 제보 화면) ──────────────────────────────────
  // 무창포항(보령) 2026-08-20, 음력 8일 = 조금. 화면의 조류세기 47%
  // → 하루 조차 = 0.47 × 800 = 376cm. 예보 범위 밖이라 바람 정보 없음.
  const reportedRangeCm = 376.0;
  final reported = mulTtaeFor(
    DateTime(2026, 8, 20),
    system: MulTtaeSystem.west7,
  );
  final reportedStrength = relativeTideStrength(
    mulTtae: reported,
    dayRangeCm: reportedRangeCm,
  );
  print(
    '■ 제보 사례 — 무창포 2026-08-20 (${reported.label}, 조차 ${reportedRangeCm.toInt()}cm)',
  );
  print(
    '   상대 조류 세기 ${reportedStrength.toStringAsFixed(3)} '
    '(예전 절대 방식: ${(reportedRangeCm / 800).toStringAsFixed(3)})',
  );
  for (final s in estimatedSpeciesCatalog) {
    final g = estimateJiggingGrade(
      species: s,
      tideStrength: reportedStrength,
      month: 8,
    );
    print('   ${s.padRight(6)} ${g.label}');
    check(g != FishingGrade.veryBad, '$s: 조금인데 "매우나쁨" — 제보와 같은 증상');
  }
  check(reported.isJogeum, '2026-08-20은 조금이어야 한다(음력 8일)');
  check(reportedStrength < 0.1, '조금의 상대 세기는 0.1 미만이어야 한다');
  print('');

  if (failures.isEmpty) {
    print('✅ 모든 검증 통과');
  } else {
    print('❌ 검증 실패 ${failures.length}건');
    for (final f in failures) {
      print('   - $f');
    }
    exitCode = 1;
  }
}
