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
import 'dart:ui'; // Import for BackdropFilter
import 'package:geolocator/geolocator.dart' as geolocator;
import '../services/location_service.dart';
import 'dart:async'; // For Timer
import 'package:location/location.dart'; // For LocationData



class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title, required this.fieldEngineer});

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

  // FCM and Local Notifications
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initializeFCM();
    fetchServiceRequests();
    fetchBranches();
    // Initialize and start the location service
    _locationService = LocationService(fieldEngineerId: widget.fieldEngineer['id']);
    _locationService.start();

    _locationStreamSubscription = _locationService.onLocationChanged.listen((LocationData newLocation) {
      // This will be called every time the GPS reports a new position
      _updateFeMarkerOnMap(newLocation);
      if (_isNavigationMode && _mapboxController != null && newLocation.latitude != null && newLocation.longitude != null) {
    _mapboxController!.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(newLocation.longitude!, newLocation.latitude!)),
        zoom: 16.0, // Zoom in closer for navigation
        bearing: newLocation.heading, // Orient the map to the direction of travel
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

  Future<void> _updateFeMarkerOnMap(LocationData locationData) async {
    if (_mapboxController == null || locationData.latitude == null || locationData.longitude == null) {
      return;
    }
    
    // This is much more efficient than removing and re-adding the layer.
    // We update the data of the existing GeoJSON source.
    try {
      final source = await _mapboxController!.style.getSource("circle-source");
      if (source is GeoJsonSource) {
        source.updateGeoJSON(json.encode({
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "geometry": {
                "type": "Point",
                "coordinates": [locationData.longitude, locationData.latitude]
              },
            }
          ]
        }));
      }
    } catch (e) {
      print("Error updating FE marker: $e");
    }
  }

  //branch marker
  Future<void> _addBranchMarkers(List<dynamic> branches) async {
  if (_mapboxController == null || branches.isEmpty || _branchIconBytes == null) {
    print("Cannot add branch markers. Controller, branches, or icon bytes are missing.");
    return;
  }

  const String branchIconId = "bank-marker-icon";

  try {
    // Check if the layer exists before removing it
    final layerExists = await _mapboxController!.style.styleLayerExists("branch-layer");
    if (layerExists) {
      await _mapboxController!.style.removeStyleLayer("branch-layer");
    }

    // Check if the source exists before removing it
    final sourceExists = await _mapboxController!.style.styleSourceExists("branch-source");
    if (sourceExists) {
      await _mapboxController!.style.removeStyleSource("branch-source");
    }

    // Remove the style image if it exists
    final imageExists = await _mapboxController!.style.hasStyleImage(branchIconId);
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
      [],    // stretchX: Add this empty list
      [],    // stretchY: Add this empty list
      null,  // content: Add this null value
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
          ]
        },
        "properties": {"id": branch['id']}
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

  _proximityCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
    final location = Location();
    final currentLocation = await location.getLocation();
    
    if (currentLocation.latitude == null || currentLocation.longitude == null) return;

    double distanceInMeters = geolocator.Geolocator.distanceBetween(
      currentLocation.latitude!,
      currentLocation.longitude!,
      branch['latitude'].toDouble(),
      branch['longitude'].toDouble(),
    );

    print('📏 Distance to destination: ${distanceInMeters.toStringAsFixed(2)} meters.');

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
        center: Point(coordinates: Position(120.9842, 14.5995)), // Default center
        zoom: 12.0,
        bearing: 0,
        pitch: 0,
      ),
      MapAnimationOptions(duration: 1000),
    );
  }
}


