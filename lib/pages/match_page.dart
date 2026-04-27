import 'package:flutter/material.dart';

/// Phase 4 — match setup, live score controls, banner events.
class MatchPage extends StatelessWidget {
  const MatchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match')),
      body: const Center(
        child: Text('Match controls — Phase 4'),
      ),
    );
  }
}
