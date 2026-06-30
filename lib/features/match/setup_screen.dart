// Setup screen — review a scheduled match before going live.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_providers.dart';
import '../../core/models/command.dart';
import '../../core/models/device.dart';
import '../../core/models/streaming.dart';
import '../../core/state/db_providers.dart' show teamsDaoProvider;
import '../../core/theme/tokens.dart';
import '../../core/widgets/wf_button.dart';
import '../../core/widgets/wf_card.dart';
import '../../core/widgets/wf_chip.dart';
import '../../core/models/overlay_layout.dart';
import '../camera/camera_state.dart' show activeCameraIdProvider;
import '../settings/sport_presets/sport_presets_state.dart'
    show sportPresetsForSportProvider, SportPreset;
import '../settings/streaming/streaming_destination_form_sheet.dart'
    show showStreamingDestinationFormSheet;
import '../settings/streaming/streaming_state.dart'
    show streamingDestinationsControllerProvider;
import '../settings/users/users_state.dart' show activeUserProvider;
import 'match_state.dart' show UpcomingMatch;
import 'session/session_state.dart' show liveMatchProvider;

enum _Quality {
  hd720p30('720p · 30 fps'),
  fhd1080p30('1080p · 30 fps'),
  fhd1080p60('1080p · 60 fps'),
  uhd4k30('4K · 30 fps');

  const _Quality(this.label);
  final String label;
}

