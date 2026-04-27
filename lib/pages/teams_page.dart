import 'package:flutter/material.dart';

/// Phase 3 — local team/player CRUD with drift database.
class TeamsPage extends StatelessWidget {
  const TeamsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teams')),
      body: const Center(
        child: Text('Team management — Phase 3'),
      ),
    );
  }
}
