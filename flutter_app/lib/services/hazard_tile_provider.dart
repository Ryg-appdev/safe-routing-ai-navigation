import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// 国土地理院 ハザードマップ タイルプロバイダ
/// TileProviderを直接実装して、httpで画像を取得する
class HazardTileProvider implements TileProvider {
  final String hazardType;
  final int tileSize;

  HazardTileProvider({
    required this.hazardType,
    this.tileSize = 256,
  });

  @override
  Future<Tile> getTile(int x, int y, int? zoom) async {
    // zoom can be null in some platform interfaces, but usually int
    // google_maps_flutter expects int? or int. Let's handle generic signature.
    final z = zoom ?? 0;
    
    final url = _getTileUrl(x, y, z);
    if (url.isEmpty) {
      return TileProvider.noTile;
    }

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        if (response.bodyBytes.isEmpty) {
            return TileProvider.noTile;
        }
        return Tile(tileSize, tileSize, response.bodyBytes);
      } else if (response.statusCode == 404) {
        // 404 is normal for safe areas (no hazard data) -> Silent
        return TileProvider.noTile;
      } else {
        print('[WARN] Tile fetch failed ${response.statusCode}: $url');
      }
    } catch (e) {
      print("[ERROR] Tile fetch error: $e");
    }
    return TileProvider.noTile;
  }

  String _getTileUrl(int x, int y, int zoom) {
    final baseUrl = _getBaseUrl(hazardType);
    if (baseUrl.isEmpty) return "";
    
    return "$baseUrl/$zoom/$x/$y.png";
  }

  String _getBaseUrl(String type) {
    switch (type) {
      case 'FLOOD': // 洪水浸水想定区域（想定最大規模）
        return "https://disaportaldata.gsi.go.jp/raster/01_flood_l2_shinsuishin_data";
      case 'LANDSLIDE': // 土砂災害警戒区域
        return "https://disaportaldata.gsi.go.jp/raster/05_dosha_keikai_data";
      case 'TSUNAMI': // 津波浸水想定
        return "https://disaportaldata.gsi.go.jp/raster/04_tsunami_newlegend_data";
      case 'STORM_SURGE': // 高潮浸水想定区域
        return "https://disaportaldata.gsi.go.jp/raster/03_hightide_l2_shinsuishin_data";
      default:
        return "";
    }
  }
}
