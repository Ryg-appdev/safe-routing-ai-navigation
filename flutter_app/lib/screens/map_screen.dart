import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../data/mock_data.dart';
import '../widgets/thinking_log_overlay.dart';
import '../widgets/mode_toggle_fab.dart';
import '../widgets/narrative_bottom_sheet.dart';
import '../widgets/alert_status_banner.dart';
import '../widgets/alert_detail_sheet.dart';
import '../widgets/location_selection_sheet.dart';
import '../widgets/analysis_point_detail_sheet.dart';
import '../widgets/agent_progress_widget.dart';
import '../services/api_service.dart';
import '../services/geocoding_service.dart';
import '../services/hazard_tile_provider.dart';
import 'settings_screen.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> with TickerProviderStateMixin {
  bool _showThinkingLog = false;
  bool _showNarrative = true; // 最初から表示する
  late AnimationController _pulseController;
  GoogleMapController? _mapController;
  
  // Real Data State
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  Set<Circle> _circles = {}; // For radar/pulse effect
  bool _realRouteActive = false; // Real API data is currently shown
  bool _isLoading = false; // Loading state for API calls
  Map<String, dynamic>? _alertInfo; // Current alert info from API
  String? _apiNarrative; // Narrative from API response
  LatLng? _currentLocation; // Current user location
  
  // ジオコーディングサービス
  final GeocodingService _geocodingService = GeocodingService();
  
  // 選択中のピン（地図タップ時に表示）
  LatLng? _selectedPin;
  
  // 出発地/目的地の座標（ジオコーディング結果）
  LatLng? _originLatLng;
  LatLng? _destLatLng;
  
  // Custom Marker Icons
  BitmapDescriptor? _safeMarkerIcon;
  BitmapDescriptor? _warningMarkerIcon;
  BitmapDescriptor? _riskyMarkerIcon;
  BitmapDescriptor? _pendingMarkerIcon;
  
  // 分析ポイントの詳細データを保存
  final Map<String, Map<String, dynamic>> _analysisPointData = {};
  
  // 分析ポイントのLatLngリスト（カメラ移動用）
  final List<LatLng> _analysisPoints = [];
  
  // エージェント進捗ステータス
  Map<String, AgentStatus> _agentStatuses = {};

  
  // 渋谷駅を初期位置に
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(35.6580, 139.7016),
    zoom: 15,
  );
  
  // Input Controllers (現在地はinitStateで設定)
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destController = TextEditingController();

  // Ripple Animation State
  late AnimationController _rippleController;
  Color? _rippleColor;

  @override
  void initState() {
    print('[DEBUG] initState called');
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500), // Smooth transition
    );

    _createAnalysisMarkerBitmap(level: 0).then((icon) {
      if (mounted) setState(() => _safeMarkerIcon = icon);
    });
    _createAnalysisMarkerBitmap(level: 1).then((icon) {
      if (mounted) setState(() => _warningMarkerIcon = icon);
    });
    _createAnalysisMarkerBitmap(level: 2).then((icon) {
      if (mounted) setState(() => _riskyMarkerIcon = icon);
    });
    _createAnalysisMarkerBitmap(level: 3).then((icon) {
      if (mounted) setState(() => _pendingMarkerIcon = icon);
    });
    
    // 現在地を取得して設定
    _initCurrentLocation();
  }

  /// 警報情報に基づいてタイルオーバーレイを生成
  Set<TileOverlay> _createTileOverlays(Map<String, dynamic>? alertInfo) {
    if (alertInfo == null || alertInfo['type'] == 'NONE') {
      return {};
    }

    final alertType = alertInfo['type'] as String;
    final Set<TileOverlay> overlays = {};

    // 1. 大雨警報 (RAIN) -> 洪水(FLOOD) + 土砂災害(LANDSLIDE)
    if (alertType == 'RAIN') {
      overlays.add(_buildTileOverlay('FLOOD', 0.7)); // 0.6 -> 0.7
      overlays.add(_buildTileOverlay('LANDSLIDE', 0.7));
    }
    // 2. 洪水警報 (FLOOD) -> 洪水
    else if (alertType == 'FLOOD') {
      overlays.add(_buildTileOverlay('FLOOD', 0.85)); // 0.7 -> 0.85
    }
    // 3. 津波警報 (TSUNAMI) -> 津波
    else if (alertType == 'TSUNAMI') {
      overlays.add(_buildTileOverlay('TSUNAMI', 0.85)); // 0.7 -> 0.85
    }
    // 4. 土砂災害 (LANDSLIDE) -> 土砂災害
    else if (alertType == 'LANDSLIDE') {
      overlays.add(_buildTileOverlay('LANDSLIDE', 0.85)); // 0.7 -> 0.85
    }
    // 5. 緊急モードその他 -> 洪水 + 土砂災害（デフォルト）
    // 地震(EARTHQUAKE) は表示なし（仕様通り）
    
    print('[DEBUG] _createTileOverlays type: $alertType count: ${overlays.length}');
    return overlays;
  }

  TileOverlay _buildTileOverlay(String hazardType, double opacity) {
    return TileOverlay(
      tileOverlayId: TileOverlayId('hazard_$hazardType'),
      tileProvider: HazardTileProvider(hazardType: hazardType),
      transparency: 1.0 - opacity, // Google Maps API uses transparency (0.0 opaque - 1.0 invisible)
      zIndex: 10, // ポリラインより下(ポリラインはdefault zIndex?), 基本より上
    );
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _rippleController.dispose();
    _originController.dispose();
    _destController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // level: 0 (Safe), 1 (Warning), 2 (Risky)
  Future<BitmapDescriptor> _createAnalysisMarkerBitmap({required int level}) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    final paint = Paint()..isAntiAlias = true;
    
    if (level == 2) {
      // -------------------------------
      // RISKY Style (Red Circle + ⚠️)
      // -------------------------------
      final double radius = 32.0;

      // 1. Draw outer circle (Red, semi-transparent)
      paint.style = PaintingStyle.fill;
      paint.color = Colors.red.withOpacity(0.3); // Background glow
      canvas.drawCircle(Offset(radius, radius), radius, paint);

      // 2. Draw inner circle (More opaque red)
      paint.color = Colors.red.withOpacity(0.6);
      canvas.drawCircle(Offset(radius, radius), radius * 0.7, paint);

      // 3. Draw Warning Icon
      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
      );
      textPainter.text = TextSpan(
        text: '⚠️', 
        style: TextStyle(
          fontSize: radius,
          fontFamily: 'Roboto',
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          radius - textPainter.width / 2,
          radius - textPainter.height / 2,
        ),
      );
      
      final image = await pictureRecorder.endRecording().toImage(
        (radius * 2).toInt(),
        (radius * 2).toInt(),
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
      
    } else if (level == 1) {
      // -------------------------------
      // WARNING Style (Yellow Circle + !)
      // -------------------------------
      final double radius = 28.0;

      // 1. Draw outer circle (Yellow, semi-transparent)
      paint.style = PaintingStyle.fill;
      paint.color = Colors.orangeAccent.withOpacity(0.3); 
      canvas.drawCircle(Offset(radius, radius), radius, paint);

      // 2. Draw inner circle (More opaque yellow)
      paint.color = Colors.orangeAccent.withOpacity(0.7);
      canvas.drawCircle(Offset(radius, radius), radius * 0.7, paint);

      // 3. Draw Exclamation Icon
      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
      );
      textPainter.text = TextSpan(
        text: '!', 
        style: TextStyle(
          fontSize: radius * 1.2,
          fontFamily: 'Roboto',
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          radius - textPainter.width / 2,
          radius - textPainter.height / 2,
        ),
      );
      
      final image = await pictureRecorder.endRecording().toImage(
        (radius * 2).toInt(),
        (radius * 2).toInt(),
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());

    } else if (level == 3) {
      // -------------------------------
      // PENDING Style (Small Gray Circle)
      // -------------------------------
      final double radius = 16.0;

      paint.style = PaintingStyle.fill;
      paint.color = Colors.grey.withOpacity(0.5);
      canvas.drawCircle(Offset(radius, radius), radius, paint);

      paint.color = Colors.white.withOpacity(0.8);
      canvas.drawCircle(Offset(radius, radius), radius * 0.5, paint);

      final image = await pictureRecorder.endRecording().toImage(
        (radius * 2).toInt(),
        (radius * 2).toInt(),
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());

    } else {
      // -------------------------------
      // SAFE Style (Original Cyan Circle)
      // -------------------------------
      final double radius = 24.0; 

      // Draw outer circle
      paint.style = PaintingStyle.fill;
      paint.color = Colors.cyanAccent.withOpacity(0.5);
      canvas.drawCircle(Offset(radius, radius), radius, paint);

      // Draw inner circle (solid)
      paint.color = Colors.cyanAccent;
      canvas.drawCircle(Offset(radius, radius), 10.0, paint);

      // Draw stroke
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2.0;
      paint.color = Colors.white;
      canvas.drawCircle(Offset(radius, radius), radius - 1.0, paint);

      final image = await pictureRecorder.endRecording().toImage(
        (radius * 2).toInt(),
        (radius * 2).toInt(),
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
    }
  }
  
  /// 現在地を取得してorigin fieldと地図マーカーを更新
  Future<void> _initCurrentLocation() async {
    print('[DEBUG] _initCurrentLocation called');
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      print('[DEBUG] Permission: $permission');
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // 権限がない場合はデフォルト値を使用
          print('[DEBUG] Permission denied, using default');
          _originController.text = '渋谷駅';
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        print('[DEBUG] Permission denied forever, using default');
        _originController.text = '渋谷駅';
        return;
      }
      
      print('[DEBUG] Getting current position...');
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      print('[DEBUG] Got position: ${pos.latitude}, ${pos.longitude}');
      
      if (!mounted) return;
      
      setState(() {
        _currentLocation = LatLng(pos.latitude, pos.longitude);
        _originController.text = '現在地';
        print('[DEBUG] Set origin to 現在地');
        // 起動時はマーカーを立てない（ユーザー要望）
      });
      
      // カメラを現在地に移動
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _currentLocation!,
            zoom: 15,
          ),
        ),
      );
    } catch (e) {
      // エラー時はデフォルト値を使用
      print('[DEBUG] Error in _initCurrentLocation: $e');
      if (mounted) {
        _originController.text = '渋谷駅';
      }
    }
  }
  


  /// 地図タップ時のハンドラ
  Future<void> _onMapTap(LatLng position) async {
    // 選択ピンを表示
    setState(() {
      _selectedPin = position;
    });
    
    // 逆ジオコーディングで地点名を取得
    // 逆ジオコーディングで地点名を取得 (Backend Places API)
    // 逆ジオコーディングで地点名を取得 (Backend Places API)
    // 戻り値には正確な座標(lat/lng)が含まれている場合がある
    final placeData = await ApiService().getReverseGeocode(position.latitude, position.longitude);
    
    if (!mounted) return;
    
    String? placeName;
    LatLng pinPosition = position; // デフォルトはタップ位置
    
    if (placeData != null) {
      placeName = placeData['name'];
      // POIの正確な位置があれば、ピンをそこにスナップさせる
      if (placeData['lat'] != null && placeData['lng'] != null) {
        pinPosition = LatLng(placeData['lat'], placeData['lng']);
      }
    }
    
    // ピン位置を更新 (スナップ)
    setState(() {
      _selectedPin = pinPosition;
    });
    
    // シートを表示（コンテキストが有効な場合のみ）
    if (!context.mounted) return;
    
    showLocationSelectionSheet(
      context: context,
      position: pinPosition,
      placeName: placeName,
      onSetAsOrigin: () {
        setState(() {
          _originController.text = placeName ?? '選択した地点';
          _originLatLng = pinPosition;
          _selectedPin = null;
        });
      },
      onSetAsDestination: () {
        setState(() {
          _destController.text = placeName ?? '選択した地点';
          _destLatLng = pinPosition;
          _selectedPin = null;
        });
      },
      onDismiss: () {
        // シートが閉じられたら選択ピンを消す
        if (mounted) {
          setState(() {
            _selectedPin = null;
          });
        }
      },
    );
  }
  


  
  /// すべてのマーカーを構築
  Set<Marker> _buildAllMarkers() {
    final markers = <Marker>{};
    
    // APIルートのマーカー
    if (_realRouteActive) {
      markers.addAll(_markers);
    }
    
    // 現在地マーカーは起動時には立てない（myLocationEnabledで青い点が表示される）
    
    // 選択ピン（地図タップ時）
    if (_selectedPin != null) {
      markers.add(Marker(
        markerId: const MarkerId('selected_pin'),
        position: _selectedPin!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
      ));
    }
    
    // 出発地マーカー（設定済みの場合は常に表示）- 青色
    if (_originLatLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('origin'),
        position: _originLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(title: _originController.text),
      ));
    }
    
    // 目的地マーカー（設定済みの場合は常に表示）
    if (_destLatLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: _destLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: _destController.text),
      ));
    }
    
    return markers;
  }
  
  /// 入力フィールドの値をジオコーディングしてカメラを移動
  Future<void> _geocodeAndMoveCamera(String query, {required bool isOrigin}) async {
    if (query.isEmpty) return;
    
    // 「現在地」の場合は現在地座標を使用
    if (query == '現在地' && _currentLocation != null) {
      if (isOrigin) {
        _originLatLng = _currentLocation;
      } else {
        _destLatLng = _currentLocation;
      }
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(_currentLocation!),
      );
      return;
    }
    
    // ジオコーディングで座標を取得
    final latLng = await _geocodingService.geocodeAddress(query);
    if (latLng != null && mounted) {
      setState(() {
        if (isOrigin) {
          _originLatLng = latLng;
        } else {
          _destLatLng = latLng;
        }
      });
      
      // カメラを該当地点に移動
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(latLng),
      );
    }
  }
  
  Future<void> _onModeToggle() async {
    // Haptic feedback
    HapticFeedback.mediumImpact();
    
    final currentMode = ref.read(emergencyModeProvider);
    final nextIsEmergency = !currentMode;
    
    // 1. Setup Ripple Color
    
    setState(() {
      _rippleColor = nextIsEmergency ? const Color(0xFFFF3B30) : const Color(0xFF007AFF);
    });
    
    // 2. Animate Ripple
    await _rippleController.forward();
    
    // 3. Toggle Actual State
    ref.read(emergencyModeProvider.notifier).toggle();
    _updateMapStyle(nextIsEmergency);
    
    // モード切替時は Thinking Log を表示しない
    // ナラティブのみ表示
    setState(() {
      _showThinkingLog = false;
      _showNarrative = true;
    });
    
    // 4. Reset Ripple (Invisible instant reset)
    _rippleController.reset();
    setState(() {
      _rippleColor = null; // Hide overlay
    });
  }
  
  void _updateMapStyle(bool isEmergency) {
    if (_mapController == null) return;
    
    if (isEmergency) {
      // ダークモードスタイル
      _mapController!.setMapStyle(_darkMapStyle);
    } else {
      // 標準スタイル
      _mapController!.setMapStyle(null);
    }
  }
  
  Future<void> _playThinkingLog(bool isEmergency) async {
    final logs = isEmergency 
      ? MockData.emergencyThinkingLog 
      : MockData.normalThinkingLog;
    
    for (final log in logs) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      ref.read(thinkingLogProvider.notifier).add(log);
    }
    
    // ログ完了後、ナラティブ表示
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() {
      _showNarrative = true;
    });
  }
  
  /// Thinking Log に1行追加（ディレイ付き）
  Future<void> _addThinkingLog(String message) async {
    if (!mounted) return;
    ref.read(thinkingLogProvider.notifier).add(message);
    await Future.delayed(const Duration(milliseconds: 150));
  }
  
  /// 現在のナラティブを生成（動的）
  /// alertInfo は effectiveAlertProvider から取得して渡す
  String _getCurrentNarrative(bool isEmergency, Map<String, dynamic>? alertInfo) {
    // 1. API レスポンスのナラティブがあればそれを使用
    if (_apiNarrative != null && _apiNarrative!.isNotEmpty) {
      return _apiNarrative!;
    }
    
    // 2. 警報情報に基づくナラティブ
    if (alertInfo != null && alertInfo['type'] != 'NONE') {
      final alertType = alertInfo['type'];
      final message = alertInfo['message'];
      
      // スタブまたは実APIからのmessageがあれば使用
      if (message != null) return message;
      
      // 警報タイプ別のデフォルトメッセージ
      switch (alertType) {
        case 'TSUNAMI':
          return '🌊 津波警報が発令されています。高台への避難ルートを優先して案内します。';
        case 'EARTHQUAKE':
          return '🔴 地震が発生しました。広い道を優先し、倒壊リスクのある建物を避けてご案内します。';
        case 'RAIN':
          return '⚠️ 大雨警報が発令されています。低地や川の近くを避けてご案内します。';
        case 'FLOOD':
          return '🌊 洪水警報が発令されています。浸水リスクのあるエリアを回避します。';
        case 'LANDSLIDE':
          return '⛰️ 土砂災害警戒情報が発令されています。山沿いを避けてご案内します。';
      }
    }
    
    // 3. モードに応じたデフォルトメッセージ
    if (isEmergency) {
      return '緊急モードに切り替えました。現在、警報・注意報は発令されていません。手動で安全ルートを検索できます。';
    }
    
    // 4. 時間帯に応じた挨拶（通常モード）
    final hour = DateTime.now().hour;
    if (hour >= 22 || hour < 5) {
      // 22時〜翌5時: 深夜
      return '深夜のお出かけですね。安全なルートを優先してご案内します。';
    } else if (hour < 10) {
      // 5時〜10時: 朝
      return 'おはようございます。今日も安全なルートでご案内します。';
    } else if (hour < 17) {
      // 10時〜17時: 昼
      return 'こんにちは！目的地を入力してナビを開始してください。';
    } else {
      // 17時〜22時: 夕方
      return 'お疲れ様です。帰り道は明るい道をご案内しますね。';
    }
  }
  
  Set<Polygon> _buildPolygons(bool isEmergency) {
    if (!isEmergency) return {};
    
    // 浸水エリアのポリゴン（赤い半透明）
    return {
      Polygon(
        polygonId: const PolygonId('flood_zone'),
        points: MockData.floodZone,
        fillColor: Colors.red.withAlpha(100),
        strokeColor: Colors.red,
        strokeWidth: 2,
      ),
    };
  }
  
  Set<Polyline> _buildMockPolylines(bool isEmergency) {
    if (!_showNarrative) return {};
    
    // ルートのポリライン
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: isEmergency ? MockData.safeRoute : MockData.unsafeRoute,
        color: isEmergency ? Colors.orange : Colors.blue,
        width: 6,
      ),
    };
  }
  
  Set<Marker> _buildMockMarkers() {
    return {
      Marker(
        markerId: const MarkerId('origin'),
        position: MockData.shibuyaStation,
        infoWindow: const InfoWindow(title: '渋谷駅'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ),
      Marker(
        markerId: const MarkerId('destination'),
        position: MockData.destination,
        infoWindow: const InfoWindow(title: '目的地'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    // Watch emergency mode state
    final isEmergency = ref.watch(emergencyModeProvider);
    final _alertInfo = ref.watch(effectiveAlertProvider);
    
    // Auto-switch to Emergency Mode when alert is detected
    ref.listen(effectiveAlertProvider, (previous, next) {
      if (next != null && 
          next['should_emergency_mode'] == true && 
          !ref.read(emergencyModeProvider)) {
            
        ref.read(emergencyModeProvider.notifier).set(true);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${next['icon']} ${next['title']} - 緊急モードに自動切替'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
    
    // Bottom sheet sizes
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return Scaffold(
      body: Stack(
        children: [
          // Google Maps
          GoogleMap(
            initialCameraPosition: _initialPosition,

            onMapCreated: (controller) {
              _mapController = controller;
              if (isEmergency) {
                controller.setMapStyle(_darkMapStyle);
              }
            },
            onTap: _onMapTap,
            polygons: _realRouteActive ? _buildPolygons(isEmergency) : {},
            polylines: _realRouteActive ? _polylines : {},
            markers: _buildAllMarkers(),
            circles: _realRouteActive ? _circles : {},
            tileOverlays: _createTileOverlays(_alertInfo),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            padding: const EdgeInsets.only(
              top: 260.0,    // Search Bar Area (Reduced slightly)
              bottom: 320.0, // Bottom Sheet Area (Reduced to minimize dead space)
              left: 0.0,
              right: 0.0,
            ),
          ),
          
          // Fade Overlay (Smooth theme transition)
          if (_rippleColor != null)
          AnimatedBuilder(
            animation: _rippleController,
            builder: (context, child) {
              // Smooth curve for fade in/out
              final opacity = Curves.easeInOut.transform(_rippleController.value) * 0.5;
              
              return Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: _rippleColor!.withOpacity(opacity),
                  ),
                ),
              );
            },
          ),
          
          // Thinking Log オーバーレイ（画面下に配置）
          // ロード中はエージェント進捗表示、そうでなければコンソールログ
          if (_showThinkingLog && !_showNarrative)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomPadding + 16, // safe area + マージン
              child: _isLoading
                ? AgentProgressWidget(agentStatuses: _agentStatuses)
                : const ThinkingLogOverlay(),
            ),
          
          // Mode Badge (Tappable) and Settings Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Row(
              children: [
                // Mode Badge
                GestureDetector(
                  onTap: _onModeToggle,
                  child: _buildModeBadge(isEmergency),
                ),
                const SizedBox(width: 8),
                // Alert Status Banner
                // effectiveAlertProvider を使用（テスト警報が設定されていればそれを優先表示）
                // Alert Status Banner
                // effectiveAlertProvider を使用（テスト警報が設定されていればそれを優先表示）
                Expanded(
                  child: Consumer(
                    builder: (context, ref, child) {
                      final alertInfo = ref.watch(effectiveAlertProvider);
                      return AlertStatusBanner(
                        alertInfo: alertInfo,
                        isCompact: true,
                        onTap: () => showAlertDetailSheet(context, alertInfo),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // Settings Button - minimal style
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SettingsScreen()),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isEmergency 
                              ? Colors.black.withOpacity(0.3) 
                              : Colors.white.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.settings_outlined,
                          color: isEmergency ? Colors.white70 : Colors.grey[600],
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Search Form (Improved visibility)
          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            left: 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: isEmergency ? const Color(0xE01C1C1E) : const Color(0xF0FFFFFF),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left Column: Icons with dotted line
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Origin Icon
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.circle, color: Colors.blue, size: 10),
                        ),
                        // Dotted Line
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            children: List.generate(3, (i) => Container(
                              width: 2,
                              height: 4,
                              margin: const EdgeInsets.symmetric(vertical: 1),
                              decoration: BoxDecoration(
                                color: isEmergency ? Colors.white30 : Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            )),
                          ),
                        ),
                        // Destination Icon
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.location_on, color: Colors.red, size: 10),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    // Middle Column: Text Inputs
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 出発地 Input
                          TextField(
                            controller: _originController,
                            style: TextStyle(
                              color: isEmergency ? Colors.white : Colors.black87,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: '出発地を入力',
                              hintStyle: TextStyle(color: isEmergency ? Colors.white38 : Colors.black38),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onTap: () {
                              // タップ時に全選択（Google Mapsと同じ挙動）
                              _originController.selection = TextSelection(
                                baseOffset: 0,
                                extentOffset: _originController.text.length,
                              );
                            },
                            onSubmitted: (value) => _geocodeAndMoveCamera(value, isOrigin: true),
                          ),
                          Divider(height: 1, color: isEmergency ? Colors.white12 : Colors.grey.shade200),
                          // 目的地 Input
                          TextField(
                            controller: _destController,
                            style: TextStyle(
                              color: isEmergency ? Colors.white : Colors.black87,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: '目的地を入力',
                              hintStyle: TextStyle(color: isEmergency ? Colors.white38 : Colors.black38),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onTap: () {
                              // タップ時に全選択（Google Mapsと同じ挙動）
                              _destController.selection = TextSelection(
                                baseOffset: 0,
                                extentOffset: _destController.text.length,
                              );
                            },
                            onSubmitted: (value) => _geocodeAndMoveCamera(value, isOrigin: false),
                          ),
                        ],
                      ),
                    ),
                    // Right Column: Start Button
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 50,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleStartNavigation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isEmergency ? Colors.red : Colors.blue,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.arrow_forward, size: 24),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          if (_showNarrative)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Consumer(
                builder: (context, ref, child) {
                  final effectiveAlert = ref.watch(effectiveAlertProvider);
                  return NarrativeBottomSheet(
                    narrative: _getCurrentNarrative(isEmergency, effectiveAlert),
                    isEmergency: isEmergency,
                  );
                },
              ),
            ),
          
          // Current Location Button (Compact)
          Positioned(
            right: 16,
            bottom: 240 + bottomPadding,
            child: FloatingActionButton(
              heroTag: 'location_fab',
              mini: true,
              backgroundColor: isEmergency ? Colors.grey[800] : Colors.white,
              foregroundColor: isEmergency ? Colors.white : Colors.black87,
              onPressed: _moveToCurrentLocation,
              child: const Icon(Icons.near_me),
            ),
          ),

        ],
      ),
    );
  }
  
  Future<void> _handleStartNavigation() async {
    if (!mounted || _isLoading) return;
    HapticFeedback.mediumImpact();
    
    setState(() => _isLoading = true);

    // Clear previous results
    setState(() {
      _markers.clear();
      _polylines.clear();
      _realRouteActive = true;
      _analysisPoints.clear();
      // エージェント進捗を初期化（状況判断は開始時から処理中）
      _agentStatuses = {
        'sentinel': AgentStatus(status: 'processing', progress: 10, message: '処理を開始...'),
      };
      // _routeLegs.clear(); // This variable is not defined in the provided context
      // _totalDistance = ''; // This variable is not defined in the provided context
      // _totalDuration = ''; // This variable is not defined in the provided context
      // _summary = 'ルート探索中...';
      // _streamingStatus = '接続中...';
       // Reset Icons -> DO NOT RESET THESE! They are cached.
       // Clearing them caused markers to not appear if analysis happened before re-init.
      // _safeMarkerIcon = null;
      // _warningMarkerIcon = null;
      // _riskyMarkerIcon = null;
    });

    // Re-generate icons just in case (though they are cached)
    // _createAnalysisMarkerBitmap(level: 0).then((icon) => _safeMarkerIcon = icon); // This method is not defined in the provided context
    // _createAnalysisMarkerBitmap(level: 1).then((icon) => _warningMarkerIcon = icon); // This method is not defined in the provided context
    // _createAnalysisMarkerBitmap(level: 2).then((icon) => _riskyMarkerIcon = icon); // This method is not defined in the provided context

    // 座標が未設定の場合（テキスト入力のみの場合）、ジオコーディングを実行
    if (_originLatLng == null && _originController.text.isNotEmpty) {
       await _geocodeAndMoveCamera(_originController.text, isOrigin: true);
    }
    if (_destLatLng == null && _destController.text.isNotEmpty) {
       await _geocodeAndMoveCamera(_destController.text, isOrigin: false);
    }

    if (_originLatLng != null && _destLatLng != null) {
        // Move camera to fit bounds of Origin and Dest immediately
        // Wait a small frame to ensure map is ready/layout is updated
        await Future.delayed(const Duration(milliseconds: 100));
        _fitBounds(_originLatLng!, _destLatLng!);
    }
    
    final api = ApiService();
    final isEmergency = ref.read(emergencyModeProvider);
    // Determine current Alert Mode for the API request
    final alertStatus = ref.read(effectiveAlertProvider);
    
    // Thinking Log を表示開始
    ref.read(thinkingLogProvider.notifier).clear();
    setState(() {
      _showThinkingLog = true;
      _showNarrative = false;
    });
    
    // リアルタイムでログを追加（コンソール風・日本語寄り）
    await _addThinkingLog('> ルート検索を初期化中...');
    await _addThinkingLog('> モード: ${isEmergency ? "EMERGENCY" : "NORMAL"}');
    await _addThinkingLog('> 出発地: ${_originController.text}');
    await _addThinkingLog('> 目的地: ${_destController.text}');
    await _addThinkingLog('> AIエージェントに接続中...');

    try {
      // 座標が取得済みの場合はそれを使用、そうでなければテキストを使用
      String origin;
      if (_originLatLng != null) {
        origin = '${_originLatLng!.latitude},${_originLatLng!.longitude}';
      } else if (_originController.text == '現在地' && _currentLocation != null) {
        // 現在地の場合、座標をセットしてマーカーを表示させる
        setState(() {
          _originLatLng = _currentLocation;
        });
        origin = '${_currentLocation!.latitude},${_currentLocation!.longitude}';
      } else {
        origin = _originController.text;
      }
      
      String dest;
      if (_destLatLng != null) {
        dest = '${_destLatLng!.latitude},${_destLatLng!.longitude}';
      } else {
        dest = _destController.text;
      }
      
      // Start時にカメラ位置を調整 (もし座標があれば)
      // Removed: if (_originLatLng != null && _destLatLng != null) { _fitBounds([_originLatLng!, _destLatLng!]); }
      // Removed: else if (_currentLocation != null && _destLatLng != null) { _fitBounds([_currentLocation!, _destLatLng!]); }

      // SSE Stream Start
      
      // SSEストリームで処理中ステータスをリアルタイム受信
      Map<String, dynamic>? finalResult;
      
      // テスト用警報が設定されている場合、APIに渡す
      final testAlert = ref.read(testAlertProvider);
      
      await for (final event in api.findSafeRouteStream(origin, dest, testAlert: testAlert)) {
        if (!mounted) break;
        
        final type = event['type'];
        
        if (type == 'status') {
          // ステータスイベント: リアルタイムでログ表示
          final agent = event['agent'] ?? 'System';
          final message = event['message'] ?? '';
          await _addThinkingLog('> [$agent] $message');
          
        } else if (type == 'agent_status') {
          // エージェント進捗表示: プログレスバー更新
          final agent = event['agent'] as String?;
          if (agent != null) {
            setState(() {
              _agentStatuses = Map.from(_agentStatuses);
              _agentStatuses[agent] = AgentStatus.fromJson(event);
            });
          }
          // ログにも追加
          final message = event['message'] ?? '';
          await _addThinkingLog('> [${agent ?? "System"}] $message');
          
        } else if (type == 'sampling_points') {
          // サンプリングポイント先行表示（グレーマーカー）
          final points = event['points'] as List?;
          if (points != null && points.isNotEmpty && _pendingMarkerIcon != null) {
            setState(() {
              for (var p in points) {
                final lat = (p['lat'] as num).toDouble();
                final lng = (p['lng'] as num).toDouble();
                final markerId = 'analysis_${lat}_${lng}';
                
                _markers.add(Marker(
                  markerId: MarkerId(markerId),
                  position: LatLng(lat, lng),
                  icon: _pendingMarkerIcon!,
                  anchor: const Offset(0.5, 0.5),
                  consumeTapEvents: true,
                  zIndex: 0,
                ));
              }
            });
          }
          
        } else if (type == 'candidate_routes') {
          // 候補ルート表示 (薄いグレー)
          final routes = event['routes'] as List;
          final newPolylines = <Polyline>{};
          for (var r in routes) {
            final encoded = r['polyline'];
            if (encoded != null) {
              newPolylines.add(Polyline(
                polylineId: PolylineId('candidate_${r['index']}'),
                points: _decodePolyline(encoded),
                color: Colors.grey.withOpacity(0.8), // より濃く
                width: 5,
              ));
            }
          }
          setState(() {
             _realRouteActive = true; 
             // 候補ルートのみ表示（最初は）
             _polylines = newPolylines;
          });
          
        } else if (type == 'analysis_point') {
          // 分析ポイントのアニメーション表示
          // Circleだとズームでサイズが変わるため、Markerを使用
          final point = event['point'];
          if (point != null) {
             final lat = (point['lat'] as num).toDouble();
             final lng = (point['lng'] as num).toDouble();
             final score = (point['score'] as num?)?.toDouble() ?? 50.0;
             final risks = (point['risks'] as List?)?.cast<String>() ?? [];
             final imageUrl = point['image_url'] as String?;
             final atmosphere = point['atmosphere'] as String?;
             
             final markerId = 'analysis_${lat}_${lng}';
             
             // ポイントデータを保存
             _analysisPointData[markerId] = {
               'lat': lat,
               'lng': lng,
               'score': score,
               'risks': risks,
               'image_url': imageUrl,
               'atmosphere': atmosphere,
             };
             
             // マーカーを追加
             // スコアに応じてアイコンを使い分け
             // < 50: 危険 (Red Warning)
             // < 70: 注意 (Yellow Warning)
             // >= 70: 安全 (Cyan Circle)
             final BitmapDescriptor? icon;
             if (score < 50) {
               icon = _riskyMarkerIcon;
             } else if (score < 70) {
               icon = _warningMarkerIcon;
             } else {
               icon = _safeMarkerIcon;
             }
             
             if (icon != null) {
               setState(() {
                 _markers.add(Marker(
                   markerId: MarkerId(markerId),
                   position: LatLng(lat, lng),
                   icon: icon!,
                   anchor: const Offset(0.5, 0.5), // 中心をアンカーに
                   onTap: () {
                     // タップで詳細シートを表示
                     final data = _analysisPointData[markerId];
                     if (data != null) {
                       showAnalysisPointDetailSheet(
                         context: context,
                         lat: data['lat'],
                         lng: data['lng'],
                         score: data['score'],
                         risks: List<String>.from(data['risks']),
                         imageUrl: data['image_url'],
                         atmosphere: data['atmosphere'],
                       );
                     }
                   },
                 ));
               });
             }
             // 少し待つことで「ポコポコ感」を演出
             await Future.delayed(const Duration(milliseconds: 50));
          }

        } else if (type == 'result') {
          // 最終結果
          finalResult = event['data'];
          break;
          
        } else if (type == 'error') {
          throw Exception(event['message']);
        }
      }
      
      if (finalResult == null || !mounted) {
        throw Exception('No result received');
      }
      
      final routeData = finalResult['route_data'];
      if (routeData == null) throw Exception("No route data in response");

      final String encodedPolyline = routeData['best_route_encoding'];
      final List<LatLng> routePoints = _decodePolyline(encodedPolyline);
      
      final List<dynamic> waypoints = routeData['waypoints'] ?? [];
      // final Set<Marker> riskMarkers = _createRiskMarkers(waypoints); // Duplicate removed
      
      // 出発地・目的地マーカーを作成
      final originPoint = routePoints.first;
      final destPoint = routePoints.last;
      final originMarker = Marker(
        markerId: const MarkerId('origin'),
        position: originPoint,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: InfoWindow(title: '出発地', snippet: _originController.text),
      );
      final destMarker = Marker(
        markerId: const MarkerId('destination'),
        position: destPoint,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: '目的地', snippet: _destController.text),
      );
      
      setState(() {
        _realRouteActive = true;
        _circles = {}; // アニメーション用の円をクリア
        // APIからのナラティブを保存 (finalResultはSSEのresultイベントのdata部分)
        final narrative = finalResult?['narrative'];
        print('[DEBUG] API Narrative: $narrative');
        if (narrative != null && narrative is String) {
          _apiNarrative = narrative;
        }
        
        // 最終ルートを上書き（候補ルートを消して、確定ルートを表示）
        _polylines = {
          Polyline(
            polylineId: const PolylineId('real_safe_route'),
            points: routePoints,
            color: ref.read(emergencyModeProvider) ? Colors.red : Colors.blue,
            width: 6,
            startCap: Cap.roundCap,
            endCap: Cap.buttCap,
            zIndex: 10, // 最前面に表示
          ),
          // もし候補ルートも薄く残したいならここで追加
        };
        // 分析ポイントマーカーを保持
        final analysisMarkers = _markers.where(
          (m) => m.markerId.value.startsWith('analysis_')
        ).toSet();
        
        _markers = {
          originMarker,
          destMarker,
          // ...riskMarkers, // Removed to avoid duplicates
          // ...riskMarkers, // Removed to avoid duplicates
          ...analysisMarkers, // 分析ポイントを保持
        };
      });

      _fitBounds(originPoint, destPoint);

      final score = routeData['risk_assessment']?['score'] ?? 'N/A';
      
      // Update alert info from API response
      final alertInfo = finalResult['alert_info'];
      if (alertInfo != null) {
        setState(() {
          _alertInfo = alertInfo;
        });
        
        // 本番APIからの警報情報をProviderにも保存
        ref.read(realAlertProvider.notifier).set(alertInfo);
      }
      
      // 最終結果を表示
      await _addThinkingLog('> ルート解析完了');
      await _addThinkingLog('> 安全スコア: $score');
      
      // ログ完了後、少し待ってからナラティブに切り替え
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() {
          _showThinkingLog = false;
          _showNarrative = true;
        });
      }
      
    } catch (e) {
      if (!mounted) return;
      await _addThinkingLog('> エラー: $e');
      await Future.delayed(const Duration(seconds: 1));
      setState(() {
        _showThinkingLog = false;
        _showNarrative = true;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _moveToCurrentLocation() async {
    HapticFeedback.lightImpact();
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('📍 位置情報の権限がありません'))
          );
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📍 設定から位置情報を許可してください'))
        );
        return;
      }
      
      final pos = await Geolocator.getCurrentPosition();
      
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(pos.latitude, pos.longitude),
            zoom: 16,
            tilt: 45,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('📍 現在地取得に失敗: $e'), backgroundColor: Colors.orange)
      );
    }
  }

  // --- Camera Control ---
  void _fitBounds(LatLng p1, LatLng p2) {
    if (_mapController == null) return;
    
    double minLat = p1.latitude < p2.latitude ? p1.latitude : p2.latitude;
    double maxLat = p1.latitude > p2.latitude ? p1.latitude : p2.latitude;
    double minLng = p1.longitude < p2.longitude ? p1.longitude : p2.longitude;
    double maxLng = p1.longitude > p2.longitude ? p1.longitude : p2.longitude;
    
    // UIのPaddingはすでにGoogleMap側で確保済みなので、
    // ここで追加するマージンは最小限(20.0)にして、なるべく大きく表示する。
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        20.0, 
      ),
    ); 


  }

  // --- Helper Methods ---

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  Set<Marker> _createRiskMarkers(List<dynamic> waypoints) {
    Set<Marker> markers = {};
    
    for (int i = 0; i < waypoints.length; i++) {
      final wp = waypoints[i];
      final risks = List<String>.from(wp['risks'] ?? []);
      final double lat = wp['lat'];
      final double lng = wp['lng'];
      final LatLng pos = LatLng(lat, lng);

      final double? score = wp['score'] is num ? (wp['score'] as num).toDouble() : null;

      // Filter: Only show RISKY points (low score)
      // High score = safe = don't show
      // Low score = risky = show
      if (score == null || score >= 70) continue;

      // Determine Icon based on Risk Level first, then Type
      // Default: Warning (Yellow)
      BitmapDescriptor icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
      String title = "注意ポイント";
      
      // 1. High Danger (Score < 50) -> RED + Radar Circle
      if (score != null && score < 50) {
        icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
        title = "⚠️ 危険エリア";
        
        // Add Radar Circle (Pseudo-Pulse)
        _circles.add(
          Circle(
            circleId: CircleId('pulse_$i'),
            center: pos,
            radius: 40, // meters
            fillColor: Colors.red.withOpacity(0.3),
            strokeColor: Colors.red,
            strokeWidth: 2,
          )
        );
      } 
      // 2. Specific Risk Types
      else if (risks.any((r) => r.contains("FLOOD"))) {
        icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan); 
        title = "浸水リスク";
      } else if (risks.any((r) => r.contains("SHADOW"))) {
         icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet); 
         title = "暗がり注意";
      } else if (risks.any((r) => r.contains("VIBE"))) {
         icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
         title = "雰囲気注意";
      } else if (risks.any((r) => r.contains("SAFETY"))) {
         icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
         title = "安全スポット";
      }

      // Format snippet text
      String snippet = risks.map((r) {
        String text = r;
        if (text.contains("VIBE_RISK:")) text = text.replaceFirst("VIBE_RISK: ", "👁️ ");
        if (text.contains("SHADOW_RISK:")) text = text.replaceFirst("SHADOW_RISK: ", "🌑 ");
        if (text.contains("FLOOD_RISK:")) text = text.replaceFirst("FLOOD_RISK: ", "🌊 ");
        if (text.contains("SAFETY_BONUS:")) text = text.replaceFirst("SAFETY_BONUS: ", "✅ ");
        return text;
      }).join("\n");

      markers.add(
        Marker(
          markerId: MarkerId('risk_$i'),
          position: pos,
          icon: icon,
          onTap: () {
            _showRiskDetailSheet(title, score, snippet);
          }
        ),
      );
    }
    return markers;
  }
  
  void _showRiskDetailSheet(String title, double? score, String snippet) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ref.read(emergencyModeProvider) ? const Color(0xFF1c1c1e) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0,4))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    title.contains("安全") ? Icons.check_circle : Icons.warning_amber_rounded,
                    color: title.contains("安全") ? Colors.green : (score != null && score < 50 ? Colors.red : Colors.orange),
                    size: 28
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: ref.read(emergencyModeProvider) ? Colors.white : Colors.black87
                    ),
                  ),
                  const Spacer(),
                  if(score != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: score < 50 ? Colors.red : (score > 80 ? Colors.green : Colors.orange),
                      borderRadius: BorderRadius.circular(8)
                    ),
                    child: Text(
                      "Score: ${score.round()}",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  )
                ],
              ),
              const Divider(height: 24),
              Text(
                snippet, 
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: ref.read(emergencyModeProvider) ? Colors.white70 : Colors.black87
                )
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  
  // Removed duplicate _fitBounds (List<LatLng>) to avoid conflict
  // We use the 2-point version for origin/dest.
  // If list version is needed, we should rename it or overload it properly.
  // For now, removing it to fix the build error.

  Widget _buildModeBadge(bool isEmergency) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: null, // Handled by parent GestureDetector
        borderRadius: BorderRadius.circular(24),
        splashColor: Colors.white24,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isEmergency 
              ? Colors.red.withAlpha(230)
              : Colors.blue.withAlpha(230),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: (isEmergency ? Colors.red : Colors.blue).withAlpha(77),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isEmergency ? Icons.warning_rounded : Icons.wb_sunny,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                isEmergency ? 'EMERGENCY' : 'NORMAL',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 6),
              // Swap indicator
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.swap_horiz,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ダークモードのマップスタイル
const String _darkMapStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [{"color": "#242f3e"}]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#746855"}]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [{"color": "#242f3e"}]
  },
  {
    "featureType": "administrative.locality",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#d59563"}]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [{"color": "#38414e"}]
  },
  {
    "featureType": "road",
    "elementType": "geometry.stroke",
    "stylers": [{"color": "#212a37"}]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [{"color": "#746855"}]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [{"color": "#17263c"}]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#515c6d"}]
  }
]
''';
