import 'package:http/http.dart' as http;

import '../../../../core/config/env.dart';
import '../../../../core/network/data_go_kr.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/fishing_index.dart';
import 'fishing_repository.dart';

/// 공공데이터포털 「해양수산부 국립해양조사원_바다낚시지수 조회」 리포지토리.
///
/// End Point: https://apis.data.go.kr/1192136/fcstFishingv2
/// 인증: data.go.kr 일반 인증키 (`Env.dataGoKrApiKey`, --dart-define 주입)
///
/// ⚠️ 응답 필드 매핑([_itemToIndex])은 포털 활용가이드의 실제 샘플 응답으로
/// 확정해야 한다. 매핑이 확정될 때까지 provider는 목 구현을 기본으로 쓴다.
class DataGoKrFishingRepository implements FishingRepository {
  DataGoKrFishingRepository({http.Client? client, String? serviceKey})
    : _client = client ?? http.Client(),
      _serviceKey = serviceKey ?? Env.dataGoKrApiKey;

  final http.Client _client;
  final String _serviceKey;

  static const _host = 'apis.data.go.kr';
  static const _basePath = '/1192136/fcstFishingv2';

  @override
  Future<FishingForecast> fetchForecast(SeaLocation location) async {
    final uri = Uri.https(_host, '$_basePath/GetFcstFishingApiService', {
      'serviceKey': _serviceKey,
      'dataType': 'JSON',
      'pageNo': '1',
      'numOfRows': '100',
      // TODO(bisan74): 활용가이드로 지점/날짜 파라미터 이름 확정
      //  (예: reqDate=yyyyMMdd, 지점 식별자).
    });

    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw http.ClientException('바다낚시지수 응답 오류 ${res.statusCode}', uri);
    }
    final items = parseDataGoKrItems(res.body);
    return FishingForecast(
      locationId: location.id,
      indices: items.map(_itemToIndex).toList(),
    );
  }

  /// TODO(bisan74): 실제 응답 샘플로 필드명 확정 필요. 아래는 자리 표시.
  FishingIndex _itemToIndex(Map<String, dynamic> item) {
    throw UnimplementedError('바다낚시지수 응답 필드 매핑은 샘플 응답 확인 후 구현');
  }
}
