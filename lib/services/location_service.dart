import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  List<Map<String, dynamic>> locationBuffer = [];
  Timer? batchTimer;
  Timer? liveUpdateTimer;
  int? fieldEngineerId;
  Map<String, dynamic>? lastLocation;

  // Function to send LIVE location update (for real-time tracking)
  Future<void> sendLiveLocationUpdate(Map<String, dynamic> locationData) async {
    if (fieldEngineerId == null) return;
    
    try {
      final url = Uri.parse('https://ecsmapappwebadminbackend-production.up.railway.app/api/FieldEngineer/updateLocation');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'id': fieldEngineerId,
          'currentLatitude': locationData['latitude'],
          'currentLongitude': locationData['longitude'],
          'isMoving': locationData['speed'] != null && locationData['speed'] > 0.5,
        }),
      );
      if (response.statusCode == 200) {
        print('📍 LIVE location update sent successfully.');
      } else {
        print('❌ Live location failed: ${response.statusCode}');
      }
    } catch (e) {
      print('🔥 Error sending live location: $e');
    }
  }

  // Function to send location history for reverse geocoding and trip detection
  Future<void> sendLocationHistory() async {
    if (locationBuffer.isEmpty || fieldEngineerId == null) return;
    
    print("📦 Sending ${locationBuffer.length} location points for trip detection & geocoding...");
    
    // Format as List<LocationPoint> - exactly what your API expects
    final List<Map<String, dynamic>> locationPoints = locationBuffer.map((point) => {
      'fieldEngineerId': fieldEngineerId,
      'latitude': point['latitude'],
      'longitude': point['longitude'],
      'speed': point['speed'] ?? 0.0,
      'accuracy': point['accuracy'] ?? 0.0,
      'timestamp': point['timestamp'],
    }).toList();
    
    final List<Map<String, dynamic>> batchToSend = List.from(locationPoints);
    locationBuffer.clear();

    try {
      print("🔍 Sending to: /api/Location");
      print("🔍 Data sample: ${json.encode(batchToSend.take(1).toList())}");
      
      final url = Uri.parse('https://ecsmapappwebadminbackend-production.up.railway.app/api/Location');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(batchToSend),
      );
      
      print("🔍 Response status: ${response.statusCode}");
      print("🔍 Response body: ${response.body}");
      
      if (response.statusCode == 200) {
        print('✅✅✅ Location history sent successfully! Trip detection & geocoding processing...');
      } else {
        print('❌❌❌ Failed to send location history. Status: ${response.statusCode}');
        // Add back to buffer for retry
        locationBuffer.insertAll(0, locationBuffer);
      }
    } catch (e) {
      print('🔥🔥🔥 Error sending location history: $e');
      // Add back to buffer for retry  
      locationBuffer.insertAll(0, batchToSend.map((point) => {
        'latitude': point['latitude'],
        'longitude': point['longitude'],
        'speed': point['speed'],
        'accuracy': point['accuracy'],
        'timestamp': point['timestamp'],
      }).toList());
    }
  }

  // Handle incoming location data from main app
  service.on('location_update').listen((event) {
    final data = event!['data'] as Map<String, dynamic>;
    lastLocation = data;
    
    // Add to buffer for history/trip detection
    locationBuffer.add(data);
    print("📍 [Background] Location added: ${data['latitude']?.toStringAsFixed(6)}, ${data['longitude']?.toStringAsFixed(6)} (Buffer: ${locationBuffer.length})");
    
    // Update notification
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "Dorothy App",
        content: "Hello, I'm Dorothy nice to meet you",
      );
    }
  });

  // Handle service events
  service.on('setAsForeground').listen((event) {
    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }
  });

  service.on('setAsBackground').listen((event) {
    if (service is AndroidServiceInstance) {
      service.setAsBackgroundService();
    }
  });

  service.on('stopService').listen((event) {
    print("🛑 [Background] Stopping service");
    batchTimer?.cancel();
    liveUpdateTimer?.cancel();
    // Send any remaining location data before stopping
    if (locationBuffer.isNotEmpty) {
      sendLocationHistory();
    }
    service.stopSelf();
  });

  // Get Field Engineer ID
  final prefs = await SharedPreferences.getInstance();
  fieldEngineerId = prefs.getInt('fieldEngineerId');
  print("📂 [Background] Field Engineer ID: $fieldEngineerId");
  
  // Set as foreground service
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }
  
  // Start LIVE update timer (every 30 seconds for real-time admin tracking)
  liveUpdateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
    if (lastLocation != null) {
      sendLiveLocationUpdate(lastLocation!);
    }
  });
  
  // Start HISTORY batch timer (every 2 minutes for trip detection & reverse geocoding)
  batchTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
    sendLocationHistory();
  });
  
  print("🚀 [Background] ECS Location service started!");
  print("📍 Live tracking: every 30 seconds → admin sees real-time position");
  print("📦 Trip detection: every 2 minutes → reverse geocoding & trip analysis");
}

