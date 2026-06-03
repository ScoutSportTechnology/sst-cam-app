import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/dev_config.dart';

class DeveloperSettingsState {
  const DeveloperSettingsState({
    required this.activeConfig,
    required this.stagedConfig,
  });

  final DevConfig activeConfig;
  final DevConfig stagedConfig;

  bool get hasPendingChanges => stagedConfig != activeConfig;

  DeveloperSettingsState _withStaged(DevConfig next) =>
      DeveloperSettingsState(activeConfig: activeConfig, stagedConfig: next);
}

class DeveloperSettingsNotifier
    extends AutoDisposeNotifier<DeveloperSettingsState> {
  var _disposed = false;

  @override
  DeveloperSettingsState build() {
    ref.onDispose(() => _disposed = true);
    final active = ref.watch(devConfigProvider);
    return DeveloperSettingsState(activeConfig: active, stagedConfig: active);
  }

  Future<void> setSeedData(bool enabled) async {
    final next = state.stagedConfig.copyWith(seedData: enabled);
    await next.save();
    if (_disposed) return;
    state = state._withStaged(next);
  }

  Future<void> setCameraEmulation(bool enabled) async {
    final next = state.stagedConfig.copyWith(cameraEmulation: enabled);
    await next.save();
    if (_disposed) return;
    state = state._withStaged(next);
  }

  Future<void> setPreviewBase(String url) async {
    final resolved = url.isEmpty ? DevConfig.defaults.previewBaseUrl : url;
    final next = state.stagedConfig.copyWith(previewBaseUrl: resolved);
    await next.save();
    if (_disposed) return;
    state = state._withStaged(next);
  }

  Future<void> setDownloadBase(String url) async {
    final resolved = url.isEmpty ? DevConfig.defaults.downloadBaseUrl : url;
    final next = state.stagedConfig.copyWith(downloadBaseUrl: resolved);
    await next.save();
    if (_disposed) return;
    state = state._withStaged(next);
  }
}

final developerSettingsProvider =
    AutoDisposeNotifierProvider<
      DeveloperSettingsNotifier,
      DeveloperSettingsState
    >(DeveloperSettingsNotifier.new);
