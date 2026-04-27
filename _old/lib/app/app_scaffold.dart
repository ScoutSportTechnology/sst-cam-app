import 'package:flutter/material.dart';
import 'app_nav_bar.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: const Text('Status Bar'),
          ),
          Container(padding: EdgeInsets.all(16), child: Text('Body')),
          Container(padding: EdgeInsets.all(16), child: AppNavBar()),
        ],
      ),
    );
  }
}
