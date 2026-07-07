// Setup screen — review a scheduled match before going live.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_providers.dart';
import '../../core/models/command.dart';
import '../../core/models/device.dart';
import '../../core/models/streaming.dart';
import '../../core/models/team.dart' show opponentDisplayName;
import '../../core/models/video_mode.dart';
import '../../core/state/auto_stop.dart'
    show autoStopMinutesProvider, lastPushedSessionConfigProvider;
import '../../core/state/db_providers.dart' show teamsDaoProvider;
import '../../core/state/device_health.dart' show captureBlockedProvider;
import '../../core/theme/tokens.dart';
import '../../core/widgets/device_health_banner.dart';
import '../../core/widgets/wf_button.dart';
import '../../core/widgets/wf_card.dart';
import '../../core/widgets/wf_chip.dart';
import '../../core/models/overlay_layout.dart';
import '../camera/camera_state.dart' show activeCameraIdProvider;
import '../settings/sport_presets/sport_presets_state.dart'
    show sportPresetsForSportProvider, SportPreset;
import '../settings/users/users_state.dart' show activeUserProvider;
import 'match_state.dart' show UpcomingMatch;
import 'session/session_state.dart' show liveMatchProvider;

/// The preferred default record/stream mode when the firmware advertises it:
/// 1080p30 is a sensible middle of the ladder. Falls back to the first
/// advertised mode when this exact mode isn't offered.
const _preferredDefaultMode = VideoMode(width: 1920, height: 1080, fps: 30);

/// The dropdown value for a (possibly stale) held selection against the CURRENT
/// firmware-advertised [modes]. A held pick is used only while it's still
/// offered; otherwise — and when nothing is held — it falls back to the default
/// (the preferred mode when advertised, else the first). Empty modes → null.
///
/// This keeps the DropdownButton value ALWAYS present in its items: a held value
/// that isn't in `modes` (firmware re-advertised a different set on reconnect /
/// camera switch) trips DropdownButton's value-in-items assertion and crashes
/// the build.
VideoMode? effectiveVideoMode(VideoMode? held, List<VideoMode> modes) {
  if (modes.isEmpty) return null;
  if (held != null && modes.contains(held)) return held;
  return modes.contains(_preferredDefaultMode)
      ? _preferredDefaultMode
      : modes.first;
}

/// Per-match streaming destination protocol. `none` = record without streaming.
/// The others map onto [StreamingProtocol]; the operator enters the URL (and a
/// stream key for RTMP/RTMPS) inline. NOTE: the firmware egress pushes over
/// rtmp2sink (RTMP/RTMPS only) — an RTSP destination is accepted here but will
/// not stream until firmware gains an RTSP-push path.
enum _Dest {
  none('None'),
  rtmp('RTMP'),
  rtmps('RTMPS'),
  rtsp('RTSP');

  const _Dest(this.label);
  final String label;

  StreamingProtocol? get protocol => switch (this) {
    _Dest.none => null,
    _Dest.rtmp => StreamingProtocol.rtmp,
    _Dest.rtmps => StreamingProtocol.rtmps,
    _Dest.rtsp => StreamingProtocol.rtsp,
  };

