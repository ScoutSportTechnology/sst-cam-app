import 'package:flutter/material.dart';

class DeviceNotFound extends StatelessWidget {
  const DeviceNotFound({super.key});

  final String title = 'No devices yet';
  final List<String> tips = const [
    'Move closer to the device',
    'Ensure the device is powered on',
    'Put the device in pairing/discovery mode',
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleMedium),
          const SizedBox(height: 10),
          ...tips.map(
            (t) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(height: 1.25)),
                  Expanded(child: Text(t, style: text.bodyMedium)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
