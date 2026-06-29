import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ble/ble_providers.dart';
import '../../../core/models/network_config.dart';
import '../../../core/widgets/wf_button.dart';
import '../../camera/camera_state.dart' show activeCameraIdProvider;

/// Settings → Network: configure the camera's internet **uplink** (the
/// cloud-streaming path), separate from the WiFi-Direct link that carries
/// control + live preview. Ethernet and a (gated) WiFi STA, each enable/disable
/// with DHCP or static IP. Reads the current config from the camera over BLE on
/// open, pushes changes on Save, and shows the camera's live per-interface
/// status. (R3–R7, R10.)
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

  // WiFi STA
  bool _wifiEnabled = false;
  bool _wifiDhcp = true;
  final _wifiSsid = TextEditingController();
  final _wifiPassword = TextEditingController();
  final _wifiAddress = TextEditingController();
  final _wifiGateway = TextEditingController();
  final _wifiDns = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
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
    try {
      final result = await ref
          .read(bleServiceProvider)
          .getNetworkConfig(deviceId);
      if (!mounted) return;
      _apply(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not read network config: $e';
      });
    }
  }

  void _apply(NetworkConfigResult result) {
    final config = result.config;
    setState(() {
      // The toggle reflects whether the interface is actually a live uplink — the
      // configured intent OR the real link state (the camera's NM-managed
      // ethernet can be up even when the firmware config has it disabled).
      _ethEnabled = config.ethernet.enabled || result.ethernetUp;
      _ethDhcp = config.ethernet.ip.dhcp;
      _ethAddress.text = config.ethernet.ip.address;
      _ethGateway.text = config.ethernet.ip.gateway;
      _ethDns.text = config.ethernet.ip.dns;
      _wifiEnabled = config.wifi.enabled || result.wifiUp;
      _wifiDhcp = config.wifi.ip.dhcp;
      _wifiSsid.text = config.wifi.ssid;
      _wifiPassword.text = config.wifi.password;
      _wifiAddress.text = config.wifi.ip.address;
      _wifiGateway.text = config.wifi.ip.gateway;
      _wifiDns.text = config.wifi.ip.dns;
      _status = result;
      _loading = false;
      _error = null;
    });
  }

  NetworkConfig _collect() => NetworkConfig(
    ethernet: EthernetUplink(
      enabled: _ethEnabled,
      ip: UplinkIp(
        dhcp: _ethDhcp,
        address: _ethAddress.text.trim(),
        gateway: _ethGateway.text.trim(),
        dns: _ethDns.text.trim(),
      ),
    ),
    wifi: WifiUplink(
      enabled: _wifiEnabled,
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
    final deviceId = _deviceId;
    if (deviceId == null) return;
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(bleServiceProvider)
          .setNetworkConfig(deviceId, _collect());
      if (!mounted) return;
      _apply(result);
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Network config applied')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Save failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                Text(
                  'The camera streams to the cloud over this uplink — separate '
                  'from the WiFi-Direct link used for control + live preview.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                _ethernetSection(context),
                const SizedBox(height: 24),
                _wifiSection(context),
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
      onEnabledChanged: (v) => setState(() => _ethEnabled = v),
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

  Widget _wifiSection(BuildContext context) {
    return _UplinkSection(
      title: 'WiFi',
      enabled: _wifiEnabled,
      onEnabledChanged: (v) => setState(() => _wifiEnabled = v),
      statusUp: _status?.wifiUp ?? false,
      // Only show the address when the wifi uplink is actually up; no verbose
      // status text (the gated "unavailable" message was too long).
      statusText: (_status?.wifiUp ?? false) ? (_status?.wifiStatus ?? '') : '',
      children: [
        _field('SSID', _wifiSsid),
        _field('Password', _wifiPassword, obscure: true),
        _DhcpToggle(
          dhcp: _wifiDhcp,
          onChanged: (v) => setState(() => _wifiDhcp = v),
        ),
        if (!_wifiDhcp) ...[
          _field('IP address (CIDR)', _wifiAddress),
          _field('Gateway', _wifiGateway),
          _field('DNS', _wifiDns),
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
                  color: statusUp ? Colors.green : scheme.outline,
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
