import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'screens/login_screen.dart';
import 'package:google_fonts/google_fonts.dart';



// Top-level function for background message handling
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Handling a background message: ${message.messageId}');
  print('Message data: ${message.data}');
  print('Message notification: ${message.notification?.title}');
}

void main() async {
  await setup();
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Set the background messaging handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  runApp(const MyApp());
}

Future<void> setup() async{
  await dotenv.load(
    fileName: ".env"
    );
    MapboxOptions.setAccessToken(dotenv.env['MAPBOX_ACCESS_TOKEN']!);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    
    const seedColor = Color(0xFF0066B2); 

    return MaterialApp(
      title: 'PERLA Field App',
      theme: ThemeData(

        useMaterial3: true,

        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),

        textTheme: GoogleFonts.outfitTextTheme(
          ThemeData(brightness: Brightness.light).textTheme,
        ),
      ),
      // darkTheme: ThemeData(
      //   useMaterial3: true,
      //   colorScheme: ColorScheme.fromSeed(
      //     seedColor: seedColor,
      //     brightness: Brightness.dark,
      //   ),
      //   textTheme: GoogleFonts.lexendTextTheme(
      //     ThemeData(brightness: Brightness.dark).textTheme,
      //   ),
      // ),
      themeMode: ThemeMode.system, 
      home: const LoginPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}



  


