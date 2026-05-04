// Sport setup preset — a saved time configuration for a sport, e.g.
// "Soccer · Tournament A" (2 × 35 min). Stored on the camera so it persists
// across matches and devices.
//
// Wire format mirrors `SportPreset` in `proto/bluetooth.proto`.

import 'package:flutter/foundation.dart';

@immutable
class SportPreset {
  const SportPreset({
    required this.id,
    required this.name,
    required this.sport,
    required this.numPeriods,
    required this.periodLengthSeconds,
    this.builtIn = false,
  });

  final String id;
  final String name;

  /// Base sport label (matches `TeamRecord.sport`). Used to constrain which
  /// presets show up when scheduling a match for a given team.
  final String sport;
  final int numPeriods;
  final int periodLengthSeconds;

  /// Factory presets shipped with firmware; UI hides delete for these.
  final bool builtIn;

  int get periodLengthMinutes => periodLengthSeconds ~/ 60;

  /// Compact format summary, e.g. `"2 × 35 min"`.
  String get summary => '$numPeriods × $periodLengthMinutes min';

  SportPreset copyWith({
    String? name,
    String? sport,
    int? numPeriods,
    int? periodLengthSeconds,
    bool? builtIn,
  }) {
    return SportPreset(
      id: id,
      name: name ?? this.name,
      sport: sport ?? this.sport,
      numPeriods: numPeriods ?? this.numPeriods,
      periodLengthSeconds: periodLengthSeconds ?? this.periodLengthSeconds,
      builtIn: builtIn ?? this.builtIn,
    );
  }
}

/// Mutable inputs for create/update. `id` is empty on create — firmware
/// assigns it.
@immutable
class SportPresetDraft {
  const SportPresetDraft({
    required this.name,
    required this.sport,
    required this.numPeriods,
    required this.periodLengthSeconds,
    this.id = '',
  });

  final String id;
  final String name;
  final String sport;
  final int numPeriods;
  final int periodLengthSeconds;
}
