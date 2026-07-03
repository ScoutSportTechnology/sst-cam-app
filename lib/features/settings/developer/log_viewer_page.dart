import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/log_service.dart';
import '../../../core/theme/tokens.dart';

/// In-app viewer for the [LogService] ring buffer. Newest line at the bottom;
/// copy-all puts the whole buffer on the clipboard (paste into a bug report)
/// since adb isn't always available. adb/logcat stays the primary path. Each
/// line renders in the standardized structure with the level color-highlighted.
class LogViewerPage extends StatelessWidget {
  const LogViewerPage({super.key, this.title = 'Logs', this.filter});

  /// App-bar title — distinguishes the App vs Camera-link views.
  final String title;

  /// Optional entry predicate. When set, only matching entries render/export —
  /// used for the live "Camera link" view (the BLE/WiFi comms the app captures).
  final bool Function(LogEntry)? filter;

  /// Color for a log level's highlighted token.
  static Color _levelColor(String level) {
    switch (level.toUpperCase()) {
      case 'SHOUT':
      case 'SEVERE':
      case 'ERROR':
        return T.danger;
      case 'WARNING':
      case 'WARN':
        return T.warn;
      case 'INFO':
        return T.ink;
      default: // CONFIG / FINE / FINER / FINEST / debug
        return T.ink3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final log = LogService.instance;
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            icon: const Icon(Icons.copy_all),
            onPressed: () async {
              final f = filter;
              final selected = f == null ? log.entries : log.entries.where(f);
              final text = selected.map((e) => e.formatted).join('\n');
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Logs copied to clipboard')),
                );
              }
            },
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: log.clear,
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: log.revision,
        builder: (context, _, _) {
          final f = filter;
          final entries = f == null
              ? log.entries
              : log.entries.where(f).toList(growable: false);
          if (entries.isEmpty) {
            return const Center(
              child: Text(
                'No logs captured yet',
                style: TextStyle(color: T.ink2, fontSize: 13),
              ),
            );
          }
          return ListView.builder(
            reverse: true,
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[entries.length - 1 - i];
              const base = TextStyle(
                fontFamily: T.mono,
                fontSize: 11,
                color: T.ink3,
                height: 1.4,
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: SelectableText.rich(
                  TextSpan(
                    style: base,
                    children: [
                      TextSpan(text: '${e.timestamp} '),
                      TextSpan(
                        text: e.level,
                        style: TextStyle(
                          color: _levelColor(e.level),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(text: ' [${e.source} (${e.isolate})]: '),
                      TextSpan(
                        text: e.message,
                        style: const TextStyle(color: T.ink2),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
