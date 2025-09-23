import 'dart:async';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class LocationService {
  final Location _location = Location();
  StreamSubscription<LocationData>? _locationSubscription;
  Timer? _updateTimer;
  LocationData? _lastLocation;
  final int _fieldEngineerId;

  Stream<LocationData> get onLocationChanged => _location.onLocationChanged;

  LocationService({required int fieldEngineerId}) : _fieldEngineerId = fieldEngineerId;

  void start() {
    _initializeLocation();
  }

  void stop() {
    _locationSubscription?.cancel();
    _updateTimer?.cancel();
  }

  Future<void> _initializeLocation() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) return;
    }

    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return;
    }

    // Listen for location changes continuously
    _locationSubscription = _location.onLocationChanged.listen((LocationData currentLocation) {
      _lastLocation = currentLocation;
    });

    // Set up a timer to send updates to the backend every 10 seconds
    _updateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_lastLocation != null) {
        _sendLocationToBackend(_lastLocation!);
      }
    });
  }

  Future<void> _sendLocationToBackend(LocationData locationData) async {
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

      if (response.statusCode == 200) {
        print('📍 Location updated successfully: ${locationData.latitude}, ${locationData.longitude}');
      } else {
        print('❌ Failed to update location. Status: ${response.statusCode}');
      }
    } catch (e) {
      print('Error sending location to backend: $e');
    }
  }
}