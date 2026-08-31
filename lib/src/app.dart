import 'package:flutter/material.dart';

import 'features/tracking/presentation/tracking_screen.dart';

class MdfTrackerApp extends StatelessWidget {
  const MdfTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00B0FF),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'MDF Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: const TrackingScreen(),
    );
  }
}
