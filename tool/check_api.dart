// 공공데이터포털(KHOA) API 연결 진단 스크립트.
//
// 사용법:
//   dart run tool/check_api.dart <서비스키>
//
// 확정된 요청 규격으로 조석예보(고저조)·바다낚시지수 API를 호출해
// 상태코드와 응답 앞부분을 출력한다.
//
// 판정 기준:
//   resultCode 00 (NORMAL_SERVICE) → 키·규격 모두 정상, 응답 필드 확인 가능
//   resultCode 03 (NODATA_ERROR)   → 키는 정상, 해당 조건에 데이터가 없음
//   Unauthorized / 30번대 코드     → 키 미동기화 또는 잘못된 키
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('사용법: dart run tool/check_api.dart <서비스키>');
    exit(1);
  }
  final key = args.first;
  final today = DateTime.now();
  final ymd =
      '${today.year}'
      '${today.month.toString().padLeft(2, '0')}'
      '${today.day.toString().padLeft(2, '0')}';

  final cases = <String, Uri>{
    '조석예보(고저조) 인천 오늘': Uri.https(
      'apis.data.go.kr',
      '/1192136/tideFcstHghLw/GetTideFcstHghLwApiService',
      {
        'serviceKey': key,
        'obsCode': 'DT_0001',
        'reqDate': ymd,
        'type': 'json',
        'pageNo': '1',
        'numOfRows': '10',
      },
    ),
    '바다낚시지수 오늘 갯바위': Uri.https(
      'apis.data.go.kr',
      '/1192136/fcstFishingv2/GetFcstFishingApiService',
      {
        'serviceKey': key,
        'type': 'json',
        'reqDate': ymd,
        'gubun': '갯바위',
        'pageNo': '1',
        'numOfRows': '10',
      },
    ),
    '바다낚시지수 오늘 선상': Uri.https(
      'apis.data.go.kr',
      '/1192136/fcstFishingv2/GetFcstFishingApiService',
      {
        'serviceKey': key,
        'type': 'json',
        'reqDate': ymd,
        'gubun': '선상',
        'pageNo': '1',
        'numOfRows': '10',
      },
    ),
  };

  final client = HttpClient();
  for (final entry in cases.entries) {
    try {
      final req = await client.getUrl(entry.value);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final head = body.replaceAll('\n', ' ');
      print('--- ${entry.key}');
      print('    HTTP ${res.statusCode}');
      print('    ${head.substring(0, head.length > 800 ? 800 : head.length)}');
      if (body.contains('NORMAL_SERVICE')) {
        print('    ✅ 정상 — 위 응답 전체를 개발 세션에 붙여넣으면 필드 매핑을 확정할 수 있습니다.');
      } else if (body.contains('NODATA_ERROR')) {
        print('    ⚠️ 키는 정상, 이 조건에는 데이터가 없습니다.');
      } else if (body.contains('Unauthorized')) {
        print('    ❌ 키 미동기화 또는 잘못된 키입니다.');
      }
    } catch (e) {
      print('--- ${entry.key}');
      print('    오류: $e');
    }
    print('');
  }
  client.close();
}
