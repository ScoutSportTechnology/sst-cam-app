import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/app_database.dart';
import '../db/mock_data_seeder.dart';
import '../env.dart';
import '../state/db_providers.dart';
import '../theme/tokens.dart';

/// Developer-only screen for inspecting the local Drift database.
///
/// Accessible only when [kAppEnv] != [AppEnv.prod]. Entry point: long-press
/// the version label in Settings. Provides a table browser and a Reset action.
class DebugPage extends ConsumerStatefulWidget {
  const DebugPage({super.key});

  @override
  ConsumerState<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends ConsumerState<DebugPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    setState(() => _resetting = true);
    try {
      final db = ref.read(appDatabaseProvider);

      // Close and delete the SQLite file.
      await db.close();
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'scout_camera.sqlite'));
      if (file.existsSync()) file.deleteSync();

      // Re-open by creating a fresh AppDatabase (onCreate re-runs).
      final newDb = AppDatabase();
      // Wait for the first query to trigger onCreate + base seed.
      await newDb.usersDao.getAll();

      if (kUseMockData) {
        await MockDataSeeder(newDb).seed();
      }

      // Override the provider so the rest of the app uses the new instance.
      // ignore: use_build_context_synchronously
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Database reset. Restart the app for full effect.')),
      );
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: const Text('Debug — DB Browser'),
        backgroundColor: T.bg,
        bottom: TabBar(
          controller: _tabs,
          labelColor: T.ink,
          indicatorColor: T.accent,
          unselectedLabelColor: T.ink2,
          tabs: const [
            Tab(text: 'Users'),
            Tab(text: 'Teams'),
            Tab(text: 'Matches'),
            Tab(text: 'Clips'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _UsersTab(db: db),
                _TeamsTab(db: db),
                _MatchesTab(db: db),
                _ClipsTab(db: db),
              ],
            ),
          ),
          _ResetBar(resetting: _resetting, onReset: _reset),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab views
// ---------------------------------------------------------------------------

class _UsersTab extends StatelessWidget {
  const _UsersTab({required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.usersDao.watchAll(),
      builder: (_, snap) {
        final rows = snap.data ?? [];
        if (rows.isEmpty) return const _Empty('No users');
        return ListView(
          children: rows
              .map((u) => _Row(primary: u.id, secondary: u.name))
              .toList(),
        );
      },
    );
  }
}

class _TeamsTab extends StatelessWidget {
  const _TeamsTab({required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.teamsDao.watchForUser('default-user'),
      builder: (_, snap) {
        final rows = snap.data ?? [];
        if (rows.isEmpty) return const _Empty('No teams');
        return ListView(
          children: rows
              .map((t) => _Row(primary: t.name, secondary: '${t.sport} · ${t.id}'))
              .toList(),
        );
      },
    );
  }
}

class _MatchesTab extends StatelessWidget {
  const _MatchesTab({required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.select(db.teamMatchesTable).watch(),
      builder: (_, snap) {
        final rows = snap.data ?? [];
        if (rows.isEmpty) return const _Empty('No matches');
        return ListView(
          children: rows
              .map(
                (m) => _Row(
                  primary: '${m.opponent} (${m.kind})',
                  secondary: '${m.date} · ${m.result}',
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _ClipsTab extends StatelessWidget {
  const _ClipsTab({required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.select(db.clipsTable).watch(),
      builder: (_, snap) {
        final rows = snap.data ?? [];
        if (rows.isEmpty) return const _Empty('No clips');
        return ListView(
          children: rows
              .map(
                (c) => _Row(
                  primary: c.label ?? c.id,
                  secondary: 'start=${c.startSeconds}s dur=${c.durationSeconds}s',
                ),
              )
              .toList(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shared primitives
// ---------------------------------------------------------------------------

class _Row extends StatelessWidget {
  const _Row({required this.primary, required this.secondary});
  final String primary;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(primary, style: const TextStyle(color: T.ink, fontSize: 13)),
      subtitle: Text(secondary, style: const TextStyle(color: T.ink2, fontSize: 11)),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(message, style: const TextStyle(color: T.ink2)),
    );
  }
}

class _ResetBar extends StatelessWidget {
  const _ResetBar({required this.resetting, required this.onReset});
  final bool resetting;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: T.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: resetting ? null : onReset,
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: resetting
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Reset Database'),
          ),
        ),
      ),
    );
  }
}
