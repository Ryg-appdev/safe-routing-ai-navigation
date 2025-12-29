import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// ジオコーディングサービス
/// 住所/地点名 ↔ 座標 の相互変換
class GeocodingService {
  /// 住所または地点名から座標を取得
  /// 例: "渋谷駅" → LatLng(35.658, 139.701)
  Future<LatLng?> geocodeAddress(String address) async {
    try {
      // 日本語の地点名にも対応
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        print('[Geocoding] "$address" → (${loc.latitude}, ${loc.longitude})');
        return LatLng(loc.latitude, loc.longitude);
      }
    } catch (e) {
      print('[Geocoding] Error geocoding "$address": $e');
    }
    return null;
  }
  
  /// 座標から住所/地点名を取得（逆ジオコーディング）
  /// 例: LatLng(35.658, 139.701) → "渋谷駅"
  Future<String?> reverseGeocode(LatLng position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        // 日本の住所形式で返す
        final address = _formatJapaneseAddress(place);
        print('[Geocoding] (${position.latitude}, ${position.longitude}) → "$address"');
        return address;
      }
    } catch (e) {
      print('[Geocoding] Error reverse geocoding: $e');
    }
    return null;
  }
  
  /// 日本の住所形式にフォーマット
  String _formatJapaneseAddress(Placemark place) {
    final parts = <String>[];
    
    // 施設名がある場合はそれを優先
    if (place.name != null && place.name!.isNotEmpty && place.name != place.street) {
      parts.add(place.name!);
    }
    
    // 住所を構築（日本式: 都道府県 → 市区町村 → 番地）
    if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
      parts.add(place.administrativeArea!); // 都道府県
    }
    if (place.locality != null && place.locality!.isNotEmpty) {
      parts.add(place.locality!); // 市区町村
    }
    if (place.subLocality != null && place.subLocality!.isNotEmpty) {
      parts.add(place.subLocality!); // 町名
    }
    if (place.thoroughfare != null && place.thoroughfare!.isNotEmpty) {
      parts.add(place.thoroughfare!); // 通り名
    }
    
    // 何も取得できなかった場合は座標を返す
    if (parts.isEmpty) {
      return '選択した地点';
    }
    
    // 最初の要素（施設名または最も詳細な住所部分）を返す
    return parts.first;
  }
}
