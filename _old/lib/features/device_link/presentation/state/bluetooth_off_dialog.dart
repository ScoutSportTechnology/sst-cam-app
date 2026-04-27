import 'package:flutter/material.dart';

class BluetoothOffDialog extends StatelessWidget {
  const BluetoothOffDialog({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bluetooth is off'),
      content: const Text(
        'Enable Bluetooth in system settings to scan for devices.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            onOpenSettings();
          },
          child: const Text('Open settings'),
        ),
      ],
    );
  }
}

Future<void> showBluetoothOffDialog(
  BuildContext context, {
  required VoidCallback onOpenSettings,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => BluetoothOffDialog(onOpenSettings: onOpenSettings),
  );
}
