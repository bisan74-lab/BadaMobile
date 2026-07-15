import 'dart:convert';

/// 공공데이터포털(data.go.kr) 공통 응답 봉투 파서.
///
/// 지원하는 봉투 (1192136 KHOA 계열에서 실제 관찰된 형태 포함):
/// 1) 표준: response.header / response.body.items.item
/// 2) JSON 축약형: 루트에 header / body 가 바로 옴 (type=json 실측)
/// 3) KHOA 바다누리 미러: result.data (오류 시 result.error)
///
/// resultCode '00' = 정상, '03'(NODATA_ERROR) = 빈 목록으로 처리,
/// 그 외 코드는 예외.
List<Map<String, dynamic>> parseDataGoKrItems(String body) {
  final root = jsonDecode(body) as Map<String, dynamic>;

  // KHOA 바다누리 스타일 봉투.
  final result = root['result'];
  if (result is Map<String, dynamic>) {
    final error = result['error'];
    if (error != null && error.toString().isNotEmpty) {
      throw FormatException('KHOA 오류 응답: $error');
    }
    final data = result['data'];
    final list = data is List ? data : (data == null ? const [] : [data]);
    return list.whereType<Map<String, dynamic>>().toList();
  }

  // 'response' 래퍼가 있으면 벗기고, 없으면 루트가 곧 봉투다 (JSON 축약형).
  final response = switch (root['response']) {
    final Map<String, dynamic> r => r,
    _ => root,
  };
  final header = response['header'] as Map<String, dynamic>?;
  if (header == null) {
    throw const FormatException('data.go.kr 응답에 header/result 필드가 없음');
  }
  final resultCode = header['resultCode']?.toString();
  if (resultCode == '03') {
    return const []; // NODATA_ERROR: 해당 조건에 데이터 없음
  }
  if (resultCode != null && resultCode != '00') {
    throw FormatException(
      'data.go.kr 오류 응답: $resultCode ${header['resultMsg'] ?? ''}',
    );
  }
  final items = (response['body'] as Map<String, dynamic>?)?['items'];
  final List<dynamic> itemList;
  if (items is List) {
    itemList = items;
  } else if (items is Map<String, dynamic>) {
    final item = items['item'];
    itemList = item is List ? item : (item == null ? const [] : [item]);
  } else {
    itemList = const [];
  }
  return itemList.whereType<Map<String, dynamic>>().toList();
}

/// 여러 후보 키 중 첫 번째로 존재하는 값을 돌려준다.
/// 공공데이터 API마다 필드 명명(camel/snake)이 달라 후보 매칭으로 흡수한다.
Object? pickField(Map<String, dynamic> item, List<String> candidates) {
  for (final key in candidates) {
    final v = item[key];
    if (v != null) return v;
  }
  return null;
}
