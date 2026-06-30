// U4 — real version display.
//
// Versions come from three sources, none of them hardcoded literals:
//   - App: a git-derived `--dart-define=APP_VERSION` (set by `just` / CI from
//     `git describe`), falling back to package metadata (`package_info_plus`)
//     for a bare `flutter run`. Channel is `--dart-define=APP_CHANNEL`
//     (alpha/beta/stable per the branch ladder), defaulting to "dev" locally.
//   - Proto: the proto submodule tag via `--dart-define=PROTO_VERSION` (repo
//     SemVer) shown alongside the wire `protocol_version` the device reports.
//   - Firmware: the device-reported `firmwareVersion` (see _CameraCard).
//
// `version_info.dart` is a plain helper — no injectable wrapper. The pure
// assembly is unit-tested; the provider just feeds it platform values.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

const String _appVersionDefine = String.fromEnvironment('APP_VERSION');
const String _appChannelDefine = String.fromEnvironment('APP_CHANNEL');

/// Proto repo SemVer tag the app was built against (the submodule's
/// `git describe`), injected at build time. "dev" for an un-pinned local build.
const String protoRepoVersion = String.fromEnvironment(
  'PROTO_VERSION',
  defaultValue: 'dev',
);

/// Assembles the app version string for display. Prefers the git-derived
/// define; falls back to package metadata for bare local builds. Always
/// annotates the channel so a local build reads e.g. `0.1.0+1 (dev)` rather
/// than masquerading as a released version.
String assembleAppVersion({
  required String defineVersion,
  required String defineChannel,
  required String packageVersion,
  required String packageBuild,
}) {
  final base = defineVersion.isNotEmpty
      ? defineVersion
      : (packageBuild.isEmpty
            ? packageVersion
            : '$packageVersion+$packageBuild');
  final channel = defineChannel.isEmpty ? 'dev' : defineChannel;
  return '$base ($channel)';
}

/// The proto version display: repo SemVer tag plus, when a device is connected,
/// the wire `protocol_version` integer it reports (two distinct axes).
String protoVersionDisplay({int? wireProtocolVersion}) =>
    wireProtocolVersion == null
    ? 'proto $protoRepoVersion'
    : 'proto $protoRepoVersion · wire v$wireProtocolVersion';

/// App version string, resolved from defines + package metadata.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return assembleAppVersion(
    defineVersion: _appVersionDefine,
    defineChannel: _appChannelDefine,
    packageVersion: info.version,
    packageBuild: info.buildNumber,
  );
});
