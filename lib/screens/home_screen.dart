import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:ui' as ui;
import 'package:geolocator/geolocator.dart' as geolocator;
import '../services/location_service.dart';
import 'dart:async';
import 'package:location/location.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'package:intl/intl.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:battery_plus/battery_plus.dart';
import 'package:timelines_plus/timelines_plus.dart';
import 'package:app_app_test/widgets/service_request_timeline.dart';
import 'package:app_app_test/widgets/field_engineer_profile.dart';
import 'package:app_app_test/widgets/service_request_list.dart';
import 'package:app_app_test/widgets/ongoing_routes_panel.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.title,
    required this.fieldEngineer,
  });

  final String title;
  final Map<String, dynamic> fieldEngineer;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<dynamic> serviceRequests = [];
  List<dynamic> branches = [];
  List<Map<String, dynamic>> ongoingRoutes = [];
  bool isLoading = false;
  String? fcmToken;
  MapboxMap? _mapboxController;
  final GlobalKey _branchIconKey = GlobalKey();
  Uint8List? _branchIconBytes;
  late final LocationService _locationService;
  StreamSubscription<geolocator.Position>? _positionStream;
  Timer? _proximityCheckTimer;
  StreamSubscription<LocationData>? _locationStreamSubscription;
  bool _isNavigationMode = false;
  Map<String, dynamic>? _activeNavigationRoute;
  final Battery _battery = Battery();
  int _batteryLevel = 0;

  // FCM and Local Notifications
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initializeFCM();
    fetchServiceRequests();
    fetchBranches();
    // Initialize and start the location service
    _locationService = LocationService(
      fieldEngineerId: widget.fieldEngineer['id'],
    );
    _locationService.start();
    _checkForActiveAssignmentOnStartup();
    _fetchBatteryLevel();

    _locationStreamSubscription = _locationService.onLocationChanged.listen((
      LocationData newLocation,
    ) {
      // This will be called every time the GPS reports a new position
      _updateFeMarkerOnMap(newLocation);
      if (_isNavigationMode &&
          _mapboxController != null &&
          newLocation.latitude != null &&
          newLocation.longitude != null) {
        _mapboxController!.flyTo(
          CameraOptions(
            center: Point(
              coordinates: Position(
                newLocation.longitude!,
                newLocation.latitude!,
              ),
            ),
            zoom: 16.0, // Zoom in closer for navigation
            bearing: newLocation
                .heading, // Orient the map to the direction of travel
            pitch: 60.0, // Tilt the map for a 3D perspective
          ),
          MapAnimationOptions(duration: 1500), // Animate the camera movement
        );
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureIconAsBytes().then((bytes) {
        if (bytes != null) {
          setState(() {
            _branchIconBytes = bytes;
            print("✅ Branch icon captured successfully!");
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _locationService.stop(); // Stop the service when the widget is disposed
    _proximityCheckTimer?.cancel();
    _locationStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchBatteryLevel() async {
    try {
      final int batteryLevel = await _battery.batteryLevel;
      setState(() {
        _batteryLevel = batteryLevel;
      });
    } catch (e) {
      print("Error fetching battery level: $e");
    }
  }

  Future<void> _updateFeMarkerOnMap(LocationData locationData) async {
    if (_mapboxController == null ||
        locationData.latitude == null ||
        locationData.longitude == null) {
      return;
    }

    // This is much more efficient than removing and re-adding the layer.
    // We update the data of the existing GeoJSON source.
    try {
      final source = await _mapboxController!.style.getSource("circle-source");
      if (source is GeoJsonSource) {
        source.updateGeoJSON(
          json.encode({
            "type": "FeatureCollection",
            "features": [
              {
                "type": "Feature",
                "geometry": {
                  "type": "Point",
                  "coordinates": [
                    locationData.longitude,
                    locationData.latitude,
                  ],
                },
              },
            ],
          }),
        );
      }
    } catch (e) {
      print("Error updating FE marker: $e");
    }
  }

  Future<void> _launchGoogleMapsNavigation(double lat, double lng) async {
    Uri uri;

    if (Platform.isAndroid) {
      //  Android
      uri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    } else if (Platform.isIOS) {
      // iOS
      Uri googleMapsUri = Uri.parse(
        'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving',
      );
      if (await canLaunchUrl(googleMapsUri)) {
        uri = googleMapsUri;
      } else {
        uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
        );
      }
    } else {
      uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
      );
    }

    try {
      await launchUrl(uri);
    } catch (e) {
      print('Could not launch $uri: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open maps')));
    }
  }

  //address
  Future<String> _getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      List<geocoding.Placemark> placemarks = await geocoding
          .placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        geocoding.Placemark place = placemarks.first;
        return "${place.street}, ${place.locality}";
      }
      return "Address not found";
    } catch (e) {
      print("Error getting address: $e");
      return "Error getting address";
    }
  }

  //branch marker
  Future<void> _addBranchMarkers(List<dynamic> branches) async {
    if (_mapboxController == null ||
        branches.isEmpty ||
        _branchIconBytes == null) {
      print(
        "Cannot add branch markers. Controller, branches, or icon bytes are missing.",
      );
      return;
    }

    const String branchIconId = "bank-marker-icon";

    try {
      // Check if the layer exists before removing it
      final layerExists = await _mapboxController!.style.styleLayerExists(
        "branch-layer",
      );
      if (layerExists) {
        await _mapboxController!.style.removeStyleLayer("branch-layer");
      }

      // Check if the source exists before removing it
      final sourceExists = await _mapboxController!.style.styleSourceExists(
        "branch-source",
      );
      if (sourceExists) {
        await _mapboxController!.style.removeStyleSource("branch-source");
      }

      // Remove the style image if it exists
      final imageExists = await _mapboxController!.style.hasStyleImage(
        branchIconId,
      );
      if (imageExists) {
        await _mapboxController!.style.removeStyleImage(branchIconId);
      }

      // Add the captured image bytes to the map's style
      await _mapboxController!.style.addStyleImage(
        branchIconId,
        3.0, // Match the pixelRatio from the capture method
        MbxImage(
          width: 40 * 3, // width * pixelRatio
          height: 40 * 3, // height * pixelRatio
          data: _branchIconBytes!,
        ),
        false, // sdf (Signed Distance Field)
        [], // stretchX: Add this empty list
        [], // stretchY: Add this empty list
        null, // content: Add this null value
      );

      // Create GeoJSON features for the branches
      final List<Map<String, dynamic>> features = branches.map((branch) {
        return {
          "type": "Feature",
          "geometry": {
            "type": "Point",
            "coordinates": [
              branch['longitude'].toDouble(),
              branch['latitude'].toDouble(),
            ],
          },
          "properties": {"id": branch['id']},
        };
      }).toList();

      // Add the GeoJSON source for the branch markers
      await _mapboxController!.style.addSource(
        GeoJsonSource(
          id: "branch-source",
          data: json.encode({
            "type": "FeatureCollection",
            "features": features,
          }),
        ),
      );

      // Add the symbol layer for the branch markers
      await _mapboxController!.style.addLayer(
        SymbolLayer(
          id: "branch-layer",
          sourceId: "branch-source",
          iconImage: branchIconId,
          iconSize: 0.60, // Adjust size to compensate for pixelRatio
          iconAllowOverlap: true,
        ),
      );

      print("📍 Branch markers added to the map.");
    } catch (e) {
      print("Error adding branch markers: $e");
    }
  }

  //check proximity
  void _startProximityCheck(Map<String, dynamic> route, dynamic branch) {
    _proximityCheckTimer?.cancel(); // Cancel any previous timer

    _proximityCheckTimer = Timer.periodic(const Duration(seconds: 5), (
      timer,
    ) async {
      final location = Location();
      final currentLocation = await location.getLocation();

      if (currentLocation.latitude == null || currentLocation.longitude == null)
        return;

      double distanceInMeters = geolocator.Geolocator.distanceBetween(
        currentLocation.latitude!,
        currentLocation.longitude!,
        branch['latitude'].toDouble(),
        branch['longitude'].toDouble(),
      );

      print(
        '📏 Distance to destination: ${distanceInMeters.toStringAsFixed(2)} meters.',
      );

      if (distanceInMeters <= 5.0) {
        print('🎉 Route complete! FE is within 5 meters of the branch.');
        _completeRoute(route);
        timer.cancel(); // Stop checking once the destination is reached
      }
    });
  }

  void _stopNavigationMode() {
    setState(() {
      _isNavigationMode = false;
      _activeNavigationRoute = null;
    });
    _proximityCheckTimer?.cancel(); // Stop checking distance

    // Optional: Reset camera to a default view
    if (_mapboxController != null) {
      _mapboxController!.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(
              widget.fieldEngineer['currentLongitude'].toDouble(),
              widget.fieldEngineer['currentLatitude'].toDouble(),
            ),
          ), // Default center
          zoom: 12.0,
          bearing: 0,
          pitch: 0,
        ),
        MapAnimationOptions(duration: 1000),
      );
    }
  }

  void _completeRoute(Map<String, dynamic> route) async {
    // Hanapin ang active route sa ating listahan
    int routeIndex = ongoingRoutes.indexWhere((r) => r['id'] == route['id']);
    if (routeIndex != -1) {
      setState(() {
        // I-update ang status at magdagdag ng bagong event
        ongoingRoutes[routeIndex]['status'] = 'arrived';
        ongoingRoutes[routeIndex]['events'].add({
          'status': 'Arrived',
          'timestamp': DateTime.now(),
        });
      });
    }

    // Hindi na natin tatanggalin ang route sa listahan dito.
    // Mananatili ito hanggang matapos ang serbisyo.
    _proximityCheckTimer?.cancel(); // Itigil ang proximity check

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ You have arrived at ${route['branchName']}!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  //finish service
  void _finishService(Map<String, dynamic> route) {
    int routeIndex = ongoingRoutes.indexWhere((r) => r['id'] == route['id']);
    if (routeIndex != -1) {
      setState(() {
        ongoingRoutes[routeIndex]['status'] = 'finished';
        ongoingRoutes[routeIndex]['events'].add({
          'status': 'Finished',
          'timestamp': DateTime.now(),
        });
      });
      // Dito mo pwedeng i-call yung API para i-update ang backend na tapos na ang serbisyo
      _proximityCheckTimer?.cancel();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Service at ${route['branchName']} marked as finished.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  //leave branch
  void _leaveBranch(Map<String, dynamic> route) {
    int routeIndex = ongoingRoutes.indexWhere((r) => r['id'] == route['id']);
    if (routeIndex != -1) {
      setState(() {
        ongoingRoutes[routeIndex]['status'] = 'left';
        ongoingRoutes[routeIndex]['events'].add({
          'status': 'Left Branch',
          'timestamp': DateTime.now(),
        });
        // Pagka-leave, pwede na nating tanggalin sa active routes after a delay
        Future.delayed(Duration(seconds: 5), () {
          setState(() {
            ongoingRoutes.removeWhere((r) => r['id'] == route['id']);
          });
          _locationService.stopHistoryBatching();
          fetchServiceRequests();
        });
      });
    }
  }

  //draw polyline
  Future<void> _drawRouteOnMap(List<dynamic> coordinates) async {
    if (_mapboxController == null) return;

    const String routeSourceId = "route-source";
    const String routeLayerId = "route-layer";

    try {
      // Clear any existing route first
      final layerExists = await _mapboxController!.style.styleLayerExists(
        routeLayerId,
      );
      if (layerExists)
        await _mapboxController!.style.removeStyleLayer(routeLayerId);
      final sourceExists = await _mapboxController!.style.styleSourceExists(
        routeSourceId,
      );
      if (sourceExists)
        await _mapboxController!.style.removeStyleSource(routeSourceId);

      final Map<String, dynamic> routeGeoJson = {
        "type": "Feature",
        "geometry": {"type": "LineString", "coordinates": coordinates},
      };

      await _mapboxController!.style.addSource(
        GeoJsonSource(id: routeSourceId, data: json.encode(routeGeoJson)),
      );

      await _mapboxController!.style.addLayer(
        LineLayer(
          id: routeLayerId,
          sourceId: routeSourceId,
          lineColor: Colors.blue.value,
          lineWidth: 5.0,
          lineOpacity: 0.8,
        ),
      );
      print('✅ Route polyline drawn on map.');
    } catch (e) {
      print('❌ Error drawing route: $e');
    }
  }

  Future<Uint8List?> _captureIconAsBytes() async {
    try {
      RenderRepaintBoundary boundary =
          _branchIconKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary;

      // The devicePixelRatio ensures the image is sharp on high-res screens.
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);

      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      return byteData?.buffer.asUint8List();
    } catch (e) {
      print("Error capturing widget: $e");
      return null;
    }
  }

  /// circle marker
  Future<void> _addCircleMarker(Position coordinates) async {
    if (_mapboxController == null) return;

    try {
      // Check if the layer exists before removing it
      final layerExists = await _mapboxController!.style.styleLayerExists(
        "circle-layer",
      );
      if (layerExists) {
        await _mapboxController!.style.removeStyleLayer("circle-layer");
      }

      // Check if the source exists before removing it
      final sourceExists = await _mapboxController!.style.styleSourceExists(
        "circle-source",
      );
      if (sourceExists) {
        await _mapboxController!.style.removeStyleSource("circle-source");
      }

      // Add the GeoJSON source
      await _mapboxController!.style.addSource(
        GeoJsonSource(
          id: "circle-source",
          data: json.encode({
            "type": "FeatureCollection",
            "features": [
              {
                "type": "Feature",
                "geometry": {
                  "type": "Point",
                  "coordinates": [coordinates.lng, coordinates.lat],
                },
                "properties": {},
              },
            ],
          }),
        ),
      );

      // Add the circle layer
      await _mapboxController!.style.addLayer(
        CircleLayer(
          id: "circle-layer",
          sourceId: "circle-source",
          circleColor: Colors.blue.value,
          circleRadius: 8.0,
          circleStrokeColor: Colors.white.value,
          circleStrokeWidth: 2.0,
        ),
      );
    } catch (e) {
      print('Error adding circle marker: $e');
    }
  }

  Future<void> _checkForActiveAssignmentOnStartup() async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://ecsmapappwebadminbackend-production.up.railway.app/api/FieldEngineer/${widget.fieldEngineer['id']}/current-assignment',
        ),
      );

      if (response.statusCode == 200 &&
          response.body.isNotEmpty &&
          response.body != "null") {
        final assignment = json.decode(response.body);
        if (assignment != null) {
          print(
            "✅ Found active assignment on startup. Resuming activity logging.",
          );
          _locationService.startHistoryBatching();
          // Optional: You could also automatically put the user back into navigation mode here
        } else {
          print("ℹ️ No active assignment found on startup.");
        }
      }
    } catch (e) {
      print("Error checking for active assignment: $e");
    }
  }

  Future<void> _initializeFCM() async {
    try {
      // Request permission for notifications
      NotificationSettings settings = await _firebaseMessaging
          .requestPermission(
            alert: true,
            announcement: false,
            badge: true,
            carPlay: false,
            criticalAlert: false,
            provisional: false,
            sound: true,
          );

      print('User granted permission: ${settings.authorizationStatus}');

      // Initialize local notifications
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      await _localNotifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // Handle notification tap
          print('Notification tapped: ${response.payload}');
          _handleNotificationTap(response.payload);
        },
      );

      // Get FCM token
      fcmToken = await _firebaseMessaging.getToken();
      print('FCM Token: $fcmToken');

      // Send token to backend and associate with field engineer
      if (fcmToken != null) {
        await _sendTokenToBackend();
      }

      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((String token) {
        print('FCM Token refreshed: $token');
        fcmToken = token;
        _sendTokenToBackend();
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('Received foreground message: ${message.notification?.title}');
        _showLocalNotification(message);
      });

      // Handle notification tap when app is in background but not terminated
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('Notification tapped (background): ${message.data}');
        _handleNotificationData(message.data);
      });

      // Handle notification tap when app is terminated
      RemoteMessage? initialMessage = await _firebaseMessaging
          .getInitialMessage();
      if (initialMessage != null) {
        print('App opened from terminated state: ${initialMessage.data}');
        _handleNotificationData(initialMessage.data);
      }
    } catch (e) {
      print('Error initializing FCM: $e');
    }
  }

  Future<void> _sendTokenToBackend() async {
    try {
      final response = await http.post(
        Uri.parse(
          'https://ecsmapappwebadminbackend-production.up.railway.app/api/FieldEngineer/${widget.fieldEngineer['id']}/fcm-token',
        ),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'fcmToken': fcmToken}),
      );

      if (response.statusCode == 200) {
        print('FCM token sent to backend successfully');
      } else {
        print('Failed to send FCM token: ${response.statusCode}');
      }
    } catch (e) {
      print('Error sending FCM token to backend: $e');
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'service_requests',
          'Service Requests',
          channelDescription: 'Notifications for new service requests',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          icon: '@mipmap/ic_launcher',
        );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await _localNotifications.show(
      message.hashCode,
      message.notification?.title ?? 'New Service Request',
      message.notification?.body ?? 'A new service request has been created',
      platformChannelSpecifics,
      payload: json.encode(message.data),
    );
  }

  void _handleNotificationTap(String? payload) {
    if (payload != null) {
      try {
        final data = json.decode(payload);
        _handleNotificationData(data);
      } catch (e) {
        print('Error parsing notification payload: $e');
      }
    }
  }

  void _handleNotificationData(Map<String, dynamic> data) {
    // Handle different types of notifications
    final type = data['type'];

    switch (type) {
      case 'new_service_request':
        // Refresh service requests and show a snackbar
        fetchServiceRequests();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'New service request: ${data['branchName'] ?? 'Unknown location'}',
            ),
            backgroundColor: Colors.blue,
            action: SnackBarAction(
              label: 'View',
              onPressed: () {
                // Scroll to service requests or navigate to specific request
              },
            ),
          ),
        );
        break;
      case 'service_request_update':
        // Refresh service requests
        fetchServiceRequests();
        break;
      default:
        print('Unknown notification type: $type');
    }
  }

  Future<void> fetchServiceRequests() async {
    setState(() {
      isLoading = true;
    });

    try {
      final response = await http.get(
        Uri.parse(
          'https://ecsmapappwebadminbackend-production.up.railway.app/api/ServiceRequests',
        ),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        List<dynamic> allRequests = json.decode(response.body);

        List<dynamic> filteredRequests = allRequests.where((request) {
          return request['fieldEngineerId'] == null ||
              request['fieldEngineerId'] == widget.fieldEngineer['id'];
        }).toList();

        setState(() {
          serviceRequests = filteredRequests;
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
        print('Failed to load service requests: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      print('Error fetching service requests: $e');
    }
  }

  Future<void> fetchBranches() async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://ecsmapappwebadminbackend-production.up.railway.app/api/Branches',
        ),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        setState(() {
          branches = json.decode(response.body);
          print("Fetched ${branches.length} branches");
        });
      }
    } catch (e) {
      print('Error fetching branches: $e');
    }
  }

  Future<Map<String, dynamic>?> getMapboxRoute(
    double fromLat,
    double fromLng,
    double toLat,
    double toLng,
  ) async {
    try {
      const String mapboxToken =
          'pk.eyJ1IjoiYmFzaWwxLTIzIiwiYSI6ImNtZWFvNW43ZTA0ejQycHBtd3dkMHJ1bnkifQ.Y-IlM-vQAlaGr7pVQnug3Q';
      final String url =
          'https://api.mapbox.com/directions/v5/mapbox/driving/$fromLng,$fromLat;$toLng,$toLat?steps=true&geometries=geojson&access_token=$mapboxToken';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' &&
            data['routes'] != null &&
            data['routes'].isNotEmpty) {
          return data['routes'][0];
        }
      }
      return null;
    } catch (e) {
      print('Error getting Mapbox route: $e');
      return null;
    }
  }

  Future<void> startFieldEngineerNavigation(
    int fieldEngineerId,
    String fieldEngineerName,
    List<dynamic> routeCoordinates,
  ) async {
    try {
      final response = await http.post(
        Uri.parse(
          'https://ecsmapappwebadminbackend-production.up.railway.app/api/Test/startNavigation',
        ),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'fieldEngineerId': fieldEngineerId,
          'fieldEngineerName': fieldEngineerName,
          'routeCoordinates': routeCoordinates,
        }),
      );

      print('Start navigation response: ${response.statusCode}');
      print('Start navigation body: ${response.body}');

      if (response.statusCode == 200) {
        print('Navigation started successfully for $fieldEngineerName');
      } else {
        print('Failed to start navigation: ${response.statusCode}');
      }
    } catch (e) {
      print('Error starting navigation: $e');
    }
  }

  Future<void> createNewRoute(Map<String, dynamic> routeData) async {
    try {
      final response = await http.post(
        Uri.parse(
          'https://ecsmapappwebadminbackend-production.up.railway.app/api/Routes',
        ),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(routeData),
      );

      print('Create route response: ${response.statusCode}');
      print('Create route body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('Route created successfully');
      } else {
        print('Failed to create route: ${response.statusCode}');
      }
    } catch (e) {
      print('Error creating route: $e');
    }
  }

  Future<void> triggerWebAdminUpdate(
    int serviceRequestId,
    int fieldEngineerId,
  ) async {
    try {
      final response = await http.post(
        Uri.parse(
          'https://ecsmapappwebadminbackend-production.up.railway.app/api/Notifications/serviceRequestAccepted',
        ),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'serviceRequestId': serviceRequestId,
          'fieldEngineerId': fieldEngineerId,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      print('Web admin update response: ${response.statusCode}');
      if (response.statusCode == 200) {
        print('Web admin notified successfully');
      }
    } catch (e) {
      print('Error notifying web admin: $e');
    }
  }

  String formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.round()} m';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)} km';
    }
  }

  String calculateFare(double distanceInKm) {
    const double baseFare = 45.0;
    const double ratePerKm = 15.0;
    final double fare = baseFare + (distanceInKm * ratePerKm);
    return '₱${fare.round()}';
  }

  Future<void> acceptServiceRequest(int serviceRequestId) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('Accepting request...'),
              ],
            ),
          );
        },
      );

      final acceptResponse = await http.post(
        Uri.parse(
          'https://ecsmapappwebadminbackend-production.up.railway.app/api/ServiceRequests/$serviceRequestId/accept',
        ),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'fieldEngineerId': widget.fieldEngineer['id']}),
      );

      if (acceptResponse.statusCode == 200) {
        print('✅ Service request accepted by backend.');

        final serviceRequest = serviceRequests.firstWhere(
          (sr) => sr['id'] == serviceRequestId,
          orElse: () => null,
        );
        if (serviceRequest == null)
          throw Exception('Could not find local service request data.');

        final branch = branches.firstWhere(
          (b) => b['id'].toString() == serviceRequest['branchId'].toString(),
          orElse: () => null,
        );
        if (branch == null)
          throw Exception('Could not find local branch data.');

        final routeData = await getMapboxRoute(
          widget.fieldEngineer['currentLatitude'].toDouble(),
          widget.fieldEngineer['currentLongitude'].toDouble(),
          branch['latitude'].toDouble(),
          branch['longitude'].toDouble(),
        );
        final newRouteForUI = {
          'id': DateTime.now().millisecondsSinceEpoch,
          'feId': widget.fieldEngineer['id'],
          'feName': widget.fieldEngineer['name'],
          'branchId': branch['id'],
          'branchName': branch['name'],
          'serviceRequestId': serviceRequestId,
          'status': 'in-transit', // Initial status
          'events': [
            {'status': 'Accepted', 'timestamp': DateTime.now()},
            {'status': 'In Transit', 'timestamp': DateTime.now()},
          ],
          // Magdagdag ng route details kung meron
          if (routeData != null) ...{
            'estimatedArrival': DateTime.now().add(
              Duration(seconds: (routeData['duration'] as double).round()),
            ),
            'distance': formatDistance(routeData['distance'].toDouble()),
            'price': calculateFare(routeData['distance'] / 1000),
          },
        };

        setState(() {
          ongoingRoutes.add(newRouteForUI);
        });

        _startProximityCheck(
          newRouteForUI,
          branch,
        ); // Simulan ang pag-check kung malapit na
        _locationService.startHistoryBatching();
        _launchGoogleMapsNavigation(
          branch['latitude'].toDouble(),
          branch['longitude'].toDouble(),
        );

        Navigator.of(context).pop(); // Itago ang loading spinner
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Request accepted! Opening Google Maps...'),
            backgroundColor: Colors.green,
          ),
        );

        fetchServiceRequests();
      } else {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept request: ${acceptResponse.body}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      print('❌ Error in acceptServiceRequest: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> stopNavigation(Map<String, dynamic> route) async {
    try {
      await http.post(
        Uri.parse(
          'https://ecsmapappwebadminbackend-production.up.railway.app/api/Test/stopNavigation',
        ),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'fieldEngineerId': route['feId']}),
      );

      if (route['id'] != null) {
        await http.delete(
          Uri.parse(
            'https://ecsmapappwebadminbackend-production.up.railway.app/api/Routes/${route['id']}',
          ),
          headers: {'Content-Type': 'application/json'},
        );
      }
      _locationService.stopHistoryBatching();

      setState(() {
        ongoingRoutes.removeWhere((r) => r['id'] == route['id']);
        _proximityCheckTimer?.cancel();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Navigation stopped for ${route['feName']}'),
          backgroundColor: Colors.orange,
        ),
      );

      fetchServiceRequests();
    } catch (e) {
      print('Error stopping navigation: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isNavigationMode) {
      return _buildNavigationView();
    } else {
      return Stack(
        children: [
          Scaffold(
            extendBodyBehindAppBar: true,
             appBar: AppBar(
              title: Text(widget.title),
              actions: [
                IconButton(
                  icon: const Icon(Icons.person_outline),
                  onPressed: _showFieldEngineerInfoDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    fetchServiceRequests();
                    fetchBranches();
                  },
                  tooltip: 'Refresh',
                ),
              ],
            ),
            body: Stack(children: [_buildMapboxMap(), _buildBottomSheet()]),
            floatingActionButton: FloatingActionButton(
              onPressed: () {
                fetchServiceRequests();
                fetchBranches();
              },
              tooltip: 'Refresh',
              child: const Icon(Icons.refresh),
            ),
            floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
            bottomNavigationBar: _buildBottomNavigationBar(), // Add this here
          ),
          Transform.translate(
            offset: Offset(MediaQuery.of(context).size.width, 0),
            child: RepaintBoundary(
              key: _branchIconKey,
              child: _buildBranchIconWidget(),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildNavigationView() {
    // Ensure we have an active route before building
    if (_activeNavigationRoute == null) {
      return const Scaffold(body: Center(child: Text("Loading Navigation...")));
    }

    return Scaffold(
      body: Stack(
        children: [
          _buildMapboxMap(),

          Positioned(
            top: 40,
            left: 10,
            right: 10,
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade400.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.black.withOpacity(0.1),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                // Clip the blur to the rounded corners
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),

                  // Apply the blur effect
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                    // The actual content goes here, inside another Container for padding
                    child: Container(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.navigation,
                            color: Colors.white,
                            size: 40,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Proceed to destination",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    shadows: [
                                      Shadow(
                                        blurRadius: 2,
                                        color: Colors.black.withOpacity(0.5),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  _activeNavigationRoute!['branchName'],
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom Summary Panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade400.withOpacity(0.5),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20.0),
                ),
                border: Border.all(
                  color: Colors.black.withOpacity(0.1),
                  width: 1.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20.0),
                ),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildNavigationInfo(
                              "ETA",
                              _activeNavigationRoute!['estimatedArrival'],
                              Icons.access_time,
                            ),
                            _buildNavigationInfo(
                              "Distance",
                              _activeNavigationRoute!['distance'],
                              Icons.straighten,
                            ),
                            _buildNavigationInfo(
                              "Fare",
                              _activeNavigationRoute!['price'],
                              Icons.attach_money,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _stopNavigationMode,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 50,
                              vertical: 15,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: const Text("End Navigation"),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationInfo(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildMapboxMap() {
    final engineerLat =
        widget.fieldEngineer['currentLatitude']?.toDouble() ?? 14.5995;
    final engineerLng =
        widget.fieldEngineer['currentLongitude']?.toDouble() ?? 120.9842;
    final engineerPosition = Position(engineerLng, engineerLat);

    return MapWidget(
      key: ValueKey("mapWidget"),
      cameraOptions: CameraOptions(
        center: Point(coordinates: engineerPosition),
        zoom: 12.0,
      ),
      styleUri: MapboxStyles.MAPBOX_STREETS,
      onMapCreated: (MapboxMap controller) {
        _mapboxController = controller;
      },
      onMapLoadedListener: (_) async {
        print("Map has loaded, adding circle marker...");

        // Ensure the map controller is set
        if (_mapboxController == null) {
          print("❌ Mapbox controller is null.");
          return;
        }

        // Add the circle marker for the engineer's position
        final engineerLat =
            widget.fieldEngineer['currentLatitude']?.toDouble() ?? 14.5995;
        final engineerLng =
            widget.fieldEngineer['currentLongitude']?.toDouble() ?? 120.9842;
        final engineerPosition = Position(engineerLng, engineerLat);
        await _addCircleMarker(engineerPosition);

        // Ensure branches are loaded
        if (branches.isEmpty) {
          print("❌ Branches list is empty. Fetching branches...");
          await fetchBranches();
        }

        // Ensure branch icon bytes are captured
        if (_branchIconBytes == null) {
          print("❌ Branch icon bytes are null. Capturing icon...");
          _branchIconBytes = await _captureIconAsBytes();
          if (_branchIconBytes == null) {
            print("❌ Failed to capture branch icon bytes.");
            return;
          }
        }

        // Add branch markers
        if (branches.isNotEmpty && _branchIconBytes != null) {
          print("✅ Adding branch markers...");
          await _addBranchMarkers(branches);
        } else {
          print("❌ Cannot add branch markers. Dependencies are missing.");
        }

        if (_isNavigationMode && _activeNavigationRoute != null) {
          print("✅ In Navigation Mode, drawing route...");
          await _drawRouteOnMap(_activeNavigationRoute!['routeCoordinates']);
        }
      },
    );
  }

  // lib/screens/home_screen.dart -> _MyHomePageState

Widget _buildBottomSheet() {
  final colorScheme = Theme.of(context).colorScheme;

  return DraggableScrollableSheet(
    initialChildSize: 0.6,
    minChildSize: 0.2,
    maxChildSize: 0.9,
    builder: (BuildContext context, ScrollController scrollController) {
      return Container(
        decoration: BoxDecoration(
          // Use Material 3 surface color with elevation tint
          color: ElevationOverlay.applySurfaceTint(
            colorScheme.surface,
            colorScheme.surfaceTint,
            3, // Elevation level
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28.0)),
        ),
        child: ListView(
          controller: scrollController,
          padding: EdgeInsets.zero,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12.0),
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            
            // The content will be provided by our separated widgets
            FieldEngineerProfile(
              fieldEngineer: widget.fieldEngineer,
              getAddress: _getAddressFromCoordinates,
            ),
            
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Divider(),
            ),

            if (ongoingRoutes.isNotEmpty)
              ServiceRequestTimeline(
                route: ongoingRoutes.first,
                onFinishService: _finishService,
                onLeaveBranch: _leaveBranch,
              )
            else
              ServiceRequestList(
                isLoading: isLoading,
                serviceRequests: serviceRequests,
                ongoingRoutes: ongoingRoutes,
                fieldEngineerId: widget.fieldEngineer['id'],
                onAcceptRequest: acceptServiceRequest,
              ),
          ],
        ),
      );
    },
  );
}

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 5,
        margin: const EdgeInsets.symmetric(vertical: 12.0),
        decoration: BoxDecoration(
          color: Colors.grey[400],
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildFcmStatusBanner() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(8),
      color: Colors.green.shade100,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 16),
          SizedBox(width: 8),
          Text(
            'Push notifications enabled',
            style: TextStyle(color: Colors.green.shade800, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchIconWidget() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.green.shade700,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(Icons.account_balance, color: Colors.white, size: 24),
    );
  }

  //Widget for bottom navigation bar
  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
      ],
    );
  }

  /// The dialog showing the field engineer's info.
  void _showFieldEngineerInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Field Engineer Info'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ID: ${widget.fieldEngineer['id']}'),
              Text('Name: ${widget.fieldEngineer['name']}'),
              Text('Email: ${widget.fieldEngineer['email']}'),
              Text('Phone: ${widget.fieldEngineer['phone']}'),
              Text('Status: ${widget.fieldEngineer['status']}'),
              Text('Available: ${widget.fieldEngineer['isAvailable']}'),
              Text('Lat: ${widget.fieldEngineer['currentLatitude']}'),
              Text('Lng: ${widget.fieldEngineer['currentLongitude']}'),
              if (fcmToken != null)
                Text(
                  'FCM: ${fcmToken!.substring(0, 20)}...',
                  style: TextStyle(fontSize: 10),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }
}