  /// RTMP/RTMPS carry a separate stream key; RTSP folds creds into the URL.
  bool get hasStreamKey => this == _Dest.rtmp || this == _Dest.rtmps;
}

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
  // Independent record + stream quality selections (R15). Null until the operator
  // picks — an unset selection defaults to the preferred advertised mode. Empty
  // advertised-modes list (older/disconnected firmware) disables the pickers.
  VideoMode? _recordMode;
  VideoMode? _streamMode;
  // null = Custom (use _customPeriods + _customMinutes from match init).
  SportPreset? _preset;
  int _customPeriods = 2;
  int _customPeriodSeconds = 35 * 60;
  bool _initialized = false;

  // Per-match streaming destination: protocol + inline URL/key. `none` = record
  // without streaming.
  _Dest _dest = _Dest.none;
  final TextEditingController _streamUrlCtl = TextEditingController();
  final TextEditingController _streamKeyCtl = TextEditingController();

  // Session push state (U9).
  bool _pushing = false;
  String? _pushError;
  // Stable match UUID for the current setup session. Generated on first tap
  // and reused on retry so the camera always sees the same UUID.
  String? _matchUuid;

  @override
  void dispose() {
    _streamUrlCtl.dispose();
    _streamKeyCtl.dispose();
    super.dispose();
  }

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
    // U3 health gate: starting a match leads straight into capture — blocked
    // while the device is inoperable (or health unknown while connected).
    final captureBlocked = ref.watch(captureBlockedProvider);

    // Firmware-advertised capture modes (R16). Empty when disconnected or on
    // firmware that predates supported_modes → the quality pickers render
    // disabled.
    final modes = activeId == null
        ? const <VideoMode>[]
        : ref
                  .watch(connectedDeviceInfoProvider(activeId))
                  .valueOrNull
                  ?.supportedModes ??
              const <VideoMode>[];

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
          const WfSection('Quality'),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: WfCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  // Record and stream quality are independent (R15) and offered
                  // only from firmware-advertised modes (R16). No modes (older /
                  // disconnected firmware) → shown but disabled with a hint.
                  _DropdownRow<VideoMode>(
                    label: 'Record quality',
                    value: modes.isEmpty ? null : _effectiveRecord(modes),
                    items: modes,
                    labelOf: (mode) => mode.label,
                    hint: 'Unavailable',
                    onChanged: modes.isEmpty
                        ? null
                        : (v) => setState(() => _recordMode = v),
                  ),
                  const Divider(height: 1, color: T.rule),
                  _DropdownRow<VideoMode>(
                    label: 'Stream quality',
                    value: modes.isEmpty ? null : _effectiveStream(modes),
                    items: modes,
                    labelOf: (mode) => mode.label,
                    hint: 'Unavailable',
                    onChanged: modes.isEmpty
                        ? null
                        : (v) => setState(() => _streamMode = v),
                  ),
                  if (modes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: WfNote(
                          'Connect to camera to load available modes',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const WfSection('Streaming'),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: WfCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DropdownRow<_Dest>(
                    label: 'Destination',
                    value: _dest,
                    items: _Dest.values,
                    labelOf: (d) => d.label,
                    onChanged: (v) => setState(() => _dest = v),
                  ),
                  if (_dest != _Dest.none) ...[
                    const Divider(height: 1, color: T.rule),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                      child: TextField(
                        controller: _streamUrlCtl,
                        autocorrect: false,
                        keyboardType: TextInputType.url,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 13, color: T.ink),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: '${_dest.label} URL',
                          hintText:
                              '${_dest.protocol!.urlScheme}your-server/live',
                          errorText: _streamUrlError(),
                        ),
                      ),
                    ),
                    if (_dest.hasStreamKey)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                        child: TextField(
                          controller: _streamKeyCtl,
                          autocorrect: false,
                          obscureText: true,
                          style: const TextStyle(fontSize: 13, color: T.ink),
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Stream key (optional)',
                          ),
                        ),
                      ),
                    if (_dest == _Dest.rtsp)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(14, 0, 14, 10),
                        child: WfNote(
                          'RTSP egress is not yet supported by the camera '
                          'firmware — this destination will not stream.',
                        ),
                      )
                    else
                      const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
          // U3 health surface — inoperable banner / recovering note, shared
          // with the main page + session screen (one widget, no divergence).
          const DeviceHealthNotice(margin: EdgeInsets.fromLTRB(14, 8, 14, 0)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: WfButton(
              label: _pushing ? 'Configuring camera…' : 'Start match',
              variant: WfButtonVariant.primary,
              size: WfButtonSize.lg,
              full: true,
              onPressed:
                  (_pushing || !connected || !_streamReady() || captureBlocked)
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
                    onPressed: (connected && _streamReady() && !captureBlocked)
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

  /// Firmware-advertised modes, or empty when disconnected / unsupported.
  List<VideoMode> _advertisedModes() {
    final activeId = ref.read(activeCameraIdProvider);
    if (activeId == null) return const [];
    return ref
            .read(connectedDeviceInfoProvider(activeId))
            .valueOrNull
            ?.supportedModes ??
        const [];
  }

  VideoMode? _effectiveRecord(List<VideoMode> modes) =>
      effectiveVideoMode(_recordMode, modes);
  VideoMode? _effectiveStream(List<VideoMode> modes) =>
      effectiveVideoMode(_streamMode, modes);

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

    // The chosen destination resolved to its full ingest URL, or null to record
    // without streaming (destination = None).
    final stream = _resolvedStream();
    final rtmpUrl = stream?.wireUrl;

    final opponentName = opponentDisplayName(widget.match.match.opponent);

    // Unsupervised-session timeout (R5): the persisted setting rides every
    // session config (default 30 when the operator never touched it).
    final autoStopMinutes = await ref.read(autoStopMinutesProvider.future);
    if (!mounted) return;

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
      autoStopMinutes: autoStopMinutes,
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
      // Remember the pushed config so a mid-session auto-stop change can
      // re-push it with the new timeout (core/state/auto_stop.dart).
      ref.read(lastPushedSessionConfigProvider.notifier).state = config;
      if (!mounted) return;

      // Persist the per-match streaming credential (scoped to this match only;
      // mid-match start reuses it). Clears the columns when no destination set.
      await ref
          .read(teamsDaoProvider)
          .setMatchStreamingCredential(
            matchUuid,
            rtmpUrl: stream?.storeUrl,
            streamKey: stream?.storeKey,
          );

      // Step 2: build and push overlay layout.
      final awayName = opponentDisplayName(widget.match.match.opponent);
      final layout = defaultScoreboardLayout(
        // Short name reads best in the compact scoreboard bug.
        homeName: widget.match.team.shortName,
        awayName: awayName,
        homeColorHex: widget.match.team.colorHex,
        awayColorHex: null,
      );
      await ble.pushOverlayLayout(deviceId, layout);
      if (!mounted) return;

      // Store layout + colors + the independent record/stream quality in live
      // session state so the record/stream start commands carry them (R15). Null
      // when no modes are advertised → firmware default.
      final ctl = ref.read(liveMatchProvider.notifier);
      ctl.setOverlayLayout(layout);
      ctl.setTeamColors(widget.match.team.colorHex, null);
      final modes = _advertisedModes();
      ctl.setQuality(
        record: _effectiveRecord(modes),
        stream: _effectiveStream(modes),
      );

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

  /// The parsed per-match streaming selection for the chosen destination, or
  /// null when `none` (record-only) or the URL is not yet scheme-valid.
  /// rtmp/rtmps carry a stream key; rtsp folds creds into the URL (no key).
  WireStream? _resolvedStream() {
    final protocol = _dest.protocol;
    if (protocol == null) return null;
    final url = _streamUrlCtl.text.trim();
    if (!url.startsWith(protocol.urlScheme)) return null;
    final StreamingConfig cfg = protocol == StreamingProtocol.rtsp
        ? RtspConfig(url: url)
        : RtmpConfig(url: url, streamKey: _streamKeyCtl.text.trim());
    return resolveWireStream(cfg);
  }

  /// Inline URL-field validation: an error string when the entered URL doesn't
  /// match the selected protocol's scheme. An empty URL shows no error (the
  /// Start button stays disabled via [_streamReady]).
  String? _streamUrlError() {
    final protocol = _dest.protocol;
    if (protocol == null) return null;
    final url = _streamUrlCtl.text.trim();
    if (url.isEmpty) return null;
    return url.startsWith(protocol.urlScheme)
        ? null
        : 'Must start with ${protocol.urlScheme}';
  }

  /// Whether the streaming selection is complete enough to start the match:
  /// either record-only (none) or a destination with a scheme-valid URL.
  bool _streamReady() => _dest == _Dest.none || _resolvedStream() != null;

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
    this.hint,
  });
  final String label;

  /// Null renders the [hint] placeholder — used for the disabled state.
  final V? value;
  final List<V> items;
  final String Function(V) labelOf;

  /// Null disables the dropdown (greyed, non-interactive).
  final ValueChanged<V>? onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: enabled ? T.ink : T.ink2,
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
              icon: Icon(
                Icons.expand_more,
                size: 16,
                color: enabled ? T.ink2 : T.ink3,
              ),
              hint: hint == null
                  ? null
                  : Text(
                      hint!,
                      style: const TextStyle(fontSize: 13, color: T.ink3),
                    ),
              items: [
                for (final item in items)
                  DropdownMenuItem(value: item, child: Text(labelOf(item))),
              ],
              onChanged: enabled
                  ? (v) {
                      if (v != null) onChanged!(v);
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
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
