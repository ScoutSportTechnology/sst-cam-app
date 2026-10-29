import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import 'camera_calibration_page.dart';

/// Diagnostic → Calibration: hardware calibration tools. Camera colour today;
/// room for lens / focus / audio calibration later.
class CalibrationPage extends StatelessWidget {
  const CalibrationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(title: const Text('Calibration'), backgroundColor: T.bg),
      body: ListView(
        children: [
          Material(
            color: Colors.transparent,
            child: ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Camera'),
              subtitle: const Text('Colour / white-balance tuning'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CameraCalibrationPage(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
