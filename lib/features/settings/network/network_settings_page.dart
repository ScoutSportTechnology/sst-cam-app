import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ble/ble_providers.dart';
import '../../../core/ble/ble_service.dart'
    show BleNetworkConfigUnsupportedException;
import '../../../core/errors/friendly_status.dart';
import '../../../core/models/command.dart'
    show kSharedWifiProvisioningProtocolVersion;
import '../../../core/models/network_config.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/wf_button.dart';
import '../../../core/wifi/wifi_handoff.dart' show previewProbeProvider;
import '../../../core/wifi/wifi_providers.dart' show wifiServiceProvider;
import '../../camera/camera_state.dart' show activeCameraIdProvider;

/// Settings → Network. Two distinct affordances:
///
///  * **Connect to your Wi-Fi (provisioning, U6).** A one-tap action that
///    provisions ONLY the phone's current SSID (INV1 — never a scan/pick-any
///    list) so the camera migrates from its WiFi-Direct GO (S1) to joining the
///    phone's network as STA (S2), which enables cloud streaming and moves live
///    preview onto the LAN. On submit the app shows a "Switching to your
///    network…" transition, probes the camera's authenticated LAN preview, then
///    confirms/denies the migration by its migration-id. Gated on the camera
///    reporting protocol_version >= 4.
///  * **Advanced network settings (legacy uplink editor).** The static-IP/DHCP
///    Ethernet + WiFi-STA editor: reads the camera's uplink config over BLE on
///    open, pushes changes on Apply, shows live per-interface status. (R3–R7,
///    R10.)
///
/// Connectivity/streaming/network failures are rendered as friendly, secret
/// redacting copy via [FriendlyStatus] (U7 + U8).
class NetworkSettingsPage extends ConsumerStatefulWidget {
  const NetworkSettingsPage({super.key});

  @override
  ConsumerState<NetworkSettingsPage> createState() =>
      _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends ConsumerState<NetworkSettingsPage> {
  // Ethernet
  bool _ethEnabled = false;
  bool _ethDhcp = true;
  final _ethAddress = TextEditingController();
  final _ethGateway = TextEditingController();
  final _ethDns = TextEditingController();

  // WiFi STA (legacy advanced editor)
  bool _wifiEnabled = false;
  bool _wifiDhcp = true;
  final _wifiSsid = TextEditingController();
  final _wifiPassword = TextEditingController();
  final _wifiAddress = TextEditingController();
  final _wifiGateway = TextEditingController();
  final _wifiDns = TextEditingController();

  // Provisioning (U6): the phone's current SSID + a one-shot password field.
  final _provisionPassword = TextEditingController();
  String? _phoneSsid;
  // The phone's current WiFi frequency (MHz); 0 = unknown. Used to validate the
  // band BEFORE provisioning — the camera can only join 5 GHz (2.4 GHz contends
  // with its Bluetooth radio).
  int _phoneWifiFreqMhz = 0;
  bool _provisioning = false;
  bool _provisionConnected = false;
  // The friendly outcome of the last provisioning attempt (U7), or null.
  FriendlyStatus? _provisionStatus;

  // The toggle DISPLAY (_ethEnabled/_wifiEnabled) is live-derived (configured
  // intent OR real link state). But persisting must not silently flip stored
  // intent: track the ORIGINAL configured value and a per-interface dirty flag
  // so _collect() only writes the live-derived ON state when the user actually
  // toggled it; otherwise it preserves the camera's stored intent.
  bool _ethConfigEnabled = false;
  bool _wifiConfigEnabled = false;
  bool _ethToggleDirty = false;
  bool _wifiToggleDirty = false;

  // Load-generation guard: a slow BLE _load() that resolves AFTER the user has
  // edited fields / started a save must not clobber their input. Each _load()
  // captures a generation before awaiting; if a newer load started or a save
  // began (which bumps _loadGen), the stale load aborts before _apply().
  int _loadGen = 0;

  bool _loading = true;
  bool _saving = false;
  // A static, secret-free blocking message (no camera / unsupported firmware).
  String? _error;
  // A friendly, redacting failure for a save/load fault (U8).
  FriendlyStatus? _friendly;
  NetworkConfigResult? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in [
      _ethAddress,
      _ethGateway,
      _ethDns,
      _wifiSsid,
      _wifiPassword,
      _wifiAddress,
      _wifiGateway,
      _wifiDns,
      _provisionPassword,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _deviceId => ref.read(activeCameraIdProvider);

  Future<void> _load() async {
    final deviceId = _deviceId;
    if (deviceId == null) {
      setState(() {
        _loading = false;
        _error = 'Connect to a camera first.';
      });
      return;
    }
    final gen = ++_loadGen;
    // Read the phone's own SSID in parallel — it only feeds the provisioning
    // card and must never block or fail the config load.
    unawaited(_loadPhoneSsid(gen));
    try {
      final result = await ref
          .read(bleServiceProvider)
          .getNetworkConfig(deviceId);
      // Abort if unmounted, superseded by a newer load, or overtaken by a save
      // (which bumps _loadGen). Otherwise this stale load would clobber the
      // user's in-progress edits.
      if (!mounted || gen != _loadGen || _saving) return;
      _apply(result);
    } on BleNetworkConfigUnsupportedException {
      if (!mounted || gen != _loadGen || _saving) return;
      setState(() {
        _loading = false;
        _error =
            'This camera\'s firmware is too old for network config — update '
            'the camera firmware to configure its uplink.';
      });
    } catch (e) {
      if (!mounted || gen != _loadGen || _saving) return;
      // U8: humanize + redact the read failure rather than surfacing raw `$e`.
      setState(() {
        _loading = false;
        _friendly = FriendlyStatus.forOutcome(
          ConnectivityOutcome.configReadFailure,
          rawDetail: e.toString(),
        );
      });
    }
  }

  Future<void> _loadPhoneSsid(int gen) async {
    try {
      final wifi = ref.read(wifiServiceProvider);
      final ssid = await wifi.currentSsid();
      final freq = await wifi.currentWifiFrequencyMhz();
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _phoneSsid = ssid;
        _phoneWifiFreqMhz = freq;
      });
    } catch (_) {
      // SSID unavailable → treat as phone offline (provision disabled).
      if (!mounted || gen != _loadGen) return;
      setState(() => _phoneSsid = null);
    }
  }

