import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../mock/mock_data_seeder.dart';
import '../../core/config/env.dart';
import '../../features/settings/users/users_state.dart' show activeUserProvider;
import '../../core/state/db_providers.dart';
import '../../core/theme/tokens.dart';

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

      // Wipe all user data in a single transaction while keeping the DB
      // connection open — this keeps the Riverpod provider valid and avoids
      // WAL/SHM file inconsistencies from manual file deletion.
      await db.transaction(() async {
        await db.delete(db.clipsTable).go();       // cascade-deletes thumbnails
        await db.delete(db.teamMatchesTable).go();  // cascade-deletes (already empty) clips
        await db.delete(db.playersTable).go();
        await db.delete(db.teamsTable).go();
        await db.delete(db.streamingDestinationsTable).go();
        await db.delete(db.sportPresetsTable).go();
        await db.delete(db.usersTable).go();
      });

      // Re-apply base seed and optional mock fixtures.
      await db.seedBaseData();
      if (kUseMockData) {
        await MockDataSeeder(db).seed();
      }

      // Reset the active user to the default so all provider scopes
      // that watch activeUserProvider reload their data correctly.
      ref.read(activeUserProvider.notifier).state = 'default-user';

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Database reset.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset failed: $e')),
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
// Tab views — each builds on _StreamTab to eliminate StreamBuilder boilerplate
// ---------------------------------------------------------------------------

class _UsersTab extends StatelessWidget {
  const _UsersTab({required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context) => _StreamTab(
        stream: db.usersDao.watchAll(),
        empty: 'No users',
        rowBuilder: (u) => _Row(primary: u.id, secondary: u.name),
      );
}

class _TeamsTab extends ConsumerWidget {
  const _TeamsTab({required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(activeUserProvider) ?? 'default-user';
    return _StreamTab(
      stream: db.teamsDao.watchForUser(userId),
      empty: 'No teams',
      rowBuilder: (t) => _Row(
        primary: t.name,
        secondary: '${t.sport} · ${t.id}',
      ),
    );
  }
}

class _MatchesTab extends StatelessWidget {
  const _MatchesTab({required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context) => _StreamTab(
        stream: db.select(db.teamMatchesTable).watch(),
        empty: 'No matches',
        rowBuilder: (m) => _Row(
          primary: '${m.opponent} (${m.kind})',
          secondary: '${m.date} · ${m.result}',
        ),
      );
}

class _ClipsTab extends StatelessWidget {
  const _ClipsTab({required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context) => _StreamTab(
        stream: db.select(db.clipsTable).watch(),
        empty: 'No clips',
        rowBuilder: (c) => _Row(
          primary: c.label ?? c.id,
          secondary: 'start=${c.startSeconds}s dur=${c.durationSeconds}s',
        ),
      );
}

class _StreamTab<R> extends StatelessWidget {
  const _StreamTab({
    required this.stream,
    required this.empty,
    required this.rowBuilder,
  });
  final Stream<List<R>> stream;
  final String empty;
  final Widget Function(R) rowBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<R>>(
      stream: stream,
      builder: (_, snap) {
        if (snap.hasError) return _Empty('Error: ${snap.error}');
        final rows = snap.data ?? [];
        if (rows.isEmpty) return _Empty(empty);
        return ListView(children: rows.map(rowBuilder).toList());
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
