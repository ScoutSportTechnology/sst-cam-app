// Camera-side operator profile. A `User` scopes everything the camera owns —
// teams, match history, sport setups, and streaming destinations — so a
// single ScoutCamera can be shared across multiple coaches without their
// data bleeding together.
//
// The phone is a thin client: users are read/written via `BleService` and
// never persisted on the device. Wire format will mirror this shape when
// firmware integration begins (see proto/README.md).

import 'package:flutter/foundation.dart';

@immutable
class UserRecord {
  const UserRecord({required this.id, required this.name});

  final String id;
  final String name;

  UserRecord copyWith({String? name}) {
    return UserRecord(id: id, name: name ?? this.name);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserRecord && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// Mutable inputs for create/update. `id` is empty on create — firmware
/// assigns it.
@immutable
class UserDraft {
  const UserDraft({required this.name, this.id = ''});

  final String id;
  final String name;
}