  // The phone is on a 2.4 GHz network the camera cannot join (5 GHz required).
  // Unknown frequency (0) is NOT treated as 2.4 GHz — let the attempt proceed.
  bool get _phoneOn24Ghz =>
      _phoneWifiFreqMhz >= 2400 && _phoneWifiFreqMhz < 2500;

  void _apply(NetworkConfigResult result, {bool clearSaving = false}) {
    final config = result.config;
    setState(() {
      // The toggle reflects whether the interface is actually a live uplink — the
      // configured intent OR the real link state (the camera's NM-managed
      // ethernet can be up even when the firmware config has it disabled).
      _ethEnabled = config.ethernet.enabled || result.ethernetUp;
      // ...but remember the camera's STORED intent separately, and clear the
      // dirty flag: a fresh load/save means the displayed live state has not
      // been touched by the user yet, so _collect() must preserve this intent.
      _ethConfigEnabled = config.ethernet.enabled;
      _ethToggleDirty = false;
      _ethDhcp = config.ethernet.ip.dhcp;
      _ethAddress.text = config.ethernet.ip.address;
      _ethGateway.text = config.ethernet.ip.gateway;
      _ethDns.text = config.ethernet.ip.dns;
      _wifiEnabled = config.wifi.enabled || result.wifiUp;
      _wifiConfigEnabled = config.wifi.enabled;
      _wifiToggleDirty = false;
      _wifiDhcp = config.wifi.ip.dhcp;
      _wifiSsid.text = config.wifi.ssid;
      _wifiPassword.text = config.wifi.password;
      _wifiAddress.text = config.wifi.ip.address;
      _wifiGateway.text = config.wifi.ip.gateway;
      _wifiDns.text = config.wifi.ip.dns;
      _status = result;
      _loading = false;
      _error = null;
      _friendly = null;
      // Fold the save-complete flag into this same rebuild to avoid a second
      // setState (button flicker between field update and 'Saving…' clearing).
      if (clearSaving) _saving = false;
    });
  }

