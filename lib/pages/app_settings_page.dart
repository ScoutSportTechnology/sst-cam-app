import 'package:flutter/material.dart';

import '../env.dart';
import '../theme/tokens.dart';
import '../widgets/wf_card.dart';
import 'debug_page.dart';

class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(title: const Text('App')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          WfCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                const _AppRowItem(
                  leading: Icon(Icons.palette_outlined),
                  label: 'Theme',
                  trailing: Text(
                    'Dark',
                    style: TextStyle(color: T.ink2, fontSize: 12),
                  ),
                ),
                const Divider(height: 1, color: T.rule),
                const _AppRowItem(
                  leading: Icon(Icons.lock_outline),
                  label: 'Permissions',
                  trailing: Text(
                    '3 granted',
                    style: TextStyle(color: T.ink2, fontSize: 12),
                  ),
                ),
                const Divider(height: 1, color: T.rule),
                GestureDetector(
                  onLongPress: kAppEnv != AppEnv.prod
                      ? () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const DebugPage(),
                            ),
                          )
                      : null,
                  child: const _AppRowItem(
                    leading: Icon(Icons.info_outline),
                    label: 'About',
                    trailing: Text(
                      '0.3.2',
                      style: TextStyle(color: T.ink2, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Local copy of the row primitive (same layout as _RowItem in settings_page.dart)
class _AppRowItem extends StatelessWidget {
  const _AppRowItem({
    required this.leading,
    required this.label,
    this.trailing,
  });
  final Widget leading;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(width: 24, child: Center(child: leading)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: T.ink,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
