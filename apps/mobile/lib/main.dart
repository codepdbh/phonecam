import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/ui/screens/camera_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(
    const ProviderScope(
      child: PhoneCamMobileApp(),
    ),
  );
}

class PhoneCamMobileApp extends StatelessWidget {
  const PhoneCamMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PhoneCam',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: const Color(0xFF00E5FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF58A6FF),
          surface: Color(0xFF0F141E),
          error: Color(0xFFFF5252),
        ),
        useMaterial3: true,
      ),
      home: const CameraScreen(),
    );
  }
}
