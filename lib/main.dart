import 'package:flutter/material.dart';

import 'screens/beam_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BeamQrApp());
}

class BeamQrApp extends StatelessWidget {
  const BeamQrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BeamQR',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(
          primary: Colors.indigoAccent,
          secondary: Colors.cyanAccent,
          surface: Color(0xFF161B22),
        ),
      ),
      home: const BeamHomeScreen(),
    );
  }
}

