import 'package:flutter/material.dart';

/// Phase 6 — per-camera config (streaming keys, WiFi, firmware) + app prefs.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(
        child: Text('Settings — Phase 6'),
      ),
    );
  }
}
