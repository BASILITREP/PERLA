import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Top-level function for background message handling
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Handling a background message: ${message.messageId}');
  print('Message data: ${message.data}');
  print('Message notification: ${message.notification?.title}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Set the background messaging handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const LoginPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  bool isLoading = false;

  Future<void> authenticateFieldEngineer() async {
    setState(() {
      isLoading = true;
    });

    try {
      final response = await http.get(
        Uri.parse('https://ecsmapappwebadminbackend-production.up.railway.app/api/FieldEngineer'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> engineers = json.decode(response.body);
        final engineer = engineers.firstWhere(
          (eng) => eng['email'].toLowerCase() == _emailController.text.toLowerCase(),
          orElse: () => null,
        );

        if (engineer != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => MyHomePage(
                title: 'PERLA - ${engineer['name']}',
                fieldEngineer: engineer,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Field Engineer not found')),
          );
        }
      }
    } catch (e) {
      print('Error authenticating: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }

    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('PEARL Login'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              decoration: InputDecoration(
                labelText: 'Email',
                hintText: 'basilcarmonasantiago@gmail.com',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            SizedBox(height: 20),
            isLoading
                ? CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: authenticateFieldEngineer,
                    child: Text('Login'),
                  ),
          ],
        ),
      ),
    );
  }
}

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

  // FCM and Local Notifications
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initializeFCM();
    fetchServiceRequests();
    fetchBranches();
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
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'fieldEngineerId': widget.fieldEngineer['id'],
        }),
      );

      print('Accept response: ${acceptResponse.statusCode}');
      print('Accept response body: ${acceptResponse.body}');

      if (acceptResponse.statusCode == 200) {
        final serviceRequest = serviceRequests.firstWhere(
          (sr) => sr['id'] == serviceRequestId,
          orElse: () => null,
        );

        if (serviceRequest != null) {
          final branch = branches.firstWhere(
            (b) => b['id'].toString() == serviceRequest['branchId'].toString(),
            orElse: () => null,
          );

          if (branch != null) {
            final routeData = await getMapboxRoute(
              widget.fieldEngineer['currentLatitude'].toDouble(),
              widget.fieldEngineer['currentLongitude'].toDouble(),
              branch['latitude'].toDouble(),
              branch['longitude'].toDouble(),
            );

            if (routeData != null) {
              final routeCoordinates = routeData['geometry']['coordinates'];
              final startTime = DateTime.now().toLocal();
              final durationMinutes = (routeData['duration'] / 60).round();
              final etaTime = startTime.add(Duration(minutes: durationMinutes));
              final distanceInKm = routeData['distance'] / 1000;

              await startFieldEngineerNavigation(
                widget.fieldEngineer['id'],
                widget.fieldEngineer['name'],
                routeCoordinates,
              );

              final newRouteData = {
                'id': DateTime.now().millisecondsSinceEpoch,
                'feId': widget.fieldEngineer['id'],
                'feName': widget.fieldEngineer['name'],
                'branchId': branch['id'],
                'branchName': branch['name'],
                'startTime': startTime.toLocal().toString().substring(11, 16),
                'estimatedArrival': etaTime.toLocal().toString().substring(11, 16),
                'distance': formatDistance(routeData['distance'].toDouble()),
                'duration': '${durationMinutes} min',
                'price': calculateFare(distanceInKm),
                'status': 'in-progress',
                'serviceRequestId': serviceRequestId,
                'routeCoordinates': routeCoordinates,
              };

              await createNewRoute(newRouteData);
              await triggerWebAdminUpdate(serviceRequestId, widget.fieldEngineer['id']);

              setState(() {
                ongoingRoutes.add(newRouteData);
              });

              Navigator.of(context).pop();
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ Service request accepted!\n🚗 Navigation started!\n📍 Web admin updated!'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );

              await Future.delayed(Duration(seconds: 2));
              fetchServiceRequests();

            } else {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Service request accepted, but failed to get route'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          } else {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Service request accepted, but branch not found'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept request: ${acceptResponse.statusCode}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      
      print('Error accepting request: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error accepting request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

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
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.lightBlue.shade800, Colors.lightBlue.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Row(
          children: [
            Icon(Icons.notifications, color: Colors.white),
            SizedBox(width: 8),
            Text(widget.title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            if (fcmToken != null) 
              Container(
                margin: EdgeInsets.only(left: 8),
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('🔔', style: TextStyle(fontSize: 10)),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.person, color: Colors.white),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('Field Engineer Info'),
                  content: Column(
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
                        Text('FCM: ${fcmToken!.substring(0, 20)}...', style: TextStyle(fontSize: 10)),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // FCM Status Banner
          if (fcmToken != null)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(8),
              color: Colors.green.shade100,
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Push notifications enabled',
                    style: TextStyle(color: Colors.green.shade800, fontSize: 12),
                  ),
                ],
              ),
            ),

          // Ongoing Routes Panel
          Container(
            margin: EdgeInsets.all(8.0),
            padding: EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.lightBlue.shade800, Colors.lightBlue.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Ongoing Routes',
                      style: TextStyle(
                        color: Colors.white,
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
                          Icon(Icons.directions_off, color: Colors.white70, size: 32),
                          SizedBox(height: 8),
                          Text(
                            'No active routes at the moment',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Accept a service request to start navigation',
                            style: TextStyle(
                              color: Colors.white54,
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
                          border: Border.all(color: statusColor.withOpacity(0.3)),
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
                                          Icon(Icons.person, color: Colors.white, size: 16),
                                          SizedBox(width: 4),
                                          Text(
                                            route['feName'],
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          Icon(Icons.location_on, color: Colors.white70, size: 14),
                                          SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              'to ${route['branchName']}',
                                              style: TextStyle(
                                                color: Colors.white70,
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
                                    Icon(Icons.straighten, color: Colors.white60, size: 14),
                                    Text(
                                      'Distance',
                                      style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      route['distance'],
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  children: [
                                    Icon(Icons.access_time, color: Colors.white60, size: 14),
                                    Text(
                                      'ETA',
                                      style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      route['estimatedArrival'],
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  children: [
                                    Icon(Icons.attach_money, color: Colors.white60, size: 14),
                                    Text(
                                      'Fare',
                                      style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      route['price'],
                                      style: TextStyle(
                                        color: Colors.white,
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
                                        color: Colors.white70,
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
                                    minimumSize: Size(60, 30),
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
          ),
          
          // Service Requests List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : serviceRequests.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('No service requests found'),
                            SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: fetchServiceRequests,
                              child: Text('Refresh'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: serviceRequests.length,
                        itemBuilder: (context, index) {
                          final request = serviceRequests[index];
                          bool isAssignedToMe = request['fieldEngineerId'] == widget.fieldEngineer['id'];
                          bool isUnassigned = request['fieldEngineerId'] == null;
                          
                          bool hasOngoingRoute = ongoingRoutes.any((route) => 
                            route['serviceRequestId'] == request['id']
                          );
                          
                          return Card(
                            margin: const EdgeInsets.all(8.0),
                            elevation: 4,
                            color: isAssignedToMe ? Colors.green.shade50 : Colors.white,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isUnassigned 
                                    ? Colors.orange 
                                    : isAssignedToMe 
                                        ? Colors.green 
                                        : Colors.grey,
                                child: Text(
                                  '${request['id']}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              title: Text(
                                'Service Request #${request['id']}',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Status: ${request['status'] ?? 'N/A'}'),
                                  Text('Branch: ${request['branch']?['name'] ?? 'N/A'}'),
                                  Text('Title: ${request['title'] ?? 'N/A'}'),
                                  Text('Description: ${request['description'] ?? 'N/A'}'),
                                  SizedBox(height: 4),
                                  if (isAssignedToMe && hasOngoingRoute)
                                    Row(
                                      children: [
                                        Icon(Icons.navigation, color: Colors.blue, size: 16),
                                        SizedBox(width: 4),
                                        Text(
                                          'Navigation Active', 
                                          style: TextStyle(
                                            color: Colors.blue, 
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          )
                                        ),
                                      ],
                                    ),
                                  if (isAssignedToMe && !hasOngoingRoute)
                                    Row(
                                      children: [
                                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                                        SizedBox(width: 4),
                                        Text(
                                          'Assigned to you', 
                                          style: TextStyle(
                                            color: Colors.green, 
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          )
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              trailing: isUnassigned
                                  ? ElevatedButton.icon(
                                      onPressed: () => acceptServiceRequest(request['id']),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                      icon: Icon(Icons.check, size: 16),
                                      label: Text('Accept', style: TextStyle(fontSize: 12)),
                                    )
                                  : isAssignedToMe
                                      ? Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              hasOngoingRoute ? Icons.navigation : Icons.check_circle, 
                                              color: hasOngoingRoute ? Colors.blue : Colors.green,
                                              size: 24,
                                            ),
                                            Text(
                                              hasOngoingRoute ? 'Active' : 'Accepted', 
                                              style: TextStyle(
                                                fontSize: 10, 
                                                color: hasOngoingRoute ? Colors.blue : Colors.green,
                                                fontWeight: FontWeight.bold,
                                              )
                                            ),
                                          ],
                                        )
                                      : Icon(Icons.person, color: Colors.grey),
                            ),
                          );
                        },
                      ),
          ),
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
    );
  }
}