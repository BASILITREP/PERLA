// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'screens/login_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/location_service.dart';

// Top-level function for background message handling
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Handling a background message: ${message.messageId}');
}


Future<void> initializeNotifications() async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'dorothy_location_service', 
    'DOROTHY Location Service',
    description: 'Notification channel for location tracking service.',
    importance: Importance.low, // Use low importance to avoid sound
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}



void main() async {

  WidgetsFlutterBinding.ensureInitialized();
  
  await setup(); 
  await Firebase.initializeApp();

  await initializeNotifications();


  await LocationService().initialize();

  
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  runApp(const MyApp());
}

Future<void> setup() async {
  await dotenv.load(fileName: ".env");
  MapboxOptions.setAccessToken(dotenv.env['MAPBOX_ACCESS_TOKEN']!);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Custom colors - UPDATED
    const primaryColor = Color.fromARGB(255, 116, 109, 241); // Deep purple background
    const accentColor = Color.fromARGB(255, 246, 255, 168);  // Bright yellow-green accent

    return MaterialApp(
      title: 'Dorothy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: Brightness.light,
          // Override specific colors for better contrast
          surface: primaryColor,           // Background color
          onSurface: Colors.white,        // Text on background
          primary: accentColor,           // Button color
          onPrimary: Colors.black87,      // Text on buttons (BLACK for yellow)
          primaryContainer: accentColor,   // FAB background
          onPrimaryContainer: Colors.black87, // FAB text/icons (BLACK for yellow)
          secondary: accentColor.withOpacity(0.8),
          tertiary: accentColor.withOpacity(0.6),
        ),
        // Custom button themes for consistent yellow-green buttons
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.black87, // BLACK text on yellow
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.black87, // BLACK text on yellow
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: accentColor,
          foregroundColor: Colors.black87, // BLACK icons on yellow
        ),
        // App bar with deep purple background
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        // Card theme for better contrast
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        // Scaffold background
        scaffoldBackgroundColor: primaryColor,
        textTheme: GoogleFonts.outfitTextTheme(
          ThemeData(brightness: Brightness.light).textTheme,
        ).apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
      ),
      home: const LoginPage(),
    );
  }
}