import 'package:flutter/material.dart';

/// Phase 5 — recording list, WiFi download, local playback.
class VideoPage extends StatelessWidget {
  const VideoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video')),
      body: const Center(
        child: Text('Recording library — Phase 5'),
      ),
    );
  }
}
