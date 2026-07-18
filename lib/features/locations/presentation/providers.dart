import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/storage/prefs.dart';
import '../data/geocoding.dart';
import '../data/models/sea_location.dart';
import '../data/sample_locations.dart';

/// 전체 지점 목록. 추후 원격 목록/검색으로 대체.
final locationsProvider = Provider<List<SeaLocation>>((ref) => sampleLocations);

/// 지오코딩(지명 검색) 리포지토리.
final geocodingRepositoryProvider = Provider<GeocodingRepository>(
  (ref) => GeocodingRepository(),
);

/// 검색어에 대한 지오코딩 결과(읍/면/동 등 세분화 지명 → 좌표).
final geocodingSearchProvider = FutureProvider.family<List<GeoPlace>, String>((
  ref,
  query,
) {
  return ref.read(geocodingRepositoryProvider).search(query);
});

/// GPS로 현재 위치를 얻어 즉석 [SeaLocation]으로 만든다. 권한 거부·위치
/// 서비스 꺼짐 등은 예외로 던져 호출부에서 안내한다.
Future<SeaLocation> resolveCurrentLocation() async {
  final enabled = await Geolocator.isLocationServiceEnabled();
  if (!enabled) {
    throw const _LocationException('위치 서비스가 꺼져 있습니다. 기기 설정에서 켜 주세요.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw const _LocationException('위치 권한이 없습니다. 앱 설정에서 허용해 주세요.');
  }
  final pos = await Geolocator.getCurrentPosition();
  return SeaLocation(
    id: 'gps_${pos.latitude.toStringAsFixed(4)}_${pos.longitude.toStringAsFixed(4)}',
    name: '현재 위치',
    region: '검색',
    latitude: pos.latitude,
    longitude: pos.longitude,
    inland: true,
  );
}

class _LocationException implements Exception {
  const _LocationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 현재 선택된 지점 — 홈/물때/날씨 화면이 모두 이 값을 따른다.
/// 선택은 SharedPreferences에 전체 정보(JSON)로 저장되어, 검색·현재위치 등
/// 목록에 없는 커스텀 지점도 앱 재시작 후 그대로 복원된다 (FR-10).
class SelectedLocationNotifier extends Notifier<SeaLocation> {
  static const _prefsKey = 'selected_location';
  static const _legacyIdKey = 'selected_location_id';

  @override
  SeaLocation build() {
    final all = ref.read(locationsProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        return SeaLocation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // 손상 시 아래 폴백으로.
      }
    }
    // 구버전 키(id만 저장) 호환.
    final savedId = prefs.getString(_legacyIdKey);
    return all.firstWhere((l) => l.id == savedId, orElse: () => all.first);
  }

  void select(SeaLocation location) {
    state = location;
    ref
        .read(sharedPreferencesProvider)
        .setString(_prefsKey, jsonEncode(location.toJson()));
  }
}

final selectedLocationProvider =
    NotifierProvider<SelectedLocationNotifier, SeaLocation>(
      SelectedLocationNotifier.new,
    );

/// 즐겨찾기 지점 id 집합. SharedPreferences에 영속화된다 (FR-10).
class FavoritesNotifier extends Notifier<Set<String>> {
  static const _prefsKey = 'favorite_location_ids';

  @override
  Set<String> build() {
    final saved = ref.read(sharedPreferencesProvider).getStringList(_prefsKey);
    return (saved ?? const []).toSet();
  }

  void toggle(String id) {
    state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};
    ref
        .read(sharedPreferencesProvider)
        .setStringList(_prefsKey, state.toList());
  }
}

final favoritesProvider = NotifierProvider<FavoritesNotifier, Set<String>>(
  FavoritesNotifier.new,
);
