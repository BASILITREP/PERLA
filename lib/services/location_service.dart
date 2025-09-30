// lib/location_service.dart
import 'dart:async';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class LocationService {
  final Location _location = Location();
  StreamSubscription<LocationData>? _locationSubscription;
  LocationData? _lastLocation;
  final int _fieldEngineerId;

  Timer? _liveUpdateTimer;
  Timer? _batchTimer;

  final List<Map<String, dynamic>> _locationBuffer = [];

  Stream<LocationData> get onLocationChanged => _location.onLocationChanged;

  LocationService({required int fieldEngineerId}) : _fieldEngineerId = fieldEngineerId;

  void start() {
    print("--- LocationService starting for FE ID: $_fieldEngineerId ---");
    _initializeLocation();
  }

  void stop() {
    print("--- LocationService stopping ---");
    _locationSubscription?.cancel();
    stopLiveUpdates();
    stopHistoryBatching();
  }

  Future<void> _initializeLocation() async {
    // Permission checks...
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) serviceEnabled = await _location.requestService();
    if (!serviceEnabled) {
      print("❌ GPS/Location service is NOT enabled.");
      return;
    }

    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
    }
    if (permissionGranted != PermissionStatus.granted) {
      print("❌ Location permission NOT granted.");
      return;
    }
    print("✅ Location permissions are OK.");

    _locationSubscription = _location.onLocationChanged.listen((LocationData currentLocation) {
      if (currentLocation.latitude != null && currentLocation.longitude != null) {
        _lastLocation = currentLocation;
        
        // MODIFICATION: Only add to the buffer if the history batching timer is active.
        if (_batchTimer != null && _batchTimer!.isActive) {
          _locationBuffer.add({
            'latitude': currentLocation.latitude,
            'longitude': currentLocation.longitude,
            'speed': currentLocation.speed,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          });
          print("➕ Point added to history buffer. Total points: ${_locationBuffer.length}");
        }
      }
    });

    // This timer for LIVE updates still runs all the time.
    _liveUpdateTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_lastLocation != null) {
        _sendLiveLocationToBackend(_lastLocation!);
      }
    });

    // MODIFICATION: We REMOVED the automatic start of the _batchTimer here.
  }
  
  // Public method to START the history batching timer
  void startHistoryBatching() {
    if (_batchTimer != null && _batchTimer!.isActive) {
      print("ℹ️ History batching is already active.");
      return;
    }
    print("✅ Starting history batching timer (every 2 minutes).");
    _batchTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (_locationBuffer.isNotEmpty) {
        _sendBatchToBackend();
      }
    });
  }

  // Public method to STOP the history batching timer
  void stopHistoryBatching() {
    if (_batchTimer != null && _batchTimer!.isActive) {
      print("🛑 Stopping history batching timer.");
      if (_locationBuffer.isNotEmpty) {
        _sendBatchToBackend(); // Send any remaining data before stopping
      }
      _batchTimer?.cancel();
      _batchTimer = null;
    }
  }

  void stopLiveUpdates() {
    _liveUpdateTimer?.cancel();
    _liveUpdateTimer = null;
  }

  // _sendLiveLocationToBackend implementation (replace with your full function)
  Future<void> _sendLiveLocationToBackend(LocationData locationData) async {
     try {
      final url = Uri.parse('https://ecsmapappwebadminbackend-production.up.railway.app/api/FieldEngineer/updateLocation');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'id': _fieldEngineerId,
          'currentLatitude': locationData.latitude,
          'currentLongitude': locationData.longitude,
        }),
      );
      if (response.statusCode == 200) print('📍 LIVE location update sent successfully.');
    } catch (e) {
      print('Error sending live location: $e');
    }
  }
  
  // _sendBatchToBackend implementation remains the same
  Future<void> _sendBatchToBackend() async {
    print("📦 Preparing to send batch of ${_locationBuffer.length} points...");
    final List<Map<String, dynamic>> batchToSend = List.from(_locationBuffer);
    _locationBuffer.clear();

    try {
      final url = Uri.parse('https://ecsmapappwebadminbackend-production.up.railway.app/api/Location/batch');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'fieldEngineerId': _fieldEngineerId,
          'points': batchToSend,
        }),
      );
      if (response.statusCode == 200) {
        print('✅✅✅ HISTORY batch of ${batchToSend.length} points sent successfully!');
      } else {
        print('❌❌❌ Failed to send HISTORY batch. Status: ${response.statusCode}.');
        print('Server Response Body: ${response.body}');
        _locationBuffer.insertAll(0, batchToSend);
      }
    } catch (e) {
      print('🔥🔥🔥 CRITICAL ERROR sending location batch: $e.');
      _locationBuffer.insertAll(0, batchToSend);
    }
  }
}