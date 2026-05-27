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
  @override
  DeveloperSettingsState build() {
    final active = ref.watch(devConfigProvider);
    return DeveloperSettingsState(activeConfig: active, stagedConfig: active);
  }

  Future<void> setDataMode(DataMode mode) async {
    final next = state.stagedConfig.copyWith(dataMode: mode);
    await next.save();
    state = state._withStaged(next);
  }

  Future<void> setCameraEmulation(bool enabled) async {
    final next = state.stagedConfig.copyWith(cameraEmulation: enabled);
    await next.save();
    state = state._withStaged(next);
  }

  Future<void> setServerAddress(String address) async {
    final resolved = address.isEmpty ? 'localhost' : address;
    final next = state.stagedConfig.copyWith(serverAddress: resolved);
    await next.save();
    state = state._withStaged(next);
  }
}

final developerSettingsProvider = AutoDisposeNotifierProvider<
  DeveloperSettingsNotifier,
  DeveloperSettingsState
>(DeveloperSettingsNotifier.new);
