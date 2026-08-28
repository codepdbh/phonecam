import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/ui/main_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: PhoneCamWindowsApp(),
    ),
  );
}

class PhoneCamWindowsApp extends StatelessWidget {
  const PhoneCamWindowsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PhoneCam - Virtual Camera Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090D13),
        primaryColor: const Color(0xFF00E5FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF58A6FF),
          surface: Color(0xFF101622),
          error: Color(0xFFFF5252),
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}