/// A resolved per-match streaming selection. [wireUrl] is the full ingest URL
/// sent to the camera (base + key). [storeUrl]/[storeKey] persist on the match
/// row (a saved destination keeps base + key split; a one-off keeps the full URL
/// with a null key).
typedef _StreamSelection = ({
  String wireUrl,
  String storeUrl,
  String? storeKey,
  String label,
});

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({
    super.key,
    required this.match,
    required this.onBack,
    required this.onStart,
  });
  final UpcomingMatch match;
  final VoidCallback onBack;
  final VoidCallback onStart;

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  _Quality _quality = _Quality.fhd1080p30;
  // null = Custom (use _customPeriods + _customMinutes from match init).
  SportPreset? _preset;
  int _customPeriods = 2;
  int _customPeriodSeconds = 35 * 60;
  bool _initialized = false;

  // Streaming destination for this match: a saved persistent destination or a
  // per-match one-off. Null = record without streaming.
  _StreamSelection? _stream;

  // Session push state (U9).
  bool _pushing = false;
  String? _pushError;
  // Stable match UUID for the current setup session. Generated on first tap
  // and reused on retry so the camera always sees the same UUID.
  String? _matchUuid;

  @override
  Widget build(BuildContext context) {
    final team = widget.match.team;
    final m = widget.match.match;
    final presets = ref.watch(sportPresetsForSportProvider(team.sport));
    final activeId = ref.watch(activeCameraIdProvider);
    final connected =
        activeId != null &&
        ref.watch(connectionStateProvider(activeId)).valueOrNull ==
            CameraConnectionState.connected;

    if (!_initialized) {
      _customPeriods = m.numPeriods > 0 ? m.numPeriods : 2;
      _customPeriodSeconds = m.periodLengthSeconds > 0
          ? m.periodLengthSeconds
          : 35 * 60;
      // Preselect a preset that matches the scheduled time config, if any.
      _preset = presets
          .where(
            (p) =>
                p.numPeriods == _customPeriods &&
                p.periodLengthSeconds == _customPeriodSeconds,
          )
          .firstOrNull;
      _initialized = true;
    }

    final periods = _preset?.numPeriods ?? _customPeriods;
    final periodMinutes =
        (_preset?.periodLengthSeconds ?? _customPeriodSeconds) ~/ 60;
    final formatLabel = _preset != null
        ? _stripSportPrefix(_preset!.name, team.sport)
        : 'Custom';

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: const Text('Match setup'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const WfSection('Match'),
          _RowItem(
            leading: _AvatarCircle(label: team.shortName),
            title: team.name,
            subtitle: 'Home',
          ),
          const Divider(height: 1, color: T.rule),
          _RowItem(
            leading: const Icon(Icons.shield_outlined),
            title: m.opponent,
            subtitle: 'Away · ${m.date}',
          ),
          const WfSection('Format'),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: WfCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _ValueRow(label: 'Sport', value: team.sport),
                  const Divider(height: 1, color: T.rule),
                  _ValueRow(
                    label: 'Format',
                    value: '$formatLabel · $periods × $periodMinutes min',
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in presets)
                  GestureDetector(
                    onTap: () => setState(() => _preset = p),
                    child: WfChip(
                      label: _stripSportPrefix(p.name, team.sport),
                      active: _preset?.id == p.id,
                    ),
                  ),
                GestureDetector(
                  onTap: () => _editCustom(context),
                  child: WfChip(label: 'Custom…', active: _preset == null),
                ),
              ],
            ),
          ),
          const WfSection('Recording'),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: WfCard(
              padding: EdgeInsets.zero,
              child: _DropdownRow<_Quality>(
                label: 'Quality',
                value: _quality,
                items: _Quality.values,
                labelOf: (q) => q.label,
                onChanged: (v) => setState(() => _quality = v),
              ),
            ),
          ),
          const WfSection('Streaming'),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: WfCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const WfNote('DESTINATION'),
                  const SizedBox(height: 8),
                  _buildStreamChips(),
                  const SizedBox(height: 8),
                  WfNote(
                    _stream == null
                        ? 'Recording only — no live stream. Pick a saved '
                              'destination or add a one-off for this match.'
                        : 'Streaming this match to ${_stream!.label}.',
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: WfButton(
              label: _pushing ? 'Configuring camera…' : 'Start match',
              variant: WfButtonVariant.primary,
              size: WfButtonSize.lg,
              full: true,
              onPressed: (_pushing || !connected)
                  ? null
                  : () => _startMatch(
                      periods,
                      _preset?.periodLengthSeconds ?? _customPeriodSeconds,
                    ),
            ),
          ),
          if (!connected)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                'Connect a camera to start the match.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: T.ink2),
              ),
            ),
          if (_pushing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: LinearProgressIndicator()),
            ),
          if (_pushError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _pushError!,
                    style: const TextStyle(color: T.danger, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  WfButton(
                    label: 'Retry',
                    variant: WfButtonVariant.outline,
                    full: true,
                    onPressed: connected
                        ? () => _startMatch(
                            periods,
                            _preset?.periodLengthSeconds ??
                                _customPeriodSeconds,
                          )
                        : null,
                  ),
                ],
              ),
            )
          else
            const SizedBox(height: 14),
        ],
      ),
    );
  }

  // matchUuid is the team_match id — a v4 UUID by contract (ids are minted with
  // Uuid().v4()). It is interpolated into the camera filesystem path, so enforce
  // the UUID shape here: it both upholds the "ids are UUIDs, never strings" rule
  // and guarantees the value can't contain a '/'/'.'/'..' that escapes the dir.
  static final _uuidRegex = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  void _validateUuid(String uuid, String name) {
    if (!_uuidRegex.hasMatch(uuid)) {
      throw ArgumentError('$name is not a valid UUID: $uuid');
    }
  }

  Future<void> _startMatch(int periods, int periodLengthSeconds) async {
    final deviceId = ref.read(activeCameraIdProvider);
    if (deviceId == null) return;

    final userUuid = ref.read(activeUserProvider);
    if (userUuid == null) return;

    // Record under the team_match id (a UUID): the firmware writes to
    // .../videos/<user>/<matchUuid>/, and the Library row finalized on match end
    // shares that id, so the recording links back to it and can be downloaded.
    _matchUuid ??= widget.match.match.id;
    final matchUuid = _matchUuid!;

    // The selected destination's full ingest URL (saved or one-off), or null to
    // record without streaming. Fixes the old gap where saved destinations were
    // ignored and only a raw custom URL ever reached the camera.
    final rtmpUrl = _stream?.wireUrl;

    final opponentName = widget.match.match.opponent.startsWith('vs ')
        ? widget.match.match.opponent.substring(3)
        : widget.match.match.opponent;

    final config = PushSessionConfig(
      matchUuid: matchUuid,
      userUuid: userUuid,
      sport: widget.match.team.sport.toLowerCase(),
      numPeriods: periods,
      periodLengthSeconds: periodLengthSeconds,
      rtmpUrl: rtmpUrl,
      // Root these under the firmware's provisioned storage (chowned to the
      // non-root sst-cam service user, and the dir the DownloadServer enumerates).
      // The old /data/video|/data/thumbnail roots don't exist on the device and
      // aren't writable, so mkdir failed -> "Failed to configure camera", and any
      // recording there would also be invisible to downloads.
      videoOutputPath: '/var/lib/sst/cam/videos/$userUuid/$matchUuid/',
      thumbnailOutputPath: '/var/lib/sst/cam/thumbnails/$userUuid/$matchUuid/',
      teamAId: widget.match.team.id,
      // The opponent has no team record/UUID, so its display name doubles as the
      // stable team B identifier. ScoreUpdateCommand for the away team sends the
      // same value (see session_screen) so the firmware routes goals correctly.
      teamBId: opponentName,
      // The scoreboard bug is compact — show short codes (home short-name,
      // a derived 3-letter code for the opponent), standardised in length.
      teamAName: widget.match.team.shortName,
      teamBName: _shortCode(opponentName),
      teamAColorHex: widget.match.team.colorHex,
    );

    setState(() {
      _pushing = true;
      _pushError = null;
    });

    try {
      // matchUuid (the team_match id) is interpolated into the camera
      // filesystem path; reject anything that isn't a safe path segment before
      // it gets there, so a malformed id can't escape the per-match directory.
      _validateUuid(matchUuid, 'matchUuid');

      final ble = ref.read(bleServiceProvider);

      // Step 1: push session config.
      await ble.pushSessionConfig(deviceId, config);
      if (!mounted) return;

      // Persist the per-match streaming credential (scoped to this match only;
      // mid-match start reuses it). Clears the columns when no destination set.
      await ref
          .read(teamsDaoProvider)
          .setMatchStreamingCredential(
            matchUuid,
            rtmpUrl: _stream?.storeUrl,
            streamKey: _stream?.storeKey,
          );

      // Step 2: build and push overlay layout.
      final opponent = widget.match.match.opponent;
      final awayName = opponent.startsWith('vs ')
          ? opponent.substring(3)
          : opponent;
      final layout = defaultScoreboardLayout(
        // Short name reads best in the compact scoreboard bug.
        homeName: widget.match.team.shortName,
        awayName: awayName,
        homeColorHex: widget.match.team.colorHex,
        awayColorHex: null,
      );
      await ble.pushOverlayLayout(deviceId, layout);
      if (!mounted) return;

      // Store layout + colors in live session state.
      final ctl = ref.read(liveMatchProvider.notifier);
      ctl.setOverlayLayout(layout);
      ctl.setTeamColors(widget.match.team.colorHex, null);

      setState(() {
        _pushing = false;
      });
      widget.onStart();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pushing = false;
        _pushError = 'Failed to configure camera. Check connection and retry.';
      });
    }
  }

  /// Saved persistent RTMP destinations (custom-RTMP entries from Settings) plus
  /// a one-off chip. Single-select — the camera streams one ingest per match.
  Widget _buildStreamChips() {
    final dests =
        ref.watch(streamingDestinationsControllerProvider).valueOrNull ??
        const <StreamingDestination>[];
    final rtmpDests = dests
        .where((d) => d.config is RtmpConfig)
        .toList(growable: false);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final d in rtmpDests)
          GestureDetector(
            onTap: () => _selectSaved(d),
            child: WfChip(label: d.name, active: _stream?.label == d.name),
          ),
        GestureDetector(
          onTap: _addOneOff,
          child: WfChip(
            label: _stream?.label == 'One-off'
                ? 'One-off · configured'
                : 'One-off RTMP',
            active: _stream?.label == 'One-off',
          ),
        ),
      ],
    );
  }

  Future<void> _selectSaved(StreamingDestination d) async {
    final cfg = d.config;
    if (cfg is! RtmpConfig) return;
    if (_stream?.label == d.name) {
      setState(() => _stream = null); // tapping the active one toggles it off
      return;
    }
    // Ask for the stream key — it's per-match for platforms like YouTube. Prefill
    // with the saved key (reusable platforms like Twitch can just confirm it).
    final key = await _promptStreamKey(
      context,
      destName: d.name,
      baseUrl: cfg.url,
      initialKey: cfg.streamKey,
    );
    if (key == null) return; // cancelled
    setState(() {
      _stream = (
        wireUrl: joinRtmp(cfg.url, key),
        storeUrl: cfg.url,
        storeKey: key,
        label: d.name,
      );
    });
  }

  Future<void> _addOneOff() async {
    // Reuse the streaming-destination form (URL + key fields, RTMP/RTMPS/RTSP)
    // for a per-match one-off — same UX as Settings, just not saved globally.
    final draft = await showStreamingDestinationFormSheet(context);
    if (draft == null) return;
    final w = resolveWireStream(draft.config);
    if (w == null) return;
    setState(() {
      _stream = (
        wireUrl: w.wireUrl,
        storeUrl: w.storeUrl,
        storeKey: w.storeKey,
        label: 'One-off',
      );
    });
  }

  Future<void> _editCustom(BuildContext context) async {
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (ctx) => _CustomFormatDialog(
        initialPeriods: _customPeriods,
        initialMinutes: _customPeriodSeconds ~/ 60,
      ),
    );
    if (result == null) return;
    setState(() {
      _preset = null;
      _customPeriods = result.$1;
      _customPeriodSeconds = result.$2 * 60;
    });
  }
}

