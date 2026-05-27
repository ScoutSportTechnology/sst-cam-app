import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injectable DB re-seeding callback for dev builds.
///
/// Defaults to a no-op so prod and empty-mode code paths work safely.
/// In dev builds, main.dart overrides this with MockDataSeeder.seed.
final devReseedProvider = Provider<Future<void> Function()>(
  (ref) => () async {},
);
