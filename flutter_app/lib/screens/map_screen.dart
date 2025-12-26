import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../providers/theme_provider.dart';
import '../data/mock_data.dart';
import '../widgets/thinking_log_overlay.dart';
import '../widgets/mode_toggle_fab.dart';
import '../widgets/narrative_bottom_sheet.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> with SingleTickerProviderStateMixin {
  bool _showThinkingLog = false;
  bool _showNarrative = false;
  late AnimationController _pulseController;
  GoogleMapController? _mapController;
  
  // 渋谷駅を初期位置に
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(35.6580, 139.7016),
    zoom: 15,
  );
  
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _mapController?.dispose();
    super.dispose();
  }
  
  void _onModeToggle() {
    // Haptic feedback
    HapticFeedback.mediumImpact();
    
    final currentMode = ref.read(emergencyModeProvider);
    ref.read(emergencyModeProvider.notifier).toggle();
    
    // Thinking Log をリセット & 再生
    ref.read(thinkingLogProvider.notifier).clear();
    setState(() {
      _showThinkingLog = true;
      _showNarrative = false;
    });
    
    _playThinkingLog(!currentMode);
    
    // マップスタイル切替
    _updateMapStyle(!currentMode);
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
  
  Set<Polyline> _buildPolylines(bool isEmergency) {
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
  
  Set<Marker> _buildMarkers() {
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
    final isEmergency = ref.watch(emergencyModeProvider);
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
            polygons: _buildPolygons(isEmergency),
            polylines: _buildPolylines(isEmergency),
            markers: _buildMarkers(),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          
          // Thinking Log オーバーレイ
          if (_showThinkingLog && !_showNarrative)
            Positioned(
              left: 0,
              right: 0,
              bottom: 100 + bottomPadding,
              child: const ThinkingLogOverlay(),
            ),
          
          // モード表示バッジ
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: _buildModeBadge(isEmergency),
          ),
          
          // ナラティブ Bottom Sheet
          if (_showNarrative)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: NarrativeBottomSheet(
                narrative: isEmergency 
                  ? MockData.emergencyModeNarration 
                  : MockData.normalModeNarration,
                isEmergency: isEmergency,
              ),
            ),
          
          // FAB - 常にBottom Sheetより上に固定
          Positioned(
            right: 16,
            bottom: 240 + bottomPadding,
            child: ModeToggleFab(
              isEmergency: isEmergency,
              onPressed: _onModeToggle,
              pulseAnimation: _pulseController,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildModeBadge(bool isEmergency) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isEmergency 
          ? Colors.red.withAlpha(230)
          : Colors.blue.withAlpha(230),
        borderRadius: BorderRadius.circular(20),
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
        ],
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