//complete route
void _completeRoute(Map<String, dynamic> route) async {
  final int serviceRequestId = route['serviceRequestId'];

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('✅ Route to ${route['branchName']} complete!'),
      backgroundColor: Colors.green,
    ),
  );
  _stopNavigationMode();


  setState(() {
    ongoingRoutes.removeWhere((r) => r['id'] == route['id']);
  });

  try{
    final url = Uri.parse('https://ecsmapappwebadminbackend-production.up.railway.app/api/ServiceRequests/$serviceRequestId/complete');
    final response = await http.post(url);

    if (response.statusCode == 200){
      print("✅ Service request marked as complete.");

    }else{
      print("❌ Failed to mark service request as complete. Status: ${response.statusCode}");
    }
  } catch(e){
    print("❌ Error marking service request as complete: $e");
  }
  
}

 //draw polyline
  Future<void> _drawRouteOnMap(List<dynamic> coordinates) async {
    if (_mapboxController == null) return;

    const String routeSourceId = "route-source";
    const String routeLayerId = "route-layer";

    try {
      // Clear any existing route first
      final layerExists = await _mapboxController!.style.styleLayerExists(routeLayerId);
      if (layerExists) await _mapboxController!.style.removeStyleLayer(routeLayerId);
      final sourceExists = await _mapboxController!.style.styleSourceExists(routeSourceId);
      if (sourceExists) await _mapboxController!.style.removeStyleSource(routeSourceId);
      
      final Map<String, dynamic> routeGeoJson = {
        "type": "Feature",
        "geometry": {"type": "LineString", "coordinates": coordinates}
      };

      await _mapboxController!.style.addSource(GeoJsonSource(id: routeSourceId, data: json.encode(routeGeoJson)));

      await _mapboxController!.style.addLayer(LineLayer(
        id: routeLayerId,
        sourceId: routeSourceId,
        lineColor: Colors.blue.value,
        lineWidth: 5.0,
        lineOpacity: 0.8,
      ));
      print('✅ Route polyline drawn on map.');
    } catch (e) {
      print('❌ Error drawing route: $e');
    }
  }

  Future<Uint8List?> _captureIconAsBytes() async {
  try {
    RenderRepaintBoundary boundary = _branchIconKey.currentContext?.findRenderObject() as RenderRepaintBoundary;
    
    // The devicePixelRatio ensures the image is sharp on high-res screens.
    ui.Image image = await boundary.toImage(pixelRatio: 3.0); 
    
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    
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
    final layerExists = await _mapboxController!.style.styleLayerExists("circle-layer");
    if (layerExists) {
      await _mapboxController!.style.removeStyleLayer("circle-layer");
    }

    // Check if the source exists before removing it
    final sourceExists = await _mapboxController!.style.styleSourceExists("circle-source");
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
                "coordinates": [coordinates.lng, coordinates.lat]
              },
              "properties": {}
            }
          ]
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

  Future<void> _initializeFCM() async {
    try {
      // Request permission for notifications
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
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

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
      );

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
      RemoteMessage? initialMessage = await _firebaseMessaging.getInitialMessage();
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
        Uri.parse('https://ecsmapappwebadminbackend-production.up.railway.app/api/FieldEngineer/${widget.fieldEngineer['id']}/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'fcmToken': fcmToken,
        }),
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
            content: Text('New service request: ${data['branchName'] ?? 'Unknown location'}'),
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
        Uri.parse('https://ecsmapappwebadminbackend-production.up.railway.app/api/ServiceRequests'),
        headers: {
          'Content-Type': 'application/json',
        },
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
        Uri.parse('https://ecsmapappwebadminbackend-production.up.railway.app/api/Branches'),
        headers: {
          'Content-Type': 'application/json',
        },
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

  Future<Map<String, dynamic>?> getMapboxRoute(double fromLat, double fromLng, double toLat, double toLng) async {
    try {
      const String mapboxToken = 'pk.eyJ1IjoiYmFzaWwxLTIzIiwiYSI6ImNtZWFvNW43ZTA0ejQycHBtd3dkMHJ1bnkifQ.Y-IlM-vQAlaGr7pVQnug3Q';
      final String url = 'https://api.mapbox.com/directions/v5/mapbox/driving/$fromLng,$fromLat;$toLng,$toLat?steps=true&geometries=geojson&access_token=$mapboxToken';
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          return data['routes'][0];
        }
      }
      return null;
    } catch (e) {
      print('Error getting Mapbox route: $e');
      return null;
    }
  }

  Future<void> startFieldEngineerNavigation(int fieldEngineerId, String fieldEngineerName, List<dynamic> routeCoordinates) async {
    try {
      final response = await http.post(
        Uri.parse('https://ecsmapappwebadminbackend-production.up.railway.app/api/Test/startNavigation'),
        headers: {
          'Content-Type': 'application/json',
        },
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
        Uri.parse('https://ecsmapappwebadminbackend-production.up.railway.app/api/Routes'),
        headers: {
          'Content-Type': 'application/json',
        },
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

  Future<void> triggerWebAdminUpdate(int serviceRequestId, int fieldEngineerId) async {
    try {
      final response = await http.post(
        Uri.parse('https://ecsmapappwebadminbackend-production.up.railway.app/api/Notifications/serviceRequestAccepted'),
        headers: {
          'Content-Type': 'application/json',
        },
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
      Uri.parse('https://ecsmapappwebadminbackend-production.up.railway.app/api/ServiceRequests/$serviceRequestId/accept'),
      headers: { 'Content-Type': 'application/json' },
      body: json.encode({ 'fieldEngineerId': widget.fieldEngineer['id'] }),
    );

    if (acceptResponse.statusCode == 200) {
      print('✅ Service request accepted by backend.');
      
      // *** NEW LOGIC STARTS HERE ***
      // Now, let's build the route for the mobile UI
      final serviceRequest = serviceRequests.firstWhere((sr) => sr['id'] == serviceRequestId, orElse: () => null);
      if (serviceRequest == null) throw Exception('Could not find local service request data.');

      final branch = branches.firstWhere((b) => b['id'].toString() == serviceRequest['branchId'].toString(), orElse: () => null);
      if (branch == null) throw Exception('Could not find local branch data.');

      // Get route geometry and details from Mapbox
      final routeData = await getMapboxRoute(
        widget.fieldEngineer['currentLatitude'].toDouble(),
        widget.fieldEngineer['currentLongitude'].toDouble(),
        branch['latitude'].toDouble(),
        branch['longitude'].toDouble(),
      );

      if (routeData != null) {
        final durationMinutes = (routeData['duration'] / 60).round();
        final distanceInKm = routeData['distance'] / 1000;
        final etaTime = DateTime.now().add(Duration(minutes: durationMinutes));

        // Create the local route object for the UI
        final newRouteForUI = {
          'id': DateTime.now().millisecondsSinceEpoch, // Use a client-side unique ID
          'feId': widget.fieldEngineer['id'],
          'feName': widget.fieldEngineer['name'],
          'branchId': branch['id'],
          'branchName': branch['name'],
          'startTime': DateTime.now().toLocal().toString().substring(11, 16),
          'estimatedArrival': etaTime.toLocal().toString().substring(11, 16),
          'distance': formatDistance(routeData['distance'].toDouble()),
          'duration': '${durationMinutes} min',
          'price': calculateFare(distanceInKm),
          'status': 'in-progress',
          'serviceRequestId': serviceRequestId,
          // Storing coordinates is optional but useful for drawing polylines later
          'routeCoordinates': routeData['geometry']['coordinates'], 
        };

        

        //check proximity
        _startProximityCheck(newRouteForUI, branch);

        // Update the UI state to show the new route
        setState(() {
          _isNavigationMode = true;
          _activeNavigationRoute = newRouteForUI;
          ongoingRoutes.add(newRouteForUI);
        });

        Navigator.of(context).pop(); // Hide loading spinner
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Request accepted and route created!'),
            backgroundColor: Colors.green,
          ),
        );

      } else {
        throw Exception('Failed to get route from Mapbox.');
      }
 
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
      SnackBar(
        content: Text('Error: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

//   Future<void> acceptServiceRequest(int serviceRequestId) async {
//     try {
//       showDialog(
//         context: context,
//         barrierDismissible: false,
//         builder: (BuildContext context) {
//           return AlertDialog(
//             content: Row(
//               children: [
//                 CircularProgressIndicator(),
//                 SizedBox(width: 20),
//                 Text('Accepting request...'),
//               ],
//             ),
//           );
//         },
//       );

//       final acceptResponse = await http.post(
//         Uri.parse('https://ecsmapappwebadminbackend-production.up.railway.app/api/ServiceRequests/$serviceRequestId/accept'),
//         headers: {
//           'Content-Type': 'application/json',
//         },
//         body: json.encode({
//           'fieldEngineerId': widget.fieldEngineer['id'],
//         }),
//       );

//       if (acceptResponse.statusCode == 200) {
//   print('Service request accepted successfully.');
// } else {
//   print('Failed to accept service request: ${acceptResponse.statusCode}');
// }

//       print('Accept response: ${acceptResponse.statusCode}');
//       print('Accept response body: ${acceptResponse.body}');

//       if (acceptResponse.statusCode == 200) {
//         final serviceRequest = serviceRequests.firstWhere(
//           (sr) => sr['id'] == serviceRequestId,
//           orElse: () => null,
//         );

//         if (serviceRequest != null) {
//           final branch = branches.firstWhere(
//             (b) => b['id'].toString() == serviceRequest['branchId'].toString(),
//             orElse: () => null,
//           );

//           if (branch != null) {
//             final routeData = await getMapboxRoute(
//               widget.fieldEngineer['currentLatitude'].toDouble(),
//               widget.fieldEngineer['currentLongitude'].toDouble(),
//               branch['latitude'].toDouble(),
//               branch['longitude'].toDouble(),
//             );

//             if (routeData != null) {
//               final routeCoordinates = routeData['geometry']['coordinates'];
//               final startTime = DateTime.now().toLocal();
//               final durationMinutes = (routeData['duration'] / 60).round();
//               final etaTime = startTime.add(Duration(minutes: durationMinutes));
//               final distanceInKm = routeData['distance'] / 1000;

//               await startFieldEngineerNavigation(
//                 widget.fieldEngineer['id'],
//                 widget.fieldEngineer['name'],
//                 routeCoordinates,
//               );

//               final newRouteData = {
//                 'id': DateTime.now().millisecondsSinceEpoch,
//                 'feId': widget.fieldEngineer['id'],
//                 'feName': widget.fieldEngineer['name'],
//                 'branchId': branch['id'],
//                 'branchName': branch['name'],
//                 'startTime': startTime.toLocal().toString().substring(11, 16),
//                 'estimatedArrival': etaTime.toLocal().toString().substring(11, 16),
//                 'distance': formatDistance(routeData['distance'].toDouble()),
//                 'duration': '${durationMinutes} min',
//                 'price': calculateFare(distanceInKm),
//                 'status': 'in-progress',
//                 'serviceRequestId': serviceRequestId,
//                 'routeCoordinates': routeCoordinates,
//               };

//               await createNewRoute(newRouteData);
//               await triggerWebAdminUpdate(serviceRequestId, widget.fieldEngineer['id']);

//               setState(() {
//                 ongoingRoutes.add(newRouteData);
//               });

//               Navigator.of(context).pop();
              
//               ScaffoldMessenger.of(context).showSnackBar(
//                 SnackBar(
//                   content: Text('✅ Service request accepted!\n🚗 Navigation started!\n📍 Web admin updated!'),
//                   backgroundColor: Colors.green,
//                   duration: Duration(seconds: 3),
//                 ),
//               );

//               await Future.delayed(Duration(seconds: 2));
//               fetchServiceRequests();

//             } else {
//               Navigator.of(context).pop();
//               ScaffoldMessenger.of(context).showSnackBar(
//                 SnackBar(
//                   content: Text('Service request accepted, but failed to get route'),
//                   backgroundColor: Colors.orange,
//                 ),
//               );
//             }
//           } else {
//             Navigator.of(context).pop();
//             ScaffoldMessenger.of(context).showSnackBar(
//               SnackBar(
//                 content: Text('Service request accepted, but branch not found'),
//                 backgroundColor: Colors.orange,
//               ),
//             );
//           }
//         }
//       } else {
//         Navigator.of(context).pop();
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Failed to accept request: ${acceptResponse.statusCode}'),
//             backgroundColor: Colors.red,
//           ),
//         );
//       }
//     } catch (e) {
//       if (Navigator.canPop(context)) {
//         Navigator.of(context).pop();
//       }
      
//       print('Error accepting request: $e');
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Error accepting request: $e'),
//           backgroundColor: Colors.red,
//         ),
//       );
//     }
//   }

  Future<void> stopNavigation(Map<String, dynamic> route) async {
    try {
      await http.post(
        Uri.parse('https://ecsmapappwebadminbackend-production.up.railway.app/api/Test/stopNavigation'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'fieldEngineerId': route['feId'],
        }),
      );

      if (route['id'] != null) {
        await http.delete(
          Uri.parse('https://ecsmapappwebadminbackend-production.up.railway.app/api/Routes/${route['id']}'),
          headers: {
            'Content-Type': 'application/json',
          },
        );
      }

      setState(() {
        ongoingRoutes.removeWhere((r) => r['id'] == route['id']);
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
  if (_isNavigationMode){
    return _buildNavigationView();  
    }
    else{
  return Stack(
    children: [
      Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              widget.title,
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: IconButton(
                  icon: Icon(Icons.person, color: Colors.blue.shade800),
                  onPressed: _showFieldEngineerInfoDialog,
                ),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            _buildMapboxMap(),
            _buildBottomSheet(),
          ],
        ),
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
        // The map takes up the full screen
        _buildMapboxMap(),

        // Glassmorphism Top Panel
        Positioned(
  top: 40,
  left: 10,
  right: 10,
  child: SafeArea(
    // NEW: We wrap the content in our glassmorphism widgets
    child: Container(
      // The main container provides the shape, border, and shadow
      decoration: BoxDecoration(
        color: Colors.grey.shade400.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.black.withOpacity(  0.1),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
          )
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
                const Icon(Icons.navigation, color: Colors.white, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Proceed to destination",
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 2, color: Colors.black.withOpacity(0.5))]),
                      ),
                      Text(
                        _activeNavigationRoute!['branchName'],
                        style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    ),
  ),
),
        // Positioned(
        //   top: 40,
        //   left: 10,
        //   right: 10,
        //   child: SafeArea(
        //     child: Card(
        //       elevation: 8,
        //       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        //       child: Container(
        //         padding: const EdgeInsets.all(12.0),
        //         decoration: BoxDecoration(
        //           color: Colors.blue.shade700,
        //           borderRadius: BorderRadius.circular(12)
        //         ),
        //         child: Row(
        //           children: [
        //             const Icon(Icons.navigation, color: Colors.white, size: 40),
        //             const SizedBox(width: 10),
        //             Expanded(
        //               child: Column(
        //                 crossAxisAlignment: CrossAxisAlignment.start,
        //                 children: [
        //                   Text(
        //                     "Proceed to destination", // This would be dynamic in a real turn-by-turn app
        //                     style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        //                   ),
        //                   Text(
        //                     _activeNavigationRoute!['branchName'],
        //                     style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
        //                     overflow: TextOverflow.ellipsis,
        //                   ),
        //                 ],
        //               ),
        //             )
        //           ],
        //         ),
        //       ),
        //     ),
        //   ),
        // ),

        // Bottom Summary Panel
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade400.withOpacity(0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
              border: Border.all(color: Colors.black.withOpacity(0.1), width: 1.5),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
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
                          _buildNavigationInfo("ETA", _activeNavigationRoute!['estimatedArrival'], Icons.access_time),
                          _buildNavigationInfo("Distance", _activeNavigationRoute!['distance'], Icons.straighten),
                          _buildNavigationInfo("Fare", _activeNavigationRoute!['price'], Icons.attach_money),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _stopNavigationMode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
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
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      Text(label, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
    ],
  );
}


  Widget _buildMapboxMap() {
    final engineerLat = widget.fieldEngineer['currentLatitude']?.toDouble() ?? 14.5995;
  final engineerLng = widget.fieldEngineer['currentLongitude']?.toDouble() ?? 120.9842;
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
  final engineerLat = widget.fieldEngineer['currentLatitude']?.toDouble() ?? 14.5995;
  final engineerLng = widget.fieldEngineer['currentLongitude']?.toDouble() ?? 120.9842;
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

  Widget _buildBottomSheet() {
  return DraggableScrollableSheet(
    initialChildSize: 0.4, // Starts at 40% of the screen height
    minChildSize: 0.15,    // Can be dragged down to 15%
    maxChildSize: 0.9,     // Can be dragged up to 90%
    builder: (BuildContext context, ScrollController scrollController) {
  
      return Container(
        decoration: BoxDecoration(
      
          color: Colors.white.withOpacity(0.35),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
 
          border: Border.all(
            color: Colors.black.withOpacity(0.2),
            width: 1.5,
          ),
          boxShadow: [

            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              spreadRadius: 2,
            )
          ],
        ),
 
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),

          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
            child: ListView(
              controller: scrollController, 
              padding: EdgeInsets.zero,
              children: [
                _buildDragHandle(),
                _buildOngoingRoutesPanel(),
                _buildServiceRequestsList(),
              ],
            ),
          ),
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

  /// Ongoing Routes" panel
  Widget _buildOngoingRoutesPanel() {

    return Container(
      margin: EdgeInsets.all(12.0),
      padding: EdgeInsets.all(16.0),
      decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.15), // A slightly different tint
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: Colors.black.withOpacity(0.1),
        width: 1.0,
      ),
    ),
      // decoration: BoxDecoration(
      //   gradient: LinearGradient(
      //     colors: [Colors.lightBlue.shade800, Colors.lightBlue.shade600],
      //     begin: Alignment.topLeft,
      //     end: Alignment.bottomRight,
      //   ),
      //   borderRadius: BorderRadius.circular(12),
      // ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ongoing Routes',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.yellow.shade300,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${ongoingRoutes.length}',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          if (ongoingRoutes.isEmpty)
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.directions_off, color: Colors.grey, size: 32),
                    SizedBox(height: 8),
                    Text(
                      'No active routes at the moment',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                        fontWeight: FontWeight.bold
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Accept a service request to start navigation',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else

             Column(
                    children: ongoingRoutes.map((route) {
                      Color statusColor;
                      String statusText;
                      
                      switch (route['status']) {
                        case 'in-progress':
                          statusColor = Colors.blue;
                          statusText = 'In Progress';
                          break;
                        case 'delayed':
                          statusColor = Colors.red;
                          statusText = 'Delayed';
                          break;
                        case 'arriving':
                          statusColor = Colors.green;
                          statusText = 'Arriving Soon';
                          break;
                        default:
                          statusColor = Colors.grey;
                          statusText = 'Unknown';
                      }

                      return Container(
                        margin: EdgeInsets.only(bottom: 8),
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.black.withOpacity(0.1)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.person, color: Colors.grey, size: 16),
                                          SizedBox(width: 4),
                                          Text(
                                            route['feName'],
                                            style: TextStyle(
                                              color: Colors.grey,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          Icon(Icons.location_on, color: Colors.grey, size: 14),
                                          SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              'to ${route['branchName']}',
                                              style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.8),
                                    border: Border.all(color: Colors.black.withOpacity(0.1)),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Column(
                                  children: [
                                    Icon(Icons.straighten, color: Colors.grey, size: 14),
                                    Text(
                                      'Distance',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      route['distance'],
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  children: [
                                    Icon(Icons.access_time, color: Colors.grey, size: 14),
                                    Text(
                                      'ETA',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      route['estimatedArrival'],
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  children: [
                                    Icon(Icons.attach_money, color: Colors.grey, size: 14),
                                    Text(
                                      'Fare',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      route['price'],
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.play_arrow, color: Colors.white70, size: 14),
                                    SizedBox(width: 4),
                                    Text(
                                      'Started: ${route['startTime']}',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                                ElevatedButton(
                                  onPressed: () => stopNavigation(route),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.stop, size: 12, color: Colors.white),
                                      SizedBox(width: 4),
                                      Text(
                                        'Stop',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
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
    child: const Icon(
      Icons.account_balance,
      color: Colors.white,
      size: 24,
    ),
  );
}




//Widget for bottom navigation bar
Widget _buildBottomNavigationBar() {
  return BottomNavigationBar(
    items: const [
      BottomNavigationBarItem(
        icon: Icon(Icons.home),
        label: 'Home',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.history),
        label: 'History',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.settings),
        label: 'Settings',
      ),
    ],
    
  );
}
Widget _buildServiceRequestCard(Map<String, dynamic> request) {
  bool isAssignedToMe = request['fieldEngineerId'] == widget.fieldEngineer['id'];
  bool isUnassigned = request['fieldEngineerId'] == null;
  bool hasOngoingRoute = ongoingRoutes.any((route) => route['serviceRequestId'] == request['id']);

  return Container(
    margin: const EdgeInsets.only(bottom: 12.0),
    padding: const EdgeInsets.all(16.0),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.black.withOpacity(0.1)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Branch Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
            'Available Service Requests',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
                  const SizedBox(height: 7),
                  Text(
                    request['branch']?['name'] ?? 'Unknown Branch',
                    style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.grey, size: 14),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          request['branch']?['address'] ?? 'No address',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Status Tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isUnassigned ? Colors.orange.withOpacity(0.8) : Colors.green.withOpacity(0.8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isUnassigned ? 'Pending' : (hasOngoingRoute ? 'Active' : 'Accepted'),
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const Divider(color: Colors.white24, height: 24),
        // Action Button
        if (isUnassigned)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => {
                HapticFeedback.lightImpact(),
                acceptServiceRequest(request['id'])
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Accept Request'),
            ),
          ),
      ],
    ),
  );
}

  Widget _buildServiceRequestsList() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
         
          const SizedBox(height: 2),
          if (isLoading)
            const Center(child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(),
            ))
          else if (serviceRequests.isEmpty)
            // ... (Your "No service requests" widget)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No service requests found', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            )
          else

            ListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: serviceRequests
                .map((request) => _buildServiceRequestCard(request))
                .toList(),
          ),
        ],
      ),
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
                Text('FCM: ${fcmToken!.substring(0, 20)}...',
                    style: TextStyle(fontSize: 10)),
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