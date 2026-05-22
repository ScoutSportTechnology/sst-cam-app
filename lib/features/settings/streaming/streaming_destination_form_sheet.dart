// U9 — Adaptive bottom-sheet form for creating / editing a streaming
// destination.
//
// Shape:
//
//   * Provider picker — 5 chips (YouTube / TikTok / Facebook / Instagram /
//     Custom).
//   * Protocol picker — only when provider == custom; 3 chips
//     (RTMP / RTMPS / RTSP). For known providers protocol is fixed to RTMP
//     and the picker is omitted from the widget tree.
//   * Name — always visible. When the user hasn't typed a custom name, the
//     field auto-fills with the new provider's display label on switch.
//   * URL — always visible. Helper note shows the expected scheme prefix.
//   * Stream key — visible when protocol ∈ {rtmp, rtmps}. Sensitive field —
//     `obscureText` with a visibility toggle, plus
//     `enableSuggestions: false` and `autocorrect: false` so soft-keyboard
//     autocomplete cannot leak input.
//   * Username (optional) + Password (optional) — visible when protocol ==
//     rtsp. Password is also sensitive (same treatment as stream key);
//     username is treated as sensitive against autocomplete (`enable
//     Suggestions` / `autocorrect` off) but is not obscured.
//
// Validation on submit:
//   * Name required.
//   * URL must start with the chosen protocol's `urlScheme` (`rtmp://`,
//     `rtmps://`, `rtsp://`).
//   * For RTMP/RTMPS, stream key is required.
//   * RTSP credentials are optional.
//
// Keys (load-bearing for tests in
// `test/pages/streaming_destination_form_sheet_test.dart` —
// `tester.widget<TextField>(find.byKey(...))` reads `obscureText` /
// `enableSuggestions` / `autocorrect` on the field).

import 'package:flutter/material.dart';

import '../../../core/models/streaming.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/wf_button.dart';
import '../../../core/widgets/wf_card.dart';

/// Show the create / edit streaming-destination form. Returns the entered
/// draft, or null if the user cancelled. Pass `existing` to prefill for
/// edit; the sheet keeps `existing.id` on the returned draft so the
/// controller routes to update.
Future<StreamingDestinationDraft?> showStreamingDestinationFormSheet(
  BuildContext context, {
  StreamingDestination? existing,
}) {
  return showModalBottomSheet<StreamingDestinationDraft>(
    context: context,
    backgroundColor: T.bg,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _DestinationForm(existing: existing),
    ),
  );
}

class _DestinationForm extends StatefulWidget {
  const _DestinationForm({this.existing});
  final StreamingDestination? existing;

  @override
  State<_DestinationForm> createState() => _DestinationFormState();
}

class _DestinationFormState extends State<_DestinationForm> {
  late StreamingProvider _provider;
  late StreamingProtocol _protocol;
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _streamKey;
  late final TextEditingController _username;
  late final TextEditingController _password;

  bool _streamKeyVisible = false;
  bool _passwordVisible = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _provider = e?.provider ?? StreamingProvider.youtube;
    _protocol = e?.protocol ?? StreamingProtocol.rtmp;
    _name = TextEditingController(text: e?.name ?? _defaultName(_provider));
    _url = TextEditingController(
      text: e == null ? '' : _urlFromConfig(e.config),
    );
    _streamKey = TextEditingController(
      text: e != null && e.config is RtmpConfig
          ? (e.config as RtmpConfig).streamKey
          : '',
    );
    _username = TextEditingController(
      text: e != null && e.config is RtspConfig
          ? ((e.config as RtspConfig).username ?? '')
          : '',
    );
    _password = TextEditingController(
      text: e != null && e.config is RtspConfig
          ? ((e.config as RtspConfig).password ?? '')
          : '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _streamKey.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _onProviderChanged(StreamingProvider next) {
    setState(() {
      _provider = next;
      // Known providers are RTMP-only; force protocol when leaving custom.
      if (next != StreamingProvider.custom) {
        _protocol = StreamingProtocol.rtmp;
      }
      // Default-name behavior: if name is empty or matches any provider's
      // default label, swap to the new provider's default.
      final defaults = StreamingProvider.values.map(_defaultName).toSet();
      if (_name.text.trim().isEmpty || defaults.contains(_name.text.trim())) {
        _name.text = _defaultName(next);
      }
    });
  }

  void _onProtocolChanged(StreamingProtocol next) {
    setState(() {
      _protocol = next;
    });
  }

  void _submit() {
    final name = _name.text.trim();
    final url = _url.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Destination name is required');
      return;
    }
    final scheme = _protocol.urlScheme;
    if (!url.startsWith(scheme)) {
      setState(() => _error = 'URL must start with $scheme');
      return;
    }

    StreamingConfig config;
    switch (_protocol) {
      case StreamingProtocol.rtmp:
      case StreamingProtocol.rtmps:
        final key = _streamKey.text.trim();
        if (key.isEmpty) {
          setState(() => _error = 'Stream key is required');
          return;
        }
        config = RtmpConfig(url: url, streamKey: key);
      case StreamingProtocol.rtsp:
        final user = _username.text.trim();
        final pass = _password.text.trim();
        config = RtspConfig(
          url: url,
          username: user.isEmpty ? null : user,
          password: pass.isEmpty ? null : pass,
        );
    }