  NetworkConfig _collect() => NetworkConfig(
    ethernet: EthernetUplink(
      // Only persist the live-derived ON state when the user actually toggled
      // it; otherwise preserve the camera's stored intent so merely opening +
      // saving the page does not flip a live-but-unconfigured interface on.
      enabled: _ethToggleDirty ? _ethEnabled : _ethConfigEnabled,
      ip: UplinkIp(
        dhcp: _ethDhcp,
        address: _ethAddress.text.trim(),
        gateway: _ethGateway.text.trim(),
        dns: _ethDns.text.trim(),
      ),
    ),
    wifi: WifiUplink(
      enabled: _wifiToggleDirty ? _wifiEnabled : _wifiConfigEnabled,
      ssid: _wifiSsid.text.trim(),
      password: _wifiPassword.text,
      ip: UplinkIp(
        dhcp: _wifiDhcp,
        address: _wifiAddress.text.trim(),
        gateway: _wifiGateway.text.trim(),
        dns: _wifiDns.text.trim(),
      ),
    ),
  );

  Future<void> _save() async {
    // Synchronous re-entrancy guard: the onPressed disable is one frame late
    // (setState schedules), so a fast double-tap could otherwise fire _save()
    // twice. This must be the FIRST line, before any setState.
    if (_saving) return;
    final deviceId = _deviceId;
    if (deviceId == null) return;
    // A save supersedes any in-flight _load(): bumping the generation makes the
    // load abort before it can clobber the values we are about to push.
    _loadGen++;
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(bleServiceProvider)
          .setNetworkConfig(deviceId, _collect());
      if (!mounted) return;
      // Fold _saving=false into the same setState as _apply (single rebuild).
      _apply(result, clearSaving: true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Network config applied')));
    } on BleNetworkConfigUnsupportedException {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'This camera\'s firmware is too old for network config — update '
            'the camera firmware to configure its uplink.';
      });
    } catch (e) {
      if (!mounted) return;
      // U8: humanize + redact the write failure rather than surfacing raw `$e`.
      setState(() {
        _saving = false;
        _friendly = FriendlyStatus.forOutcome(
          ConnectivityOutcome.configWriteFailure,
          rawDetail: e.toString(),
        );
      });
    }
  }

  /// U6 — provision the phone's current network: enable the WiFi STA uplink with
  /// that SSID + the entered password, then run the migration handshake (probe
  /// the authenticated LAN preview → confirm/deny by migration-id).
  Future<void> _provision() async {
    if (_provisioning) return;
    final deviceId = _deviceId;
    final ssid = _phoneSsid;
    if (deviceId == null || ssid == null) return;
    FocusScope.of(context).unfocus();
    // Validate the band FIRST: the camera can only join a 5 GHz Wi-Fi (its single
    // radio holds Bluetooth on 2.4 GHz), so a 2.4 GHz network never associates.
    // Fail fast with the clear "switch to 5 GHz" message rather than attempting a
    // join that would take ~15s and revert.
    if (_phoneOn24Ghz) {
      setState(() {
        _provisionConnected = false;
        _provisionStatus = FriendlyStatus.forOutcome(
          ConnectivityOutcome.needs5GHz,
        );
      });
      return;
    }
    // Supersede any in-flight load so it can't clobber the transition state.
    _loadGen++;
    setState(() {
      _provisioning = true;
      _provisionConnected = false;
      _provisionStatus = null;
      _friendly = null;
    });

    try {
      // Secure the link FIRST: bond so the credential write crosses an encrypted
      // BLE link (INV6/AE7). If bonding fails the firmware gate would reject the
      // credentials anyway, so surface a friendly error and never send them.
      await ref.read(bleServiceProvider).ensureBonded(deviceId);
      if (!mounted) return;

      // Provision ONLY the phone's current SSID (INV1), over DHCP. Preserve the
      // Ethernet editor's stored intent; the STA join begins the migration.
      final config = _collect().copyWith(
        wifi: WifiUplink(
          enabled: true,
          ssid: ssid,
          password: _provisionPassword.text,
        ),
      );
      final result = await ref
          .read(bleServiceProvider)
          .setNetworkConfig(deviceId, config);
      if (!mounted) return;

      if (!result.isMigrating) {
        // Firmware accepted the config but did not begin a migration (e.g. it
        // couldn't join the network) — friendly "couldn't join" (U7).
        setState(() {
          _provisioning = false;
          _provisionStatus = FriendlyStatus.forOutcome(
            ConnectivityOutcome.couldntJoin,
          );
        });
        return;
      }

      // Probe the AUTHENTICATED LAN preview (OQ2). The probe timeout is strictly
      // shorter than the firmware self-revert window, so our confirm/deny always
      // beats the firmware backstop.
      final reachable = await ref
          .read(previewProbeProvider)
          .probe(result.previewEndpoint, result.previewCredential);

      // Confirm (reachable) or deny (isolation) by migration-id. A confirm fault
      // is treated as a failed migration (stay in S1).
      ConfirmPreviewReachableResult confirm;
      try {
        confirm = await ref
            .read(bleServiceProvider)
            .confirmPreviewReachable(
              deviceId,
              migrationId: result.migrationId,
              reachable: reachable,
            );
      } catch (_) {
        confirm = ConfirmPreviewReachableResult(
          migrationId: result.migrationId,
          inSharedWifi: false,
        );
      }
      if (!mounted) return;

      final success = reachable && confirm.inSharedWifi;
      setState(() {
        _provisioning = false;
        _provisionConnected = success;
        _provisionStatus = success
            ? null
            // Not reachable (client/AP isolation) → friendly isolation copy (U7).
            : FriendlyStatus.forOutcome(ConnectivityOutcome.isolated);
        // Mirror the outcome into the uplink-config state the Advanced "Apply"
        // preserves (SetNetworkConfig is a full replace) — so applying an ethernet
        // change never clobbers or resurrects the WiFi uplink. On success the STA
        // is up on the phone's network (DHCP); on failure the firmware reverted to
        // S1, so WiFi is off.
        _wifiConfigEnabled = success;
        _wifiEnabled = success;
        _wifiToggleDirty = false;
        if (success) {
          _wifiDhcp = true;
          _wifiSsid.text = _phoneSsid ?? _wifiSsid.text;
          _wifiPassword.text = _provisionPassword.text;
        }
      });
    } on BleNetworkConfigUnsupportedException {
      if (!mounted) return;
      setState(() {
        _provisioning = false;
        _provisionStatus = FriendlyStatus.forOutcome(
          ConnectivityOutcome.couldntJoin,
        );
      });
    } catch (e) {
      if (!mounted) return;
      // Classify (e.g. wrong password vs a generic join failure) + redact (U8).
      setState(() {
        _provisioning = false;
        _provisionStatus = FriendlyStatus.fromError(
          e,
          fallback: ConnectivityOutcome.couldntJoin,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // WATCH the active camera so a disconnect rebuilds this page (a stale read
    // would keep showing the last camera's uplink after it's gone).
    final deviceId = ref.watch(activeCameraIdProvider);
    // No camera connected → the whole page is meaningless (there's nothing to
    // provision or configure). Show a single hint, not a stale Ethernet card.
    if (deviceId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Network')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Connect to a camera to configure its network.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final info = ref.watch(connectedDeviceInfoProvider(deviceId)).valueOrNull;
    final supportsProvisioning =
        (info?.protocolVersion ?? 0) >= kSharedWifiProvisioningProtocolVersion;

    return Scaffold(
      appBar: AppBar(title: const Text('Network')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_friendly != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _FriendlyBanner(status: _friendly!),
                  ),
                if (supportsProvisioning) ...[
                  _ProvisioningCard(
                    phoneSsid: _phoneSsid,
                    passwordController: _provisionPassword,
                    provisioning: _provisioning,
                    connected: _provisionConnected,
                    status: _provisionStatus,
                    onConnect: _provision,
                  ),
                  const SizedBox(height: 24),
                ],
                const _AdvancedHeader(),
                const SizedBox(height: 8),
                Text(
                  'The camera streams to the cloud over this uplink — separate '
                  'from the WiFi-Direct link used for control + live preview.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                _ethernetSection(context),
                const SizedBox(height: 24),
                WfButton(
                  label: _saving ? 'Saving…' : 'Apply',
                  variant: WfButtonVariant.primary,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
    );
  }

  Widget _ethernetSection(BuildContext context) {
    return _UplinkSection(
      title: 'Ethernet',
      enabled: _ethEnabled,
      onEnabledChanged: (v) => setState(() {
        _ethEnabled = v;
        _ethToggleDirty = true;
      }),
      statusUp: _status?.ethernetUp ?? false,
      // Green dot = up; show only the address when up, nothing otherwise.
      statusText: (_status?.ethernetUp ?? false)
          ? (_status?.ethernetAddress ?? '')
          : '',
      children: [
        _DhcpToggle(
          dhcp: _ethDhcp,
          onChanged: (v) => setState(() => _ethDhcp = v),
        ),
        if (!_ethDhcp) ...[
          _field('IP address (CIDR, e.g. 10.0.0.5/24)', _ethAddress),
          _field('Gateway', _ethGateway),
          _field('DNS', _ethDns),
        ],
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// U6 — one-tap provisioning of the phone's CURRENT network only (INV1). Shows
/// that SSID (never a scan/pick list), a password field, a "Switching…"
/// transition, and the friendly outcome (U7).
class _ProvisioningCard extends StatefulWidget {
  const _ProvisioningCard({
    required this.phoneSsid,
    required this.passwordController,
    required this.provisioning,
    required this.connected,
    required this.status,
    required this.onConnect,
  });

  final String? phoneSsid;
  final TextEditingController passwordController;
  final bool provisioning;
  final bool connected;
  final FriendlyStatus? status;
  final Future<void> Function() onConnect;

  @override
  State<_ProvisioningCard> createState() => _ProvisioningCardState();
}

class _ProvisioningCardState extends State<_ProvisioningCard> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final phoneSsid = widget.phoneSsid;
    final passwordController = widget.passwordController;
    final provisioning = widget.provisioning;
    final connected = widget.connected;
    final status = widget.status;
    final onConnect = widget.onConnect;
    final theme = Theme.of(context);
    final offline = phoneSsid == null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connect the camera to your Wi-Fi',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Puts the camera on the same Wi-Fi as your phone so live preview '
              'moves onto your network and cloud streaming turns on. The camera '
              'only ever joins the network your phone is on.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (offline)
              // Phone not on WiFi → provision disabled + streaming greyed.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Join a Wi-Fi network on your phone to connect the camera to '
                  'it. Until then, streaming stays off — recording and the '
                  'direct live preview still work.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else ...[
              // The phone's CURRENT SSID only (read-only, INV1).
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Your Wi-Fi network',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wifi),
                ),
                child: Text(phoneSsid),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: _obscure,
                enabled: !provisioning,
                decoration: InputDecoration(
                  labelText: 'Wi-Fi password',
                  helperText: 'Enter it once — your phone keeps it hidden.',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                    ),
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (provisioning)
                Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Switching to your network…',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                )
              else
                WfButton(
                  label: connected ? 'Connected' : 'Connect',
                  variant: WfButtonVariant.primary,
                  onPressed: onConnect,
                ),
              if (connected && status == null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.check_circle, size: 16, color: T.ok),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Connected to your Wi-Fi — live preview and streaming '
                        'are on.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
              if (status != null) ...[
                const SizedBox(height: 12),
                _FriendlyBanner(status: status),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Renders a [FriendlyStatus]: the human message + action hint, with the raw
/// (already-redacted) detail behind a collapsed "Details" affordance (U8).
class _FriendlyBanner extends StatelessWidget {
  const _FriendlyBanner({required this.status});

  final FriendlyStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status.message, style: theme.textTheme.bodyMedium),
          if (status.actionHint != null) ...[
            const SizedBox(height: 4),
            Text(
              status.actionHint!,
              style: theme.textTheme.bodySmall?.copyWith(color: T.ink2),
            ),
          ],
          if (status.debugDetail != null) ...[
            const SizedBox(height: 4),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text('Details', style: theme.textTheme.bodySmall),
                children: [
                  // Already redacted by FriendlyStatus — no SSID/passphrase.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      status.debugDetail!,
                      style: const TextStyle(
                        fontFamily: T.mono,
                        fontSize: 11,
                        color: T.ink2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AdvancedHeader extends StatelessWidget {
  const _AdvancedHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.tune, size: 16, color: T.ink2),
        const SizedBox(width: 8),
        Text(
          'Advanced network settings',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
    );
  }
}

class _UplinkSection extends StatelessWidget {
  const _UplinkSection({
    required this.title,
    required this.enabled,
    required this.onEnabledChanged,
    required this.statusUp,
    required this.statusText,
    required this.children,
  });

  final String title;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final bool statusUp;
  final String statusText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 12,
                  color: statusUp ? T.ok : scheme.outline,
                ),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Switch(value: enabled, onChanged: onEnabledChanged),
              ],
            ),
            if (statusText.isNotEmpty)
              Text(statusText, style: Theme.of(context).textTheme.bodySmall),
            if (enabled) ...children,
          ],
        ),
      ),
    );
  }
}

class _DhcpToggle extends StatelessWidget {
  const _DhcpToggle({required this.dhcp, required this.onChanged});

  final bool dhcp;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Automatic (DHCP)'),
      subtitle: Text(dhcp ? 'IP assigned automatically' : 'Static IP'),
      value: dhcp,
      onChanged: onChanged,
    );
  }
}