/// Drop a leading `<sport> · ` from a preset display name when shown in
/// a context where the sport is already obvious.
String _stripSportPrefix(String name, String sport) {
  final pref = '$sport · ';
  return name.startsWith(pref) ? name.substring(pref.length) : name;
}

/// A compact, scoreboard-friendly code for a free-text opponent name (which has
/// no short-name field): the first three letters, uppercased — "Eastfield FC"
/// → "EAS". Falls back to the trimmed name when it has no letters.
String _shortCode(String name) {
  final letters = name.replaceAll(RegExp('[^A-Za-z]'), '');
  if (letters.isEmpty) return name.trim().toUpperCase();
  return letters
      .substring(0, letters.length < 3 ? letters.length : 3)
      .toUpperCase();
}

// ---------------------------------------------------------------------------
// VALUE ROW
// ---------------------------------------------------------------------------

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
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
          Text(value, style: const TextStyle(fontSize: 12, color: T.ink2)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DROPDOWN ROW
// ---------------------------------------------------------------------------

class _DropdownRow<V> extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });
  final String label;
  final V value;
  final List<V> items;
  final String Function(V) labelOf;
  final ValueChanged<V> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: T.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<V>(
              value: value,
              isDense: true,
              dropdownColor: T.surface,
              style: const TextStyle(fontSize: 13, color: T.ink),
              icon: const Icon(Icons.expand_more, size: 16, color: T.ink2),
              items: [
                for (final item in items)
                  DropdownMenuItem(value: item, child: Text(labelOf(item))),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// STREAM KEY PROMPT — shown when a saved destination is picked. The stream key
// is per-match for platforms like YouTube, so it's entered/confirmed at setup
// even for a saved base URL. Returns the key, or null on cancel.
// ---------------------------------------------------------------------------

Future<String?> _promptStreamKey(
  BuildContext context, {
  required String destName,
  required String baseUrl,
  required String initialKey,
}) {
  final controller = TextEditingController(text: initialKey);
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: T.bg,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                destName,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: T.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$baseUrl — enter the stream key for this match.',
                style: const TextStyle(
                  fontSize: 11,
                  color: T.ink2,
                  height: 1.4,
                  fontFamily: T.mono,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: T.fillSoft,
                  border: Border.all(color: T.hair),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    hintText: 'stream key',
                    hintStyle: TextStyle(color: T.ink3, fontSize: 13),
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  style: const TextStyle(color: T.ink, fontSize: 13),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: WfButton(
                      label: 'Cancel',
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: WfButton(
                      label: 'Use destination',
                      variant: WfButtonVariant.primary,
                      onPressed: () =>
                          Navigator.of(ctx).pop(controller.text.trim()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// CUSTOM FORMAT DIALOG
// ---------------------------------------------------------------------------

class _CustomFormatDialog extends StatefulWidget {
  const _CustomFormatDialog({
    required this.initialPeriods,
    required this.initialMinutes,
  });
  final int initialPeriods;
  final int initialMinutes;

  @override
  State<_CustomFormatDialog> createState() => _CustomFormatDialogState();
}

class _CustomFormatDialogState extends State<_CustomFormatDialog> {
  late final TextEditingController _periods = TextEditingController(
    text: '${widget.initialPeriods}',
  );
  late final TextEditingController _minutes = TextEditingController(
    text: '${widget.initialMinutes}',
  );
  String? _error;

  @override
  void dispose() {
    _periods.dispose();
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: T.surface,
      title: const Text('Custom format'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _periods,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Periods'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _minutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Period length (min)',
                  ),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: T.danger, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final p = int.tryParse(_periods.text.trim());
            final m = int.tryParse(_minutes.text.trim());
            if (p == null || p < 1 || p > 9) {
              setState(() => _error = 'Periods must be 1–9');
              return;
            }
            if (m == null || m < 1 || m > 120) {
              setState(() => _error = 'Period length must be 1–120 min');
              return;
            }
            Navigator.of(context).pop((p, m));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ROW ITEM
// ---------------------------------------------------------------------------

class _RowItem extends StatelessWidget {
  const _RowItem({required this.title, this.subtitle, this.leading});
  final String title;
  final String? subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          if (leading != null) ...[
            SizedBox(width: 36, child: Center(child: leading)),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    color: T.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  WfNote(subtitle!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AVATAR CIRCLE (needed for setup's _RowItem leading widget)
// ---------------------------------------------------------------------------

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: T.fillSoft,
        shape: BoxShape.circle,
        border: Border.all(color: T.hair),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: T.ink2,
        ),
      ),
    );
  }
}