    Navigator.of(context).pop(
      StreamingDestinationDraft(
        id: widget.existing?.id ?? '',
        name: name,
        provider: _provider,
        protocol: _protocol,
        config: config,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final isCustom = _provider == StreamingProvider.custom;
    final showStreamKey =
        _protocol == StreamingProtocol.rtmp ||
        _protocol == StreamingProtocol.rtmps;
    final showRtspCreds = _protocol == StreamingProtocol.rtsp;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: T.fillMid,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isEdit ? 'Edit destination' : 'Add destination',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: T.ink,
              ),
            ),
            const SizedBox(height: 14),
            // Provider picker.
            const WfNote('PROVIDER'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: StreamingProvider.values
                  .map(
                    (p) => _PickerChip(
                      label: p.displayLabel,
                      selected: _provider == p,
                      onTap: () => _onProviderChanged(p),
                    ),
                  )
                  .toList(),
            ),
            // Protocol picker — only when provider == custom.
            if (isCustom) ...[
              const SizedBox(height: 14),
              const WfNote('PROTOCOL'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: StreamingProtocol.values
                    .map(
                      (p) => _PickerChip(
                        label: p.displayLabel,
                        selected: _protocol == p,
                        onTap: () => _onProtocolChanged(p),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 14),
            // Name — always.
            _LabeledField(
              key: const Key('streaming-name-field-wrapper'),
              fieldKey: const Key('streaming-name-field'),
              label: 'Name',
              controller: _name,
              hint: 'My YouTube channel',
            ),
            const SizedBox(height: 14),
            // URL — always.
            _LabeledField(
              key: const Key('streaming-url-field-wrapper'),
              fieldKey: const Key('streaming-url-field'),
              label: 'URL',
              controller: _url,
              hint: '${_protocol.urlScheme}server.example.com/path',
              keyboardType: TextInputType.url,
              helper: 'Must start with ${_protocol.urlScheme}',
            ),
            // Stream key — visible when protocol ∈ {rtmp, rtmps}. Sensitive.
            if (showStreamKey) ...[
              const SizedBox(height: 14),
              _LabeledField(
                key: const Key('streaming-key-field-wrapper'),
                fieldKey: const Key('streaming-key-field'),
                label: 'Stream key',
                controller: _streamKey,
                hint: 'paste your stream key',
                obscureText: !_streamKeyVisible,
                enableSuggestions: false,
                autocorrect: false,
                trailing: IconButton(
                  icon: Icon(
                    _streamKeyVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                  ),
                  color: T.ink2,
                  tooltip: _streamKeyVisible
                      ? 'Hide stream key'
                      : 'Show stream key',
                  onPressed: () =>
                      setState(() => _streamKeyVisible = !_streamKeyVisible),
                ),
              ),
            ],
            // RTSP — Username + Password (both optional, both sensitive
            // against autocomplete; password is obscured).
            if (showRtspCreds) ...[
              const SizedBox(height: 14),
              _LabeledField(
                key: const Key('streaming-username-field-wrapper'),
                fieldKey: const Key('streaming-username-field'),
                label: 'Username (optional)',
                controller: _username,
                hint: 'optional',
                enableSuggestions: false,
                autocorrect: false,
              ),
              const SizedBox(height: 14),
              _LabeledField(
                key: const Key('streaming-password-field-wrapper'),
                fieldKey: const Key('streaming-password-field'),
                label: 'Password (optional)',
                controller: _password,
                hint: 'optional',
                obscureText: !_passwordVisible,
                enableSuggestions: false,
                autocorrect: false,
                trailing: IconButton(
                  icon: Icon(
                    _passwordVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                  ),
                  color: T.ink2,
                  tooltip: _passwordVisible ? 'Hide password' : 'Show password',
                  onPressed: () =>
                      setState(() => _passwordVisible = !_passwordVisible),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: T.danger, fontSize: 12),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: WfButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: WfButton(
                    label: isEdit ? 'Save' : 'Add destination',
                    variant: WfButtonVariant.primary,
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerChip extends StatelessWidget {
  const _PickerChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: T.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? T.accent : T.fillSoft,
          border: Border.all(color: selected ? T.accent : T.hair),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? T.accentInk : T.ink2,
          ),
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.keyboardType,
    this.obscureText = false,
    this.enableSuggestions = true,
    this.autocorrect = true,
    this.trailing,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enableSuggestions;
  final bool autocorrect;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WfNote(label.toUpperCase()),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: T.fillSoft,
            border: Border.all(color: T.hair),
          ),
          padding: const EdgeInsets.only(left: 12, right: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: fieldKey,
                  controller: controller,
                  keyboardType: keyboardType,
                  obscureText: obscureText,
                  enableSuggestions: enableSuggestions,
                  autocorrect: autocorrect,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(color: T.ink3, fontSize: 13),
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  style: const TextStyle(color: T.ink, fontSize: 13),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        if (helper != null) ...[const SizedBox(height: 4), WfNote(helper!)],
      ],
    );
  }
}

String _defaultName(StreamingProvider p) =>
    p == StreamingProvider.custom ? '' : p.displayLabel;

String _urlFromConfig(StreamingConfig c) {
  return switch (c) {
    RtmpConfig(:final url) => url,
    RtspConfig(:final url) => url,
  };
}
