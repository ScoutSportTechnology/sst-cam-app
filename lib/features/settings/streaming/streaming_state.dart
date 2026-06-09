// Streaming destinations state — per-user list. `userId` is passed explicitly
// to every BleService call (sourced from `activeUserProvider`); when no user
// is active, `build()` returns empty without making a BLE call.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart'
    show StreamingDestinationsTableData, StreamingDestinationsTableCompanion;
import '../../../core/db/daos/streaming_destinations_dao.dart';
import '../../../core/models/streaming.dart';
import '../../../core/state/db_providers.dart';
import '../users/users_state.dart' show activeUserProvider;

export '../../../core/models/streaming.dart';

const _uuid = Uuid();

class StreamingDestinationsController
    extends AsyncNotifier<List<StreamingDestination>> {
  String _requireActiveUser() {
    final activeUserId = ref.read(activeUserProvider);
    if (activeUserId == null) {
      throw StateError('No active user');
    }
    return activeUserId;
  }

  @override
  Future<List<StreamingDestination>> build() async {
    final activeUserId = ref.watch(activeUserProvider);
    if (activeUserId == null) return const [];

    final dao = ref.watch(streamingDestinationsDaoProvider);

    // Subscribe to all mutations. The listener may fire once with the same
    // data as the initial snapshot below; that is acceptable.
    final sub = dao
        .watchForUser(activeUserId)
        .listen(
          (rows) {
            state = AsyncValue.data(_toDestinations(rows));
          },
          onError: (Object e, StackTrace st) {
            state = AsyncValue.error(e, st);
          },
        );
    ref.onDispose(sub.cancel);

    return _toDestinations(await dao.getForUser(activeUserId));
  }

  static List<StreamingDestination> _toDestinations(
    List<StreamingDestinationsTableData> rows,
  ) => rows
      .map(
        (r) => StreamingDestination(
          id: r.id,
          name: r.name,
          provider: StreamingProvider.values.byName(r.provider),
          protocol: StreamingProtocol.values.byName(r.protocol),
          config: StreamingDestinationsDao.configFromRow(r),
        ),
      )
      .toList();

  StreamingDestinationsTableCompanion _draftToCompanion(
    String id,
    String userId,
    StreamingDestinationDraft draft,
  ) {
    final config = draft.config;
    return switch (config) {
      RtmpConfig() => StreamingDestinationsTableCompanion.insert(
        id: id,
        userId: userId,
        name: draft.name,
        provider: draft.provider.name,
        protocol: draft.protocol.name,
        configType: 'rtmp',
        configUrl: config.url,
        configStreamKey: Value(config.streamKey),
        configUsername: const Value(null),
        configPassword: const Value(null),
      ),
      RtspConfig() => StreamingDestinationsTableCompanion.insert(
        id: id,
        userId: userId,
        name: draft.name,
        provider: draft.provider.name,
        protocol: draft.protocol.name,
        configType: 'rtsp',
        configUrl: config.url,
        configStreamKey: const Value(null),
        configUsername: Value(config.username),
        configPassword: Value(config.password),
      ),
    };
  }

  Future<StreamingDestination> create(StreamingDestinationDraft draft) async {
    final userId = _requireActiveUser();
    final id = _uuid.v4();
    final companion = _draftToCompanion(id, userId, draft);
    await ref
        .read(streamingDestinationsDaoProvider)
        .insertDestination(companion);
    final config = draft.config;
    return StreamingDestination(
      id: id,
      name: draft.name,
      provider: draft.provider,
      protocol: draft.protocol,
      config: config,
    );
  }

  Future<StreamingDestination> edit(StreamingDestinationDraft draft) async {
    final userId = _requireActiveUser();
    final companion = _draftToCompanion(draft.id, userId, draft);
    await ref
        .read(streamingDestinationsDaoProvider)
        .updateDestination(companion);
    return StreamingDestination(
      id: draft.id,
      name: draft.name,
      provider: draft.provider,
      protocol: draft.protocol,
      config: draft.config,
    );
  }

  Future<void> delete(String destinationId) async {
    await ref.read(streamingDestinationsDaoProvider).deleteById(destinationId);
  }
}

final streamingDestinationsControllerProvider =
    AsyncNotifierProvider<
      StreamingDestinationsController,
      List<StreamingDestination>
    >(StreamingDestinationsController.new);