class LocationService {
  final _backgroundService = FlutterBackgroundService();
  Location? _location;
  StreamSubscription<LocationData>? _locationSubscription;
  Timer? _heartbeatTimer;

  Future<void> initialize() async {
    await _backgroundService.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: true,
        autoStart: false,
        notificationChannelId: 'dorothy_location_service',
        initialNotificationTitle: 'DOROTHY Location Service',
        initialNotificationContent: 'Location tracking active for trip detection.',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        onForeground: onStart,
        onBackground: onIosBackground,
        autoStart: false,
      ),
    );
  }

  Future<void> start(int fieldEngineerId) async {
    print("=== Starting ECS Location Service for FE ID: $fieldEngineerId ===");
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('fieldEngineerId', fieldEngineerId);
    
    _location = Location();
    
    // Check location service and permissions
    bool serviceEnabled = await _location!.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location!.requestService();
      if (!serviceEnabled) { 
        print("❌ Location service not enabled"); 
        return; 
      }
    }

    PermissionStatus permissionGranted = await _location!.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location!.requestPermission();
      if (permissionGranted != PermissionStatus.granted) { 
        print("❌ Location permission denied"); 
        return; 
      }
    }
    
    print("✅ Location permissions granted");
    
    try {
      await _backgroundService.startService();
      await _startLocationTracking();
      print("✅ ECS Location service started - Trip detection & geocoding active!");
    } catch (e) {
      print("❌ ERROR starting service: $e");
    }
  }

  Future<void> _startLocationTracking() async {
    try {
      await _location!.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 5000, // 15 seconds
        distanceFilter: 1, // 5 meters minimum movement
      );

      _locationSubscription = _location!.onLocationChanged.listen(
        (LocationData currentLocation) {
          if (currentLocation.latitude != null && currentLocation.longitude != null) {
            final locationPoint = {
              'latitude': currentLocation.latitude,
              'longitude': currentLocation.longitude,
              'speed': currentLocation.speed ?? 0.0,
              'accuracy': currentLocation.accuracy ?? 0.0,
              'timestamp': DateTime.now().toUtc().toIso8601String(),
            };
            
            print("📍 Location: ${currentLocation.latitude?.toStringAsFixed(6)}, ${currentLocation.longitude?.toStringAsFixed(6)}");
            _backgroundService.invoke('location_update', {'data': locationPoint});
          }
        },
        onError: (error) {
          print("🔥 Location stream error: $error");
        },
      );
      
      _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
        print("💓 Service active - tracking for trip detection");
      });
      
    } catch (e) {
      print("🔥 Error starting location tracking: $e");
    }
  }

  void stop() {
    print("=== Stopping ECS Location Service ===");
    _locationSubscription?.cancel();
    _heartbeatTimer?.cancel();
    _backgroundService.invoke('stopService');
  }
}