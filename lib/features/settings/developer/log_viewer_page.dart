import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/log_service.dart';
import '../../../core/theme/tokens.dart';

/// In-app viewer for the [LogService] ring buffer. Newest line at the bottom;
/// copy-all puts the whole buffer on the clipboard (paste into a bug report)
/// since adb isn't always available. adb/logcat stays the primary path.
class LogViewerPage extends StatelessWidget {
  const LogViewerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final log = LogService.instance;
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            icon: const Icon(Icons.copy_all),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: log.export()));
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
          final lines = log.lines;
          if (lines.isEmpty) {
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
            itemCount: lines.length,
            itemBuilder: (context, i) {
              final line = lines[lines.length - 1 - i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: SelectableText(
                  line,
                  style: const TextStyle(
                    fontFamily: T.mono,
                    fontSize: 11,
                    color: T.ink2,
                    height: 1.4,
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
