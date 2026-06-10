// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $UsersTableTable extends UsersTable
    with TableInfo<$UsersTableTable, UsersTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsersTableTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'users';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UsersTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UsersTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
    );
  }

  @override
  $UsersTableTable createAlias(String alias) {
    return $UsersTableTable(attachedDatabase, alias);
  }
}

class UsersTableData extends DataClass implements Insertable<UsersTableData> {
  final String id;
  final String name;
  const UsersTableData({required this.id, required this.name});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    return map;
  }

  UsersTableCompanion toCompanion(bool nullToAbsent) {
    return UsersTableCompanion(id: Value(id), name: Value(name));
  }

  factory UsersTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UsersTableData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
    };
  }

  UsersTableData copyWith({String? id, String? name}) =>
      UsersTableData(id: id ?? this.id, name: name ?? this.name);
  UsersTableData copyWithCompanion(UsersTableCompanion data) {
    return UsersTableData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UsersTableData(')
          ..write('id: $id, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UsersTableData &&
          other.id == this.id &&
          other.name == this.name);
}

class UsersTableCompanion extends UpdateCompanion<UsersTableData> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> rowid;
  const UsersTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UsersTableCompanion.insert({
    required String id,
    required String name,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<UsersTableData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UsersTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? rowid,
  }) {
    return UsersTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TeamsTableTable extends TeamsTable
    with TableInfo<$TeamsTableTable, TeamsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TeamsTableTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> shortName = GeneratedColumn<String>(
    'short_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> sport = GeneratedColumn<String>(
    'sport',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> colorHex = GeneratedColumn<String>(
    'color_hex',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<bool> hidden = GeneratedColumn<bool>(
    'hidden',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("hidden" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    name,
    shortName,
    sport,
    colorHex,
    hidden,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'teams';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TeamsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TeamsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      shortName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}short_name'],
      )!,
      sport: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sport'],
      )!,
      colorHex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_hex'],
      ),
      hidden: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}hidden'],
      )!,
    );
  }

  @override
  $TeamsTableTable createAlias(String alias) {
    return $TeamsTableTable(attachedDatabase, alias);
  }
}

class TeamsTableData extends DataClass implements Insertable<TeamsTableData> {
  final String id;
  final String userId;
  final String name;
  final String shortName;
  final String sport;
  final String? colorHex;
  final bool hidden;
  const TeamsTableData({
    required this.id,
    required this.userId,
    required this.name,
    required this.shortName,
    required this.sport,
    this.colorHex,
    required this.hidden,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['name'] = Variable<String>(name);
    map['short_name'] = Variable<String>(shortName);
    map['sport'] = Variable<String>(sport);
    if (!nullToAbsent || colorHex != null) {
      map['color_hex'] = Variable<String>(colorHex);
    }
    map['hidden'] = Variable<bool>(hidden);
    return map;
  }

  TeamsTableCompanion toCompanion(bool nullToAbsent) {
    return TeamsTableCompanion(
      id: Value(id),
      userId: Value(userId),
      name: Value(name),
      shortName: Value(shortName),
      sport: Value(sport),
      colorHex: colorHex == null && nullToAbsent
          ? const Value.absent()
          : Value(colorHex),
      hidden: Value(hidden),
    );
  }

  factory TeamsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TeamsTableData(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      name: serializer.fromJson<String>(json['name']),
      shortName: serializer.fromJson<String>(json['shortName']),
      sport: serializer.fromJson<String>(json['sport']),
      colorHex: serializer.fromJson<String?>(json['colorHex']),
      hidden: serializer.fromJson<bool>(json['hidden']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'name': serializer.toJson<String>(name),
      'shortName': serializer.toJson<String>(shortName),
      'sport': serializer.toJson<String>(sport),
      'colorHex': serializer.toJson<String?>(colorHex),
      'hidden': serializer.toJson<bool>(hidden),
    };
  }

  TeamsTableData copyWith({
    String? id,
    String? userId,
    String? name,
    String? shortName,
    String? sport,
    Value<String?> colorHex = const Value.absent(),
    bool? hidden,
  }) => TeamsTableData(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    name: name ?? this.name,
    shortName: shortName ?? this.shortName,
    sport: sport ?? this.sport,
    colorHex: colorHex.present ? colorHex.value : this.colorHex,
    hidden: hidden ?? this.hidden,
  );
  TeamsTableData copyWithCompanion(TeamsTableCompanion data) {
    return TeamsTableData(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      name: data.name.present ? data.name.value : this.name,
      shortName: data.shortName.present ? data.shortName.value : this.shortName,
      sport: data.sport.present ? data.sport.value : this.sport,
      colorHex: data.colorHex.present ? data.colorHex.value : this.colorHex,
      hidden: data.hidden.present ? data.hidden.value : this.hidden,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TeamsTableData(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('shortName: $shortName, ')
          ..write('sport: $sport, ')
          ..write('colorHex: $colorHex, ')
          ..write('hidden: $hidden')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, userId, name, shortName, sport, colorHex, hidden);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TeamsTableData &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.name == this.name &&
          other.shortName == this.shortName &&
          other.sport == this.sport &&
          other.colorHex == this.colorHex &&
          other.hidden == this.hidden);
}

class TeamsTableCompanion extends UpdateCompanion<TeamsTableData> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> name;
  final Value<String> shortName;
  final Value<String> sport;
  final Value<String?> colorHex;
  final Value<bool> hidden;
  final Value<int> rowid;
  const TeamsTableCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.name = const Value.absent(),
    this.shortName = const Value.absent(),
    this.sport = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.hidden = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TeamsTableCompanion.insert({
    required String id,
    required String userId,
    required String name,
    required String shortName,
    required String sport,
    this.colorHex = const Value.absent(),
    this.hidden = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       name = Value(name),
       shortName = Value(shortName),
       sport = Value(sport);
  static Insertable<TeamsTableData> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? name,
    Expression<String>? shortName,
    Expression<String>? sport,
    Expression<String>? colorHex,
    Expression<bool>? hidden,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (name != null) 'name': name,
      if (shortName != null) 'short_name': shortName,
      if (sport != null) 'sport': sport,
      if (colorHex != null) 'color_hex': colorHex,
      if (hidden != null) 'hidden': hidden,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TeamsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? name,
    Value<String>? shortName,
    Value<String>? sport,
    Value<String?>? colorHex,
    Value<bool>? hidden,
    Value<int>? rowid,
  }) {
    return TeamsTableCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      shortName: shortName ?? this.shortName,
      sport: sport ?? this.sport,
      colorHex: colorHex ?? this.colorHex,
      hidden: hidden ?? this.hidden,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (shortName.present) {
      map['short_name'] = Variable<String>(shortName.value);
    }
    if (sport.present) {
      map['sport'] = Variable<String>(sport.value);
    }
    if (colorHex.present) {
      map['color_hex'] = Variable<String>(colorHex.value);
    }
    if (hidden.present) {
      map['hidden'] = Variable<bool>(hidden.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TeamsTableCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('shortName: $shortName, ')
          ..write('sport: $sport, ')
          ..write('colorHex: $colorHex, ')
          ..write('hidden: $hidden, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlayersTableTable extends PlayersTable
    with TableInfo<$PlayersTableTable, PlayersTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlayersTableTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<String> teamId = GeneratedColumn<String>(
    'team_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES teams (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> position = GeneratedColumn<String>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<bool> captain = GeneratedColumn<bool>(
    'captain',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("captain" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    teamId,
    number,
    name,
    position,
    captain,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'players';
  @override
  Set<GeneratedColumn> get $primaryKey => {teamId, number};
  @override
  PlayersTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlayersTableData(
      teamId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}team_id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}position'],
      )!,
      captain: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}captain'],
      )!,
    );
  }

  @override
  $PlayersTableTable createAlias(String alias) {
    return $PlayersTableTable(attachedDatabase, alias);
  }
}

class PlayersTableData extends DataClass
    implements Insertable<PlayersTableData> {
  final String teamId;
  final int number;
  final String name;
  final String position;
  final bool captain;
  const PlayersTableData({
    required this.teamId,
    required this.number,
    required this.name,
    required this.position,
    required this.captain,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['team_id'] = Variable<String>(teamId);
    map['number'] = Variable<int>(number);
    map['name'] = Variable<String>(name);
    map['position'] = Variable<String>(position);
    map['captain'] = Variable<bool>(captain);
    return map;
  }

  PlayersTableCompanion toCompanion(bool nullToAbsent) {
    return PlayersTableCompanion(
      teamId: Value(teamId),
      number: Value(number),
      name: Value(name),
      position: Value(position),
      captain: Value(captain),
    );
  }

  factory PlayersTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlayersTableData(
      teamId: serializer.fromJson<String>(json['teamId']),
      number: serializer.fromJson<int>(json['number']),
      name: serializer.fromJson<String>(json['name']),
      position: serializer.fromJson<String>(json['position']),
      captain: serializer.fromJson<bool>(json['captain']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'teamId': serializer.toJson<String>(teamId),
      'number': serializer.toJson<int>(number),
      'name': serializer.toJson<String>(name),
      'position': serializer.toJson<String>(position),
      'captain': serializer.toJson<bool>(captain),
    };
  }

  PlayersTableData copyWith({
    String? teamId,
    int? number,
    String? name,
    String? position,
    bool? captain,
  }) => PlayersTableData(
    teamId: teamId ?? this.teamId,
    number: number ?? this.number,
    name: name ?? this.name,
    position: position ?? this.position,
    captain: captain ?? this.captain,
  );
  PlayersTableData copyWithCompanion(PlayersTableCompanion data) {
    return PlayersTableData(
      teamId: data.teamId.present ? data.teamId.value : this.teamId,
      number: data.number.present ? data.number.value : this.number,
      name: data.name.present ? data.name.value : this.name,
      position: data.position.present ? data.position.value : this.position,
      captain: data.captain.present ? data.captain.value : this.captain,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlayersTableData(')
          ..write('teamId: $teamId, ')
          ..write('number: $number, ')
          ..write('name: $name, ')
          ..write('position: $position, ')
          ..write('captain: $captain')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(teamId, number, name, position, captain);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlayersTableData &&
          other.teamId == this.teamId &&
          other.number == this.number &&
          other.name == this.name &&
          other.position == this.position &&
          other.captain == this.captain);
}

class PlayersTableCompanion extends UpdateCompanion<PlayersTableData> {
  final Value<String> teamId;
  final Value<int> number;
  final Value<String> name;
  final Value<String> position;
  final Value<bool> captain;
  final Value<int> rowid;
  const PlayersTableCompanion({
    this.teamId = const Value.absent(),
    this.number = const Value.absent(),
    this.name = const Value.absent(),
    this.position = const Value.absent(),
    this.captain = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlayersTableCompanion.insert({
    required String teamId,
    required int number,
    required String name,
    required String position,
    this.captain = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : teamId = Value(teamId),
       number = Value(number),
       name = Value(name),
       position = Value(position);
  static Insertable<PlayersTableData> custom({
    Expression<String>? teamId,
    Expression<int>? number,
    Expression<String>? name,
    Expression<String>? position,
    Expression<bool>? captain,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (teamId != null) 'team_id': teamId,
      if (number != null) 'number': number,
      if (name != null) 'name': name,
      if (position != null) 'position': position,
      if (captain != null) 'captain': captain,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlayersTableCompanion copyWith({
    Value<String>? teamId,
    Value<int>? number,
    Value<String>? name,
    Value<String>? position,
    Value<bool>? captain,
    Value<int>? rowid,
  }) {
    return PlayersTableCompanion(
      teamId: teamId ?? this.teamId,
      number: number ?? this.number,
      name: name ?? this.name,
      position: position ?? this.position,
      captain: captain ?? this.captain,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (teamId.present) {
      map['team_id'] = Variable<String>(teamId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (position.present) {
      map['position'] = Variable<String>(position.value);
    }
    if (captain.present) {
      map['captain'] = Variable<bool>(captain.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlayersTableCompanion(')
          ..write('teamId: $teamId, ')
          ..write('number: $number, ')
          ..write('name: $name, ')
          ..write('position: $position, ')
          ..write('captain: $captain, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TeamMatchesTableTable extends TeamMatchesTable
    with TableInfo<$TeamMatchesTableTable, TeamMatchesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TeamMatchesTableTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> teamId = GeneratedColumn<String>(
    'team_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES teams (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> opponent = GeneratedColumn<String>(
    'opponent',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> result = GeneratedColumn<String>(
    'result',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> numPeriods = GeneratedColumn<int>(
    'num_periods',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> periodLengthSeconds = GeneratedColumn<int>(
    'period_length_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> clips = GeneratedColumn<int>(
    'clips',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumn<int> sizeMb = GeneratedColumn<int>(
    'size_mb',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumn<String> eventsJson = GeneratedColumn<String>(
    'events_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    teamId,
    opponent,
    date,
    result,
    kind,
    numPeriods,
    periodLengthSeconds,
    clips,
    sizeMb,
    eventsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'team_matches';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TeamMatchesTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TeamMatchesTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      teamId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}team_id'],
      )!,
      opponent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}opponent'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      result: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      numPeriods: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}num_periods'],
      )!,
      periodLengthSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}period_length_seconds'],
      )!,
      clips: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}clips'],
      )!,
      sizeMb: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_mb'],
      )!,
      eventsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}events_json'],
      )!,
    );
  }

  @override
  $TeamMatchesTableTable createAlias(String alias) {
    return $TeamMatchesTableTable(attachedDatabase, alias);
  }
}

class TeamMatchesTableData extends DataClass
    implements Insertable<TeamMatchesTableData> {
  final String id;
  final String teamId;
  final String opponent;
  final String date;
  final String result;

  /// 'past' | 'upcoming'
  final String kind;
  final int numPeriods;
  final int periodLengthSeconds;
  final int clips;
  final int sizeMb;

  /// JSON-encoded list of match events: [{timeSeconds, label, team, kind}].
  /// Empty array '[]' when no events recorded.
  final String eventsJson;
  const TeamMatchesTableData({
    required this.id,
    required this.teamId,
    required this.opponent,
    required this.date,
    required this.result,
    required this.kind,
    required this.numPeriods,
    required this.periodLengthSeconds,
    required this.clips,
    required this.sizeMb,
    required this.eventsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['team_id'] = Variable<String>(teamId);
    map['opponent'] = Variable<String>(opponent);
    map['date'] = Variable<String>(date);
    map['result'] = Variable<String>(result);
    map['kind'] = Variable<String>(kind);
    map['num_periods'] = Variable<int>(numPeriods);
    map['period_length_seconds'] = Variable<int>(periodLengthSeconds);
    map['clips'] = Variable<int>(clips);
    map['size_mb'] = Variable<int>(sizeMb);
    map['events_json'] = Variable<String>(eventsJson);
    return map;
  }

  TeamMatchesTableCompanion toCompanion(bool nullToAbsent) {
    return TeamMatchesTableCompanion(
      id: Value(id),
      teamId: Value(teamId),
      opponent: Value(opponent),
      date: Value(date),
      result: Value(result),
      kind: Value(kind),
      numPeriods: Value(numPeriods),
      periodLengthSeconds: Value(periodLengthSeconds),
      clips: Value(clips),
      sizeMb: Value(sizeMb),
      eventsJson: Value(eventsJson),
    );
  }

  factory TeamMatchesTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TeamMatchesTableData(
      id: serializer.fromJson<String>(json['id']),
      teamId: serializer.fromJson<String>(json['teamId']),
      opponent: serializer.fromJson<String>(json['opponent']),
      date: serializer.fromJson<String>(json['date']),
      result: serializer.fromJson<String>(json['result']),
      kind: serializer.fromJson<String>(json['kind']),
      numPeriods: serializer.fromJson<int>(json['numPeriods']),
      periodLengthSeconds: serializer.fromJson<int>(
        json['periodLengthSeconds'],
      ),
      clips: serializer.fromJson<int>(json['clips']),
      sizeMb: serializer.fromJson<int>(json['sizeMb']),
      eventsJson: serializer.fromJson<String>(json['eventsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'teamId': serializer.toJson<String>(teamId),
      'opponent': serializer.toJson<String>(opponent),
      'date': serializer.toJson<String>(date),
      'result': serializer.toJson<String>(result),
      'kind': serializer.toJson<String>(kind),
      'numPeriods': serializer.toJson<int>(numPeriods),
      'periodLengthSeconds': serializer.toJson<int>(periodLengthSeconds),
      'clips': serializer.toJson<int>(clips),
      'sizeMb': serializer.toJson<int>(sizeMb),
      'eventsJson': serializer.toJson<String>(eventsJson),
    };
  }

  TeamMatchesTableData copyWith({
    String? id,
    String? teamId,
    String? opponent,
    String? date,
    String? result,
    String? kind,
    int? numPeriods,
    int? periodLengthSeconds,
    int? clips,
    int? sizeMb,
    String? eventsJson,
  }) => TeamMatchesTableData(
    id: id ?? this.id,
    teamId: teamId ?? this.teamId,
    opponent: opponent ?? this.opponent,
    date: date ?? this.date,
    result: result ?? this.result,
    kind: kind ?? this.kind,
    numPeriods: numPeriods ?? this.numPeriods,
    periodLengthSeconds: periodLengthSeconds ?? this.periodLengthSeconds,
    clips: clips ?? this.clips,
    sizeMb: sizeMb ?? this.sizeMb,
    eventsJson: eventsJson ?? this.eventsJson,
  );
  TeamMatchesTableData copyWithCompanion(TeamMatchesTableCompanion data) {
    return TeamMatchesTableData(
      id: data.id.present ? data.id.value : this.id,
      teamId: data.teamId.present ? data.teamId.value : this.teamId,
      opponent: data.opponent.present ? data.opponent.value : this.opponent,
      date: data.date.present ? data.date.value : this.date,
      result: data.result.present ? data.result.value : this.result,
      kind: data.kind.present ? data.kind.value : this.kind,
      numPeriods: data.numPeriods.present
          ? data.numPeriods.value
          : this.numPeriods,
      periodLengthSeconds: data.periodLengthSeconds.present
          ? data.periodLengthSeconds.value
          : this.periodLengthSeconds,
      clips: data.clips.present ? data.clips.value : this.clips,
      sizeMb: data.sizeMb.present ? data.sizeMb.value : this.sizeMb,
      eventsJson: data.eventsJson.present
          ? data.eventsJson.value
          : this.eventsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TeamMatchesTableData(')
          ..write('id: $id, ')
          ..write('teamId: $teamId, ')
          ..write('opponent: $opponent, ')
          ..write('date: $date, ')
          ..write('result: $result, ')
          ..write('kind: $kind, ')
          ..write('numPeriods: $numPeriods, ')
          ..write('periodLengthSeconds: $periodLengthSeconds, ')
          ..write('clips: $clips, ')
          ..write('sizeMb: $sizeMb, ')
          ..write('eventsJson: $eventsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    teamId,
    opponent,
    date,
    result,
    kind,
    numPeriods,
    periodLengthSeconds,
    clips,
    sizeMb,
    eventsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TeamMatchesTableData &&
          other.id == this.id &&
          other.teamId == this.teamId &&
          other.opponent == this.opponent &&
          other.date == this.date &&
          other.result == this.result &&
          other.kind == this.kind &&
          other.numPeriods == this.numPeriods &&
          other.periodLengthSeconds == this.periodLengthSeconds &&
          other.clips == this.clips &&
          other.sizeMb == this.sizeMb &&
          other.eventsJson == this.eventsJson);
}

class TeamMatchesTableCompanion extends UpdateCompanion<TeamMatchesTableData> {
  final Value<String> id;
  final Value<String> teamId;
  final Value<String> opponent;
  final Value<String> date;
  final Value<String> result;
  final Value<String> kind;
  final Value<int> numPeriods;
  final Value<int> periodLengthSeconds;
  final Value<int> clips;
  final Value<int> sizeMb;
  final Value<String> eventsJson;
  final Value<int> rowid;
  const TeamMatchesTableCompanion({
    this.id = const Value.absent(),
    this.teamId = const Value.absent(),
    this.opponent = const Value.absent(),
    this.date = const Value.absent(),
    this.result = const Value.absent(),
    this.kind = const Value.absent(),
    this.numPeriods = const Value.absent(),
    this.periodLengthSeconds = const Value.absent(),
    this.clips = const Value.absent(),
    this.sizeMb = const Value.absent(),
    this.eventsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TeamMatchesTableCompanion.insert({
    required String id,
    required String teamId,
    required String opponent,
    required String date,
    required String result,
    required String kind,
    required int numPeriods,
    required int periodLengthSeconds,
    this.clips = const Value.absent(),
    this.sizeMb = const Value.absent(),
    this.eventsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       teamId = Value(teamId),
       opponent = Value(opponent),
       date = Value(date),
       result = Value(result),
       kind = Value(kind),
       numPeriods = Value(numPeriods),
       periodLengthSeconds = Value(periodLengthSeconds);
  static Insertable<TeamMatchesTableData> custom({
    Expression<String>? id,
    Expression<String>? teamId,
    Expression<String>? opponent,
    Expression<String>? date,
    Expression<String>? result,
    Expression<String>? kind,
    Expression<int>? numPeriods,
    Expression<int>? periodLengthSeconds,
    Expression<int>? clips,
    Expression<int>? sizeMb,
    Expression<String>? eventsJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (teamId != null) 'team_id': teamId,
      if (opponent != null) 'opponent': opponent,
      if (date != null) 'date': date,
      if (result != null) 'result': result,
      if (kind != null) 'kind': kind,
      if (numPeriods != null) 'num_periods': numPeriods,
      if (periodLengthSeconds != null)
        'period_length_seconds': periodLengthSeconds,
      if (clips != null) 'clips': clips,
      if (sizeMb != null) 'size_mb': sizeMb,
      if (eventsJson != null) 'events_json': eventsJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TeamMatchesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? teamId,
    Value<String>? opponent,
    Value<String>? date,
    Value<String>? result,
    Value<String>? kind,
    Value<int>? numPeriods,
    Value<int>? periodLengthSeconds,
    Value<int>? clips,
    Value<int>? sizeMb,
    Value<String>? eventsJson,
    Value<int>? rowid,
  }) {
    return TeamMatchesTableCompanion(
      id: id ?? this.id,
      teamId: teamId ?? this.teamId,
      opponent: opponent ?? this.opponent,
      date: date ?? this.date,
      result: result ?? this.result,
      kind: kind ?? this.kind,
      numPeriods: numPeriods ?? this.numPeriods,
      periodLengthSeconds: periodLengthSeconds ?? this.periodLengthSeconds,
      clips: clips ?? this.clips,
      sizeMb: sizeMb ?? this.sizeMb,
      eventsJson: eventsJson ?? this.eventsJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (teamId.present) {
      map['team_id'] = Variable<String>(teamId.value);
    }
    if (opponent.present) {
      map['opponent'] = Variable<String>(opponent.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (result.present) {
      map['result'] = Variable<String>(result.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (numPeriods.present) {
      map['num_periods'] = Variable<int>(numPeriods.value);
    }
    if (periodLengthSeconds.present) {
      map['period_length_seconds'] = Variable<int>(periodLengthSeconds.value);
    }
    if (clips.present) {
      map['clips'] = Variable<int>(clips.value);
    }
    if (sizeMb.present) {
      map['size_mb'] = Variable<int>(sizeMb.value);
    }
    if (eventsJson.present) {
      map['events_json'] = Variable<String>(eventsJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TeamMatchesTableCompanion(')
          ..write('id: $id, ')
          ..write('teamId: $teamId, ')
          ..write('opponent: $opponent, ')
          ..write('date: $date, ')
          ..write('result: $result, ')
          ..write('kind: $kind, ')
          ..write('numPeriods: $numPeriods, ')
          ..write('periodLengthSeconds: $periodLengthSeconds, ')
          ..write('clips: $clips, ')
          ..write('sizeMb: $sizeMb, ')
          ..write('eventsJson: $eventsJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SportPresetsTableTable extends SportPresetsTable
    with TableInfo<$SportPresetsTableTable, SportPresetsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SportPresetsTableTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> sport = GeneratedColumn<String>(
    'sport',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> numPeriods = GeneratedColumn<int>(
    'num_periods',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> periodLengthSeconds = GeneratedColumn<int>(
    'period_length_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<bool> builtIn = GeneratedColumn<bool>(
    'built_in',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("built_in" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    name,
    sport,
    numPeriods,
    periodLengthSeconds,
    builtIn,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sport_presets';
  @override
  Set<GeneratedColumn> get $primaryKey => {id, userId};
  @override
  SportPresetsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SportPresetsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sport: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sport'],
      )!,
      numPeriods: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}num_periods'],
      )!,
      periodLengthSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}period_length_seconds'],
      )!,
      builtIn: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}built_in'],
      )!,
    );
  }

  @override
  $SportPresetsTableTable createAlias(String alias) {
    return $SportPresetsTableTable(attachedDatabase, alias);
  }
}

class SportPresetsTableData extends DataClass
    implements Insertable<SportPresetsTableData> {
  final String id;
  final String userId;
  final String name;
  final String sport;
  final int numPeriods;
  final int periodLengthSeconds;
  final bool builtIn;
  const SportPresetsTableData({
    required this.id,
    required this.userId,
    required this.name,
    required this.sport,
    required this.numPeriods,
    required this.periodLengthSeconds,
    required this.builtIn,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['name'] = Variable<String>(name);
    map['sport'] = Variable<String>(sport);
    map['num_periods'] = Variable<int>(numPeriods);
    map['period_length_seconds'] = Variable<int>(periodLengthSeconds);
    map['built_in'] = Variable<bool>(builtIn);
    return map;
  }

  SportPresetsTableCompanion toCompanion(bool nullToAbsent) {
    return SportPresetsTableCompanion(
      id: Value(id),
      userId: Value(userId),
      name: Value(name),
      sport: Value(sport),
      numPeriods: Value(numPeriods),
      periodLengthSeconds: Value(periodLengthSeconds),
      builtIn: Value(builtIn),
    );
  }

  factory SportPresetsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SportPresetsTableData(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      name: serializer.fromJson<String>(json['name']),
      sport: serializer.fromJson<String>(json['sport']),
      numPeriods: serializer.fromJson<int>(json['numPeriods']),
      periodLengthSeconds: serializer.fromJson<int>(
        json['periodLengthSeconds'],
      ),
      builtIn: serializer.fromJson<bool>(json['builtIn']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'name': serializer.toJson<String>(name),
      'sport': serializer.toJson<String>(sport),
      'numPeriods': serializer.toJson<int>(numPeriods),
      'periodLengthSeconds': serializer.toJson<int>(periodLengthSeconds),
      'builtIn': serializer.toJson<bool>(builtIn),
    };
  }

  SportPresetsTableData copyWith({
    String? id,
    String? userId,
    String? name,
    String? sport,
    int? numPeriods,
    int? periodLengthSeconds,
    bool? builtIn,
  }) => SportPresetsTableData(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    name: name ?? this.name,
    sport: sport ?? this.sport,
    numPeriods: numPeriods ?? this.numPeriods,
    periodLengthSeconds: periodLengthSeconds ?? this.periodLengthSeconds,
    builtIn: builtIn ?? this.builtIn,
  );
  SportPresetsTableData copyWithCompanion(SportPresetsTableCompanion data) {
    return SportPresetsTableData(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      name: data.name.present ? data.name.value : this.name,
      sport: data.sport.present ? data.sport.value : this.sport,
      numPeriods: data.numPeriods.present
          ? data.numPeriods.value
          : this.numPeriods,
      periodLengthSeconds: data.periodLengthSeconds.present
          ? data.periodLengthSeconds.value
          : this.periodLengthSeconds,
      builtIn: data.builtIn.present ? data.builtIn.value : this.builtIn,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SportPresetsTableData(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('sport: $sport, ')
          ..write('numPeriods: $numPeriods, ')
          ..write('periodLengthSeconds: $periodLengthSeconds, ')
          ..write('builtIn: $builtIn')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    name,
    sport,
    numPeriods,
    periodLengthSeconds,
    builtIn,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportPresetsTableData &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.name == this.name &&
          other.sport == this.sport &&
          other.numPeriods == this.numPeriods &&
          other.periodLengthSeconds == this.periodLengthSeconds &&
          other.builtIn == this.builtIn);
}

class SportPresetsTableCompanion
    extends UpdateCompanion<SportPresetsTableData> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> name;
  final Value<String> sport;
  final Value<int> numPeriods;
  final Value<int> periodLengthSeconds;
  final Value<bool> builtIn;
  final Value<int> rowid;
  const SportPresetsTableCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.name = const Value.absent(),
    this.sport = const Value.absent(),
    this.numPeriods = const Value.absent(),
    this.periodLengthSeconds = const Value.absent(),
    this.builtIn = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SportPresetsTableCompanion.insert({
    required String id,
    required String userId,
    required String name,
    required String sport,
    required int numPeriods,
    required int periodLengthSeconds,
    this.builtIn = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       name = Value(name),
       sport = Value(sport),
       numPeriods = Value(numPeriods),
       periodLengthSeconds = Value(periodLengthSeconds);
  static Insertable<SportPresetsTableData> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? name,
    Expression<String>? sport,
    Expression<int>? numPeriods,
    Expression<int>? periodLengthSeconds,
    Expression<bool>? builtIn,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (name != null) 'name': name,
      if (sport != null) 'sport': sport,
      if (numPeriods != null) 'num_periods': numPeriods,
      if (periodLengthSeconds != null)
        'period_length_seconds': periodLengthSeconds,
      if (builtIn != null) 'built_in': builtIn,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SportPresetsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? name,
    Value<String>? sport,
    Value<int>? numPeriods,
    Value<int>? periodLengthSeconds,
    Value<bool>? builtIn,
    Value<int>? rowid,
  }) {
    return SportPresetsTableCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      sport: sport ?? this.sport,
      numPeriods: numPeriods ?? this.numPeriods,
      periodLengthSeconds: periodLengthSeconds ?? this.periodLengthSeconds,
      builtIn: builtIn ?? this.builtIn,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sport.present) {
      map['sport'] = Variable<String>(sport.value);
    }
    if (numPeriods.present) {
      map['num_periods'] = Variable<int>(numPeriods.value);
    }
    if (periodLengthSeconds.present) {
      map['period_length_seconds'] = Variable<int>(periodLengthSeconds.value);
    }
    if (builtIn.present) {
      map['built_in'] = Variable<bool>(builtIn.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SportPresetsTableCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('sport: $sport, ')
          ..write('numPeriods: $numPeriods, ')
          ..write('periodLengthSeconds: $periodLengthSeconds, ')
          ..write('builtIn: $builtIn, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StreamingDestinationsTableTable extends StreamingDestinationsTable
    with
        TableInfo<
          $StreamingDestinationsTableTable,
          StreamingDestinationsTableData
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StreamingDestinationsTableTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> protocol = GeneratedColumn<String>(
    'protocol',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> configType = GeneratedColumn<String>(
    'config_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> configUrl = GeneratedColumn<String>(
    'config_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> configStreamKey = GeneratedColumn<String>(
    'config_stream_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> configUsername = GeneratedColumn<String>(
    'config_username',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> configPassword = GeneratedColumn<String>(
    'config_password',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    name,
    provider,
    protocol,
    configType,
    configUrl,
    configStreamKey,
    configUsername,
    configPassword,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'streaming_destinations';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StreamingDestinationsTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StreamingDestinationsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      )!,
      protocol: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}protocol'],
      )!,
      configType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_type'],
      )!,
      configUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_url'],
      )!,
      configStreamKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_stream_key'],
      ),
      configUsername: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_username'],
      ),
      configPassword: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_password'],
      ),
    );
  }

  @override
  $StreamingDestinationsTableTable createAlias(String alias) {
    return $StreamingDestinationsTableTable(attachedDatabase, alias);
  }
}

class StreamingDestinationsTableData extends DataClass
    implements Insertable<StreamingDestinationsTableData> {
  final String id;
  final String userId;
  final String name;
  final String provider;
  final String protocol;

  /// 'rtmp' | 'rtsp'
  final String configType;
  final String configUrl;
  final String? configStreamKey;
  final String? configUsername;
  final String? configPassword;
  const StreamingDestinationsTableData({
    required this.id,
    required this.userId,
    required this.name,
    required this.provider,
    required this.protocol,
    required this.configType,
    required this.configUrl,
    this.configStreamKey,
    this.configUsername,
    this.configPassword,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['name'] = Variable<String>(name);
    map['provider'] = Variable<String>(provider);
    map['protocol'] = Variable<String>(protocol);
    map['config_type'] = Variable<String>(configType);
    map['config_url'] = Variable<String>(configUrl);
    if (!nullToAbsent || configStreamKey != null) {
      map['config_stream_key'] = Variable<String>(configStreamKey);
    }
    if (!nullToAbsent || configUsername != null) {
      map['config_username'] = Variable<String>(configUsername);
    }
    if (!nullToAbsent || configPassword != null) {
      map['config_password'] = Variable<String>(configPassword);
    }
    return map;
  }

  StreamingDestinationsTableCompanion toCompanion(bool nullToAbsent) {
    return StreamingDestinationsTableCompanion(
      id: Value(id),
      userId: Value(userId),
      name: Value(name),
      provider: Value(provider),
      protocol: Value(protocol),
      configType: Value(configType),
      configUrl: Value(configUrl),
      configStreamKey: configStreamKey == null && nullToAbsent
          ? const Value.absent()
          : Value(configStreamKey),
      configUsername: configUsername == null && nullToAbsent
          ? const Value.absent()
          : Value(configUsername),
      configPassword: configPassword == null && nullToAbsent
          ? const Value.absent()
          : Value(configPassword),
    );
  }

  factory StreamingDestinationsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StreamingDestinationsTableData(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      name: serializer.fromJson<String>(json['name']),
      provider: serializer.fromJson<String>(json['provider']),
      protocol: serializer.fromJson<String>(json['protocol']),
      configType: serializer.fromJson<String>(json['configType']),
      configUrl: serializer.fromJson<String>(json['configUrl']),
      configStreamKey: serializer.fromJson<String?>(json['configStreamKey']),
      configUsername: serializer.fromJson<String?>(json['configUsername']),
      configPassword: serializer.fromJson<String?>(json['configPassword']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'name': serializer.toJson<String>(name),
      'provider': serializer.toJson<String>(provider),
      'protocol': serializer.toJson<String>(protocol),
      'configType': serializer.toJson<String>(configType),
      'configUrl': serializer.toJson<String>(configUrl),
      'configStreamKey': serializer.toJson<String?>(configStreamKey),
      'configUsername': serializer.toJson<String?>(configUsername),
      'configPassword': serializer.toJson<String?>(configPassword),
    };
  }

  StreamingDestinationsTableData copyWith({
    String? id,
    String? userId,
    String? name,
    String? provider,
    String? protocol,
    String? configType,
    String? configUrl,
    Value<String?> configStreamKey = const Value.absent(),
    Value<String?> configUsername = const Value.absent(),
    Value<String?> configPassword = const Value.absent(),
  }) => StreamingDestinationsTableData(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    name: name ?? this.name,
    provider: provider ?? this.provider,
    protocol: protocol ?? this.protocol,
    configType: configType ?? this.configType,
    configUrl: configUrl ?? this.configUrl,
    configStreamKey: configStreamKey.present
        ? configStreamKey.value
        : this.configStreamKey,
    configUsername: configUsername.present
        ? configUsername.value
        : this.configUsername,
    configPassword: configPassword.present
        ? configPassword.value
        : this.configPassword,
  );
  StreamingDestinationsTableData copyWithCompanion(
    StreamingDestinationsTableCompanion data,
  ) {
    return StreamingDestinationsTableData(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      name: data.name.present ? data.name.value : this.name,
      provider: data.provider.present ? data.provider.value : this.provider,
      protocol: data.protocol.present ? data.protocol.value : this.protocol,
      configType: data.configType.present
          ? data.configType.value
          : this.configType,
      configUrl: data.configUrl.present ? data.configUrl.value : this.configUrl,
      configStreamKey: data.configStreamKey.present
          ? data.configStreamKey.value
          : this.configStreamKey,
      configUsername: data.configUsername.present
          ? data.configUsername.value
          : this.configUsername,
      configPassword: data.configPassword.present
          ? data.configPassword.value
          : this.configPassword,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StreamingDestinationsTableData(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('provider: $provider, ')
          ..write('protocol: $protocol, ')
          ..write('configType: $configType, ')
          ..write('configUrl: $configUrl, ')
          ..write('configStreamKey: $configStreamKey, ')
          ..write('configUsername: $configUsername, ')
          ..write('configPassword: $configPassword')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    name,
    provider,
    protocol,
    configType,
    configUrl,
    configStreamKey,
    configUsername,
    configPassword,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StreamingDestinationsTableData &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.name == this.name &&
          other.provider == this.provider &&
          other.protocol == this.protocol &&
          other.configType == this.configType &&
          other.configUrl == this.configUrl &&
          other.configStreamKey == this.configStreamKey &&
          other.configUsername == this.configUsername &&
          other.configPassword == this.configPassword);
}

class StreamingDestinationsTableCompanion
    extends UpdateCompanion<StreamingDestinationsTableData> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> name;
  final Value<String> provider;
  final Value<String> protocol;
  final Value<String> configType;
  final Value<String> configUrl;
  final Value<String?> configStreamKey;
  final Value<String?> configUsername;
  final Value<String?> configPassword;
  final Value<int> rowid;
  const StreamingDestinationsTableCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.name = const Value.absent(),
    this.provider = const Value.absent(),
    this.protocol = const Value.absent(),
    this.configType = const Value.absent(),
    this.configUrl = const Value.absent(),
    this.configStreamKey = const Value.absent(),
    this.configUsername = const Value.absent(),
    this.configPassword = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StreamingDestinationsTableCompanion.insert({
    required String id,
    required String userId,
    required String name,
    required String provider,
    required String protocol,
    required String configType,
    required String configUrl,
    this.configStreamKey = const Value.absent(),
    this.configUsername = const Value.absent(),
    this.configPassword = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       name = Value(name),
       provider = Value(provider),
       protocol = Value(protocol),
       configType = Value(configType),
       configUrl = Value(configUrl);
  static Insertable<StreamingDestinationsTableData> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? name,
    Expression<String>? provider,
    Expression<String>? protocol,
    Expression<String>? configType,
    Expression<String>? configUrl,
    Expression<String>? configStreamKey,
    Expression<String>? configUsername,
    Expression<String>? configPassword,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (name != null) 'name': name,
      if (provider != null) 'provider': provider,
      if (protocol != null) 'protocol': protocol,
      if (configType != null) 'config_type': configType,
      if (configUrl != null) 'config_url': configUrl,
      if (configStreamKey != null) 'config_stream_key': configStreamKey,
      if (configUsername != null) 'config_username': configUsername,
      if (configPassword != null) 'config_password': configPassword,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StreamingDestinationsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? name,
    Value<String>? provider,
    Value<String>? protocol,
    Value<String>? configType,
    Value<String>? configUrl,
    Value<String?>? configStreamKey,
    Value<String?>? configUsername,
    Value<String?>? configPassword,
    Value<int>? rowid,
  }) {
    return StreamingDestinationsTableCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      protocol: protocol ?? this.protocol,
      configType: configType ?? this.configType,
      configUrl: configUrl ?? this.configUrl,
      configStreamKey: configStreamKey ?? this.configStreamKey,
      configUsername: configUsername ?? this.configUsername,
      configPassword: configPassword ?? this.configPassword,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (protocol.present) {
      map['protocol'] = Variable<String>(protocol.value);
    }
    if (configType.present) {
      map['config_type'] = Variable<String>(configType.value);
    }
    if (configUrl.present) {
      map['config_url'] = Variable<String>(configUrl.value);
    }
    if (configStreamKey.present) {
      map['config_stream_key'] = Variable<String>(configStreamKey.value);
    }
    if (configUsername.present) {
      map['config_username'] = Variable<String>(configUsername.value);
    }
    if (configPassword.present) {
      map['config_password'] = Variable<String>(configPassword.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StreamingDestinationsTableCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('provider: $provider, ')
          ..write('protocol: $protocol, ')
          ..write('configType: $configType, ')
          ..write('configUrl: $configUrl, ')
          ..write('configStreamKey: $configStreamKey, ')
          ..write('configUsername: $configUsername, ')
          ..write('configPassword: $configPassword, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClipsTableTable extends ClipsTable
    with TableInfo<$ClipsTableTable, ClipsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClipsTableTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> matchId = GeneratedColumn<String>(
    'match_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES team_matches (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<int> startSeconds = GeneratedColumn<int>(
    'start_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> startedAt = GeneratedColumn<String>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    matchId,
    startSeconds,
    durationSeconds,
    sizeBytes,
    startedAt,
    label,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'clips';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ClipsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClipsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      matchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}match_id'],
      )!,
      startSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_seconds'],
      )!,
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}started_at'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      ),
    );
  }

  @override
  $ClipsTableTable createAlias(String alias) {
    return $ClipsTableTable(attachedDatabase, alias);
  }
}

class ClipsTableData extends DataClass implements Insertable<ClipsTableData> {
  final String id;
  final String matchId;

  /// Start offset in seconds from the beginning of the source video.
  final int startSeconds;
  final int durationSeconds;
  final int sizeBytes;
  final String startedAt;
  final String? label;
  const ClipsTableData({
    required this.id,
    required this.matchId,
    required this.startSeconds,
    required this.durationSeconds,
    required this.sizeBytes,
    required this.startedAt,
    this.label,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['match_id'] = Variable<String>(matchId);
    map['start_seconds'] = Variable<int>(startSeconds);
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['started_at'] = Variable<String>(startedAt);
    if (!nullToAbsent || label != null) {
      map['label'] = Variable<String>(label);
    }
    return map;
  }

  ClipsTableCompanion toCompanion(bool nullToAbsent) {
    return ClipsTableCompanion(
      id: Value(id),
      matchId: Value(matchId),
      startSeconds: Value(startSeconds),
      durationSeconds: Value(durationSeconds),
      sizeBytes: Value(sizeBytes),
      startedAt: Value(startedAt),
      label: label == null && nullToAbsent
          ? const Value.absent()
          : Value(label),
    );
  }

  factory ClipsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClipsTableData(
      id: serializer.fromJson<String>(json['id']),
      matchId: serializer.fromJson<String>(json['matchId']),
      startSeconds: serializer.fromJson<int>(json['startSeconds']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      startedAt: serializer.fromJson<String>(json['startedAt']),
      label: serializer.fromJson<String?>(json['label']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'matchId': serializer.toJson<String>(matchId),
      'startSeconds': serializer.toJson<int>(startSeconds),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'startedAt': serializer.toJson<String>(startedAt),
      'label': serializer.toJson<String?>(label),
    };
  }

  ClipsTableData copyWith({
    String? id,
    String? matchId,
    int? startSeconds,
    int? durationSeconds,
    int? sizeBytes,
    String? startedAt,
    Value<String?> label = const Value.absent(),
  }) => ClipsTableData(
    id: id ?? this.id,
    matchId: matchId ?? this.matchId,
    startSeconds: startSeconds ?? this.startSeconds,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    startedAt: startedAt ?? this.startedAt,
    label: label.present ? label.value : this.label,
  );
  ClipsTableData copyWithCompanion(ClipsTableCompanion data) {
    return ClipsTableData(
      id: data.id.present ? data.id.value : this.id,
      matchId: data.matchId.present ? data.matchId.value : this.matchId,
      startSeconds: data.startSeconds.present
          ? data.startSeconds.value
          : this.startSeconds,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      label: data.label.present ? data.label.value : this.label,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClipsTableData(')
          ..write('id: $id, ')
          ..write('matchId: $matchId, ')
          ..write('startSeconds: $startSeconds, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('startedAt: $startedAt, ')
          ..write('label: $label')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    matchId,
    startSeconds,
    durationSeconds,
    sizeBytes,
    startedAt,
    label,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClipsTableData &&
          other.id == this.id &&
          other.matchId == this.matchId &&
          other.startSeconds == this.startSeconds &&
          other.durationSeconds == this.durationSeconds &&
          other.sizeBytes == this.sizeBytes &&
          other.startedAt == this.startedAt &&
          other.label == this.label);
}

class ClipsTableCompanion extends UpdateCompanion<ClipsTableData> {
  final Value<String> id;
  final Value<String> matchId;
  final Value<int> startSeconds;
  final Value<int> durationSeconds;
  final Value<int> sizeBytes;
  final Value<String> startedAt;
  final Value<String?> label;
  final Value<int> rowid;
  const ClipsTableCompanion({
    this.id = const Value.absent(),
    this.matchId = const Value.absent(),
    this.startSeconds = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.label = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClipsTableCompanion.insert({
    required String id,
    required String matchId,
    this.startSeconds = const Value.absent(),
    required int durationSeconds,
    required int sizeBytes,
    required String startedAt,
    this.label = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       matchId = Value(matchId),
       durationSeconds = Value(durationSeconds),
       sizeBytes = Value(sizeBytes),
       startedAt = Value(startedAt);
  static Insertable<ClipsTableData> custom({
    Expression<String>? id,
    Expression<String>? matchId,
    Expression<int>? startSeconds,
    Expression<int>? durationSeconds,
    Expression<int>? sizeBytes,
    Expression<String>? startedAt,
    Expression<String>? label,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (matchId != null) 'match_id': matchId,
      if (startSeconds != null) 'start_seconds': startSeconds,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (startedAt != null) 'started_at': startedAt,
      if (label != null) 'label': label,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClipsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? matchId,
    Value<int>? startSeconds,
    Value<int>? durationSeconds,
    Value<int>? sizeBytes,
    Value<String>? startedAt,
    Value<String?>? label,
    Value<int>? rowid,
  }) {
    return ClipsTableCompanion(
      id: id ?? this.id,
      matchId: matchId ?? this.matchId,
      startSeconds: startSeconds ?? this.startSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      startedAt: startedAt ?? this.startedAt,
      label: label ?? this.label,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (matchId.present) {
      map['match_id'] = Variable<String>(matchId.value);
    }
    if (startSeconds.present) {
      map['start_seconds'] = Variable<int>(startSeconds.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<String>(startedAt.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClipsTableCompanion(')
          ..write('id: $id, ')
          ..write('matchId: $matchId, ')
          ..write('startSeconds: $startSeconds, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('startedAt: $startedAt, ')
          ..write('label: $label, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ThumbnailsTableTable extends ThumbnailsTable
    with TableInfo<$ThumbnailsTableTable, ThumbnailsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ThumbnailsTableTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<String> clipId = GeneratedColumn<String>(
    'clip_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES clips (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [clipId, localPath];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'thumbnails';
  @override
  Set<GeneratedColumn> get $primaryKey => {clipId};
  @override
  ThumbnailsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ThumbnailsTableData(
      clipId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}clip_id'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
    );
  }

  @override
  $ThumbnailsTableTable createAlias(String alias) {
    return $ThumbnailsTableTable(attachedDatabase, alias);
  }
}

class ThumbnailsTableData extends DataClass
    implements Insertable<ThumbnailsTableData> {
  final String clipId;
  final String localPath;
  const ThumbnailsTableData({required this.clipId, required this.localPath});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['clip_id'] = Variable<String>(clipId);
    map['local_path'] = Variable<String>(localPath);
    return map;
  }

  ThumbnailsTableCompanion toCompanion(bool nullToAbsent) {
    return ThumbnailsTableCompanion(
      clipId: Value(clipId),
      localPath: Value(localPath),
    );
  }

  factory ThumbnailsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ThumbnailsTableData(
      clipId: serializer.fromJson<String>(json['clipId']),
      localPath: serializer.fromJson<String>(json['localPath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clipId': serializer.toJson<String>(clipId),
      'localPath': serializer.toJson<String>(localPath),
    };
  }

  ThumbnailsTableData copyWith({String? clipId, String? localPath}) =>
      ThumbnailsTableData(
        clipId: clipId ?? this.clipId,
        localPath: localPath ?? this.localPath,
      );
  ThumbnailsTableData copyWithCompanion(ThumbnailsTableCompanion data) {
    return ThumbnailsTableData(
      clipId: data.clipId.present ? data.clipId.value : this.clipId,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ThumbnailsTableData(')
          ..write('clipId: $clipId, ')
          ..write('localPath: $localPath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(clipId, localPath);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ThumbnailsTableData &&
          other.clipId == this.clipId &&
          other.localPath == this.localPath);
}

class ThumbnailsTableCompanion extends UpdateCompanion<ThumbnailsTableData> {
  final Value<String> clipId;
  final Value<String> localPath;
  final Value<int> rowid;
  const ThumbnailsTableCompanion({
    this.clipId = const Value.absent(),
    this.localPath = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ThumbnailsTableCompanion.insert({
    required String clipId,
    required String localPath,
    this.rowid = const Value.absent(),
  }) : clipId = Value(clipId),
       localPath = Value(localPath);
  static Insertable<ThumbnailsTableData> custom({
    Expression<String>? clipId,
    Expression<String>? localPath,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clipId != null) 'clip_id': clipId,
      if (localPath != null) 'local_path': localPath,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ThumbnailsTableCompanion copyWith({
    Value<String>? clipId,
    Value<String>? localPath,
    Value<int>? rowid,
  }) {
    return ThumbnailsTableCompanion(
      clipId: clipId ?? this.clipId,
      localPath: localPath ?? this.localPath,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clipId.present) {
      map['clip_id'] = Variable<String>(clipId.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ThumbnailsTableCompanion(')
          ..write('clipId: $clipId, ')
          ..write('localPath: $localPath, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RawRecordingsTableTable extends RawRecordingsTable
    with TableInfo<$RawRecordingsTableTable, RawRecordingsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RawRecordingsTableTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> captureGroupId = GeneratedColumn<String>(
    'capture_group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> cameraIndex = GeneratedColumn<int>(
    'camera_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> matchId = GeneratedColumn<String>(
    'match_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES team_matches (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumn<bool> isRaw = GeneratedColumn<bool>(
    'is_raw',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_raw" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  late final GeneratedColumn<bool> isComplete = GeneratedColumn<bool>(
    'is_complete',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_complete" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumn<String> startedAt = GeneratedColumn<String>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    captureGroupId,
    cameraIndex,
    matchId,
    localPath,
    sizeBytes,
    isRaw,
    isComplete,
    startedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'raw_recordings';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RawRecordingsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RawRecordingsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      captureGroupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}capture_group_id'],
      )!,
      cameraIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}camera_index'],
      )!,
      matchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}match_id'],
      ),
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      ),
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      isRaw: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_raw'],
      )!,
      isComplete: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_complete'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}started_at'],
      )!,
    );
  }

  @override
  $RawRecordingsTableTable createAlias(String alias) {
    return $RawRecordingsTableTable(attachedDatabase, alias);
  }
}

class RawRecordingsTableData extends DataClass
    implements Insertable<RawRecordingsTableData> {
  /// Stable local id (e.g. the firmware recording_id / file stem).
  final String id;

  /// App-minted id shared by both per-camera files of one raw session.
  final String captureGroupId;

  /// Physical sensor index (0 = primary, 1 = secondary).
  final int cameraIndex;

  /// Optional association to a match; cascades on match delete.
  final String? matchId;

  /// On-disk path of the downloaded file (mirrors clips/thumbnails).
  final String? localPath;
  final int sizeBytes;

  /// Always true for rows in this table; kept explicit so the column mirrors the
  /// contract field and a future non-raw use can't silently reinterpret rows.
  final bool isRaw;

  /// Whether both files of the pair downloaded successfully. A recovered single
  /// file is marked incomplete rather than saved as if whole.
  final bool isComplete;
  final String startedAt;
  const RawRecordingsTableData({
    required this.id,
    required this.captureGroupId,
    required this.cameraIndex,
    this.matchId,
    this.localPath,
    required this.sizeBytes,
    required this.isRaw,
    required this.isComplete,
    required this.startedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['capture_group_id'] = Variable<String>(captureGroupId);
    map['camera_index'] = Variable<int>(cameraIndex);
    if (!nullToAbsent || matchId != null) {
      map['match_id'] = Variable<String>(matchId);
    }
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['is_raw'] = Variable<bool>(isRaw);
    map['is_complete'] = Variable<bool>(isComplete);
    map['started_at'] = Variable<String>(startedAt);
    return map;
  }

  RawRecordingsTableCompanion toCompanion(bool nullToAbsent) {
    return RawRecordingsTableCompanion(
      id: Value(id),
      captureGroupId: Value(captureGroupId),
      cameraIndex: Value(cameraIndex),
      matchId: matchId == null && nullToAbsent
          ? const Value.absent()
          : Value(matchId),
      localPath: localPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPath),
      sizeBytes: Value(sizeBytes),
      isRaw: Value(isRaw),
      isComplete: Value(isComplete),
      startedAt: Value(startedAt),
    );
  }

  factory RawRecordingsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RawRecordingsTableData(
      id: serializer.fromJson<String>(json['id']),
      captureGroupId: serializer.fromJson<String>(json['captureGroupId']),
      cameraIndex: serializer.fromJson<int>(json['cameraIndex']),
      matchId: serializer.fromJson<String?>(json['matchId']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      isRaw: serializer.fromJson<bool>(json['isRaw']),
      isComplete: serializer.fromJson<bool>(json['isComplete']),
      startedAt: serializer.fromJson<String>(json['startedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'captureGroupId': serializer.toJson<String>(captureGroupId),
      'cameraIndex': serializer.toJson<int>(cameraIndex),
      'matchId': serializer.toJson<String?>(matchId),
      'localPath': serializer.toJson<String?>(localPath),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'isRaw': serializer.toJson<bool>(isRaw),
      'isComplete': serializer.toJson<bool>(isComplete),
      'startedAt': serializer.toJson<String>(startedAt),
    };
  }

  RawRecordingsTableData copyWith({
    String? id,
    String? captureGroupId,
    int? cameraIndex,
    Value<String?> matchId = const Value.absent(),
    Value<String?> localPath = const Value.absent(),
    int? sizeBytes,
    bool? isRaw,
    bool? isComplete,
    String? startedAt,
  }) => RawRecordingsTableData(
    id: id ?? this.id,
    captureGroupId: captureGroupId ?? this.captureGroupId,
    cameraIndex: cameraIndex ?? this.cameraIndex,
    matchId: matchId.present ? matchId.value : this.matchId,
    localPath: localPath.present ? localPath.value : this.localPath,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    isRaw: isRaw ?? this.isRaw,
    isComplete: isComplete ?? this.isComplete,
    startedAt: startedAt ?? this.startedAt,
  );
  RawRecordingsTableData copyWithCompanion(RawRecordingsTableCompanion data) {
    return RawRecordingsTableData(
      id: data.id.present ? data.id.value : this.id,
      captureGroupId: data.captureGroupId.present
          ? data.captureGroupId.value
          : this.captureGroupId,
      cameraIndex: data.cameraIndex.present
          ? data.cameraIndex.value
          : this.cameraIndex,
      matchId: data.matchId.present ? data.matchId.value : this.matchId,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      isRaw: data.isRaw.present ? data.isRaw.value : this.isRaw,
      isComplete: data.isComplete.present
          ? data.isComplete.value
          : this.isComplete,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RawRecordingsTableData(')
          ..write('id: $id, ')
          ..write('captureGroupId: $captureGroupId, ')
          ..write('cameraIndex: $cameraIndex, ')
          ..write('matchId: $matchId, ')
          ..write('localPath: $localPath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('isRaw: $isRaw, ')
          ..write('isComplete: $isComplete, ')
          ..write('startedAt: $startedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    captureGroupId,
    cameraIndex,
    matchId,
    localPath,
    sizeBytes,
    isRaw,
    isComplete,
    startedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RawRecordingsTableData &&
          other.id == this.id &&
          other.captureGroupId == this.captureGroupId &&
          other.cameraIndex == this.cameraIndex &&
          other.matchId == this.matchId &&
          other.localPath == this.localPath &&
          other.sizeBytes == this.sizeBytes &&
          other.isRaw == this.isRaw &&
          other.isComplete == this.isComplete &&
          other.startedAt == this.startedAt);
}

class RawRecordingsTableCompanion
    extends UpdateCompanion<RawRecordingsTableData> {
  final Value<String> id;
  final Value<String> captureGroupId;
  final Value<int> cameraIndex;
  final Value<String?> matchId;
  final Value<String?> localPath;
  final Value<int> sizeBytes;
  final Value<bool> isRaw;
  final Value<bool> isComplete;
  final Value<String> startedAt;
  final Value<int> rowid;
  const RawRecordingsTableCompanion({
    this.id = const Value.absent(),
    this.captureGroupId = const Value.absent(),
    this.cameraIndex = const Value.absent(),
    this.matchId = const Value.absent(),
    this.localPath = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.isRaw = const Value.absent(),
    this.isComplete = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RawRecordingsTableCompanion.insert({
    required String id,
    required String captureGroupId,
    required int cameraIndex,
    this.matchId = const Value.absent(),
    this.localPath = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.isRaw = const Value.absent(),
    this.isComplete = const Value.absent(),
    required String startedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       captureGroupId = Value(captureGroupId),
       cameraIndex = Value(cameraIndex),
       startedAt = Value(startedAt);
  static Insertable<RawRecordingsTableData> custom({
    Expression<String>? id,
    Expression<String>? captureGroupId,
    Expression<int>? cameraIndex,
    Expression<String>? matchId,
    Expression<String>? localPath,
    Expression<int>? sizeBytes,
    Expression<bool>? isRaw,
    Expression<bool>? isComplete,
    Expression<String>? startedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (captureGroupId != null) 'capture_group_id': captureGroupId,
      if (cameraIndex != null) 'camera_index': cameraIndex,
      if (matchId != null) 'match_id': matchId,
      if (localPath != null) 'local_path': localPath,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (isRaw != null) 'is_raw': isRaw,
      if (isComplete != null) 'is_complete': isComplete,
      if (startedAt != null) 'started_at': startedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RawRecordingsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? captureGroupId,
    Value<int>? cameraIndex,
    Value<String?>? matchId,
    Value<String?>? localPath,
    Value<int>? sizeBytes,
    Value<bool>? isRaw,
    Value<bool>? isComplete,
    Value<String>? startedAt,
    Value<int>? rowid,
  }) {
    return RawRecordingsTableCompanion(
      id: id ?? this.id,
      captureGroupId: captureGroupId ?? this.captureGroupId,
      cameraIndex: cameraIndex ?? this.cameraIndex,
      matchId: matchId ?? this.matchId,
      localPath: localPath ?? this.localPath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      isRaw: isRaw ?? this.isRaw,
      isComplete: isComplete ?? this.isComplete,
      startedAt: startedAt ?? this.startedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (captureGroupId.present) {
      map['capture_group_id'] = Variable<String>(captureGroupId.value);
    }
    if (cameraIndex.present) {
      map['camera_index'] = Variable<int>(cameraIndex.value);
    }
    if (matchId.present) {
      map['match_id'] = Variable<String>(matchId.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (isRaw.present) {
      map['is_raw'] = Variable<bool>(isRaw.value);
    }
    if (isComplete.present) {
      map['is_complete'] = Variable<bool>(isComplete.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<String>(startedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RawRecordingsTableCompanion(')
          ..write('id: $id, ')
          ..write('captureGroupId: $captureGroupId, ')
          ..write('cameraIndex: $cameraIndex, ')
          ..write('matchId: $matchId, ')
          ..write('localPath: $localPath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('isRaw: $isRaw, ')
          ..write('isComplete: $isComplete, ')
          ..write('startedAt: $startedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $UsersTableTable usersTable = $UsersTableTable(this);
  late final $TeamsTableTable teamsTable = $TeamsTableTable(this);
  late final $PlayersTableTable playersTable = $PlayersTableTable(this);
  late final $TeamMatchesTableTable teamMatchesTable = $TeamMatchesTableTable(
    this,
  );
  late final $SportPresetsTableTable sportPresetsTable =
      $SportPresetsTableTable(this);
  late final $StreamingDestinationsTableTable streamingDestinationsTable =
      $StreamingDestinationsTableTable(this);
  late final $ClipsTableTable clipsTable = $ClipsTableTable(this);
  late final $ThumbnailsTableTable thumbnailsTable = $ThumbnailsTableTable(
    this,
  );
  late final $RawRecordingsTableTable rawRecordingsTable =
      $RawRecordingsTableTable(this);
  late final UsersDao usersDao = UsersDao(this as AppDatabase);
  late final TeamsDao teamsDao = TeamsDao(this as AppDatabase);
  late final SportPresetsDao sportPresetsDao = SportPresetsDao(
    this as AppDatabase,
  );
  late final StreamingDestinationsDao streamingDestinationsDao =
      StreamingDestinationsDao(this as AppDatabase);
  late final ClipsDao clipsDao = ClipsDao(this as AppDatabase);
  late final RawRecordingsDao rawRecordingsDao = RawRecordingsDao(
    this as AppDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    usersTable,
    teamsTable,
    playersTable,
    teamMatchesTable,
    sportPresetsTable,
    streamingDestinationsTable,
    clipsTable,
    thumbnailsTable,
    rawRecordingsTable,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'users',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('teams', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'teams',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('players', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'teams',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('team_matches', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'users',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('sport_presets', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'users',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('streaming_destinations', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'team_matches',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('clips', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'clips',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('thumbnails', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'team_matches',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('raw_recordings', kind: UpdateKind.delete)],
    ),
  ]);
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$UsersTableTableCreateCompanionBuilder =
    UsersTableCompanion Function({
      required String id,
      required String name,
      Value<int> rowid,
    });
typedef $$UsersTableTableUpdateCompanionBuilder =
    UsersTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> rowid,
    });

final class $$UsersTableTableReferences
    extends BaseReferences<_$AppDatabase, $UsersTableTable, UsersTableData> {
  $$UsersTableTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TeamsTableTable, List<TeamsTableData>>
  _teamsTableRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.teamsTable,
    aliasName: $_aliasNameGenerator(db.usersTable.id, db.teamsTable.userId),
  );

  $$TeamsTableTableProcessedTableManager get teamsTableRefs {
    final manager = $$TeamsTableTableTableManager(
      $_db,
      $_db.teamsTable,
    ).filter((f) => f.userId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_teamsTableRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $SportPresetsTableTable,
    List<SportPresetsTableData>
  >
  _sportPresetsTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.sportPresetsTable,
        aliasName: $_aliasNameGenerator(
          db.usersTable.id,
          db.sportPresetsTable.userId,
        ),
      );

  $$SportPresetsTableTableProcessedTableManager get sportPresetsTableRefs {
    final manager = $$SportPresetsTableTableTableManager(
      $_db,
      $_db.sportPresetsTable,
    ).filter((f) => f.userId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _sportPresetsTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $StreamingDestinationsTableTable,
    List<StreamingDestinationsTableData>
  >
  _streamingDestinationsTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.streamingDestinationsTable,
        aliasName: $_aliasNameGenerator(
          db.usersTable.id,
          db.streamingDestinationsTable.userId,
        ),
      );

  $$StreamingDestinationsTableTableProcessedTableManager
  get streamingDestinationsTableRefs {
    final manager = $$StreamingDestinationsTableTableTableManager(
      $_db,
      $_db.streamingDestinationsTable,
    ).filter((f) => f.userId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _streamingDestinationsTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$UsersTableTableFilterComposer
    extends Composer<_$AppDatabase, $UsersTableTable> {
  $$UsersTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> teamsTableRefs(
    Expression<bool> Function($$TeamsTableTableFilterComposer f) f,
  ) {
    final $$TeamsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.teamsTable,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeamsTableTableFilterComposer(
            $db: $db,
            $table: $db.teamsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> sportPresetsTableRefs(
    Expression<bool> Function($$SportPresetsTableTableFilterComposer f) f,
  ) {
    final $$SportPresetsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sportPresetsTable,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SportPresetsTableTableFilterComposer(
            $db: $db,
            $table: $db.sportPresetsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> streamingDestinationsTableRefs(
    Expression<bool> Function($$StreamingDestinationsTableTableFilterComposer f)
    f,
  ) {
    final $$StreamingDestinationsTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.streamingDestinationsTable,
          getReferencedColumn: (t) => t.userId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$StreamingDestinationsTableTableFilterComposer(
                $db: $db,
                $table: $db.streamingDestinationsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$UsersTableTableOrderingComposer
    extends Composer<_$AppDatabase, $UsersTableTable> {
  $$UsersTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UsersTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $UsersTableTable> {
  $$UsersTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  Expression<T> teamsTableRefs<T extends Object>(
    Expression<T> Function($$TeamsTableTableAnnotationComposer a) f,
  ) {
    final $$TeamsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.teamsTable,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeamsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.teamsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> sportPresetsTableRefs<T extends Object>(
    Expression<T> Function($$SportPresetsTableTableAnnotationComposer a) f,
  ) {
    final $$SportPresetsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.sportPresetsTable,
          getReferencedColumn: (t) => t.userId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SportPresetsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.sportPresetsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> streamingDestinationsTableRefs<T extends Object>(
    Expression<T> Function(
      $$StreamingDestinationsTableTableAnnotationComposer a,
    )
    f,
  ) {
    final $$StreamingDestinationsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.streamingDestinationsTable,
          getReferencedColumn: (t) => t.userId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$StreamingDestinationsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.streamingDestinationsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$UsersTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UsersTableTable,
          UsersTableData,
          $$UsersTableTableFilterComposer,
          $$UsersTableTableOrderingComposer,
          $$UsersTableTableAnnotationComposer,
          $$UsersTableTableCreateCompanionBuilder,
          $$UsersTableTableUpdateCompanionBuilder,
          (UsersTableData, $$UsersTableTableReferences),
          UsersTableData,
          PrefetchHooks Function({
            bool teamsTableRefs,
            bool sportPresetsTableRefs,
            bool streamingDestinationsTableRefs,
          })
        > {
  $$UsersTableTableTableManager(_$AppDatabase db, $UsersTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UsersTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UsersTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UsersTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsersTableCompanion(id: id, name: name, rowid: rowid),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> rowid = const Value.absent(),
              }) =>
                  UsersTableCompanion.insert(id: id, name: name, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$UsersTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                teamsTableRefs = false,
                sportPresetsTableRefs = false,
                streamingDestinationsTableRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (teamsTableRefs) db.teamsTable,
                    if (sportPresetsTableRefs) db.sportPresetsTable,
                    if (streamingDestinationsTableRefs)
                      db.streamingDestinationsTable,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (teamsTableRefs)
                        await $_getPrefetchedData<
                          UsersTableData,
                          $UsersTableTable,
                          TeamsTableData
                        >(
                          currentTable: table,
                          referencedTable: $$UsersTableTableReferences
                              ._teamsTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UsersTableTableReferences(
                                db,
                                table,
                                p0,
                              ).teamsTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (sportPresetsTableRefs)
                        await $_getPrefetchedData<
                          UsersTableData,
                          $UsersTableTable,
                          SportPresetsTableData
                        >(
                          currentTable: table,
                          referencedTable: $$UsersTableTableReferences
                              ._sportPresetsTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UsersTableTableReferences(
                                db,
                                table,
                                p0,
                              ).sportPresetsTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (streamingDestinationsTableRefs)
                        await $_getPrefetchedData<
                          UsersTableData,
                          $UsersTableTable,
                          StreamingDestinationsTableData
                        >(
                          currentTable: table,
                          referencedTable: $$UsersTableTableReferences
                              ._streamingDestinationsTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UsersTableTableReferences(
                                db,
                                table,
                                p0,
                              ).streamingDestinationsTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$UsersTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UsersTableTable,
      UsersTableData,
      $$UsersTableTableFilterComposer,
      $$UsersTableTableOrderingComposer,
      $$UsersTableTableAnnotationComposer,
      $$UsersTableTableCreateCompanionBuilder,
      $$UsersTableTableUpdateCompanionBuilder,
      (UsersTableData, $$UsersTableTableReferences),
      UsersTableData,
      PrefetchHooks Function({
        bool teamsTableRefs,
        bool sportPresetsTableRefs,
        bool streamingDestinationsTableRefs,
      })
    >;
typedef $$TeamsTableTableCreateCompanionBuilder =
    TeamsTableCompanion Function({
      required String id,
      required String userId,
      required String name,
      required String shortName,
      required String sport,
      Value<String?> colorHex,
      Value<bool> hidden,
      Value<int> rowid,
    });
typedef $$TeamsTableTableUpdateCompanionBuilder =
    TeamsTableCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> name,
      Value<String> shortName,
      Value<String> sport,
      Value<String?> colorHex,
      Value<bool> hidden,
      Value<int> rowid,
    });

final class $$TeamsTableTableReferences
    extends BaseReferences<_$AppDatabase, $TeamsTableTable, TeamsTableData> {
  $$TeamsTableTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $UsersTableTable _userIdTable(_$AppDatabase db) =>
      db.usersTable.createAlias(
        $_aliasNameGenerator(db.teamsTable.userId, db.usersTable.id),
      );

  $$UsersTableTableProcessedTableManager get userId {
    final $_column = $_itemColumn<String>('user_id')!;

    final manager = $$UsersTableTableTableManager(
      $_db,
      $_db.usersTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_userIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$PlayersTableTable, List<PlayersTableData>>
  _playersTableRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.playersTable,
    aliasName: $_aliasNameGenerator(db.teamsTable.id, db.playersTable.teamId),
  );

  $$PlayersTableTableProcessedTableManager get playersTableRefs {
    final manager = $$PlayersTableTableTableManager(
      $_db,
      $_db.playersTable,
    ).filter((f) => f.teamId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_playersTableRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TeamMatchesTableTable, List<TeamMatchesTableData>>
  _teamMatchesTableRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.teamMatchesTable,
    aliasName: $_aliasNameGenerator(
      db.teamsTable.id,
      db.teamMatchesTable.teamId,
    ),
  );

  $$TeamMatchesTableTableProcessedTableManager get teamMatchesTableRefs {
    final manager = $$TeamMatchesTableTableTableManager(
      $_db,
      $_db.teamMatchesTable,
    ).filter((f) => f.teamId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _teamMatchesTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TeamsTableTableFilterComposer
    extends Composer<_$AppDatabase, $TeamsTableTable> {
  $$TeamsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shortName => $composableBuilder(
    column: $table.shortName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sport => $composableBuilder(
    column: $table.sport,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorHex => $composableBuilder(
    column: $table.colorHex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hidden => $composableBuilder(
    column: $table.hidden,
    builder: (column) => ColumnFilters(column),
  );

  $$UsersTableTableFilterComposer get userId {
    final $$UsersTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.usersTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableTableFilterComposer(
            $db: $db,
            $table: $db.usersTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> playersTableRefs(
    Expression<bool> Function($$PlayersTableTableFilterComposer f) f,
  ) {
    final $$PlayersTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.playersTable,
      getReferencedColumn: (t) => t.teamId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlayersTableTableFilterComposer(
            $db: $db,
            $table: $db.playersTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> teamMatchesTableRefs(
    Expression<bool> Function($$TeamMatchesTableTableFilterComposer f) f,
  ) {
    final $$TeamMatchesTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.teamMatchesTable,
      getReferencedColumn: (t) => t.teamId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeamMatchesTableTableFilterComposer(
            $db: $db,
            $table: $db.teamMatchesTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TeamsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $TeamsTableTable> {
  $$TeamsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shortName => $composableBuilder(
    column: $table.shortName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sport => $composableBuilder(
    column: $table.sport,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorHex => $composableBuilder(
    column: $table.colorHex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hidden => $composableBuilder(
    column: $table.hidden,
    builder: (column) => ColumnOrderings(column),
  );

  $$UsersTableTableOrderingComposer get userId {
    final $$UsersTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.usersTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableTableOrderingComposer(
            $db: $db,
            $table: $db.usersTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TeamsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $TeamsTableTable> {
  $$TeamsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get shortName =>
      $composableBuilder(column: $table.shortName, builder: (column) => column);

  GeneratedColumn<String> get sport =>
      $composableBuilder(column: $table.sport, builder: (column) => column);

  GeneratedColumn<String> get colorHex =>
      $composableBuilder(column: $table.colorHex, builder: (column) => column);

  GeneratedColumn<bool> get hidden =>
      $composableBuilder(column: $table.hidden, builder: (column) => column);

  $$UsersTableTableAnnotationComposer get userId {
    final $$UsersTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.usersTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableTableAnnotationComposer(
            $db: $db,
            $table: $db.usersTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> playersTableRefs<T extends Object>(
    Expression<T> Function($$PlayersTableTableAnnotationComposer a) f,
  ) {
    final $$PlayersTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.playersTable,
      getReferencedColumn: (t) => t.teamId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlayersTableTableAnnotationComposer(
            $db: $db,
            $table: $db.playersTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> teamMatchesTableRefs<T extends Object>(
    Expression<T> Function($$TeamMatchesTableTableAnnotationComposer a) f,
  ) {
    final $$TeamMatchesTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.teamMatchesTable,
      getReferencedColumn: (t) => t.teamId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeamMatchesTableTableAnnotationComposer(
            $db: $db,
            $table: $db.teamMatchesTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TeamsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TeamsTableTable,
          TeamsTableData,
          $$TeamsTableTableFilterComposer,
          $$TeamsTableTableOrderingComposer,
          $$TeamsTableTableAnnotationComposer,
          $$TeamsTableTableCreateCompanionBuilder,
          $$TeamsTableTableUpdateCompanionBuilder,
          (TeamsTableData, $$TeamsTableTableReferences),
          TeamsTableData,
          PrefetchHooks Function({
            bool userId,
            bool playersTableRefs,
            bool teamMatchesTableRefs,
          })
        > {
  $$TeamsTableTableTableManager(_$AppDatabase db, $TeamsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TeamsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TeamsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TeamsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> shortName = const Value.absent(),
                Value<String> sport = const Value.absent(),
                Value<String?> colorHex = const Value.absent(),
                Value<bool> hidden = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TeamsTableCompanion(
                id: id,
                userId: userId,
                name: name,
                shortName: shortName,
                sport: sport,
                colorHex: colorHex,
                hidden: hidden,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String name,
                required String shortName,
                required String sport,
                Value<String?> colorHex = const Value.absent(),
                Value<bool> hidden = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TeamsTableCompanion.insert(
                id: id,
                userId: userId,
                name: name,
                shortName: shortName,
                sport: sport,
                colorHex: colorHex,
                hidden: hidden,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TeamsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                userId = false,
                playersTableRefs = false,
                teamMatchesTableRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (playersTableRefs) db.playersTable,
                    if (teamMatchesTableRefs) db.teamMatchesTable,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (userId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.userId,
                                    referencedTable: $$TeamsTableTableReferences
                                        ._userIdTable(db),
                                    referencedColumn:
                                        $$TeamsTableTableReferences
                                            ._userIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (playersTableRefs)
                        await $_getPrefetchedData<
                          TeamsTableData,
                          $TeamsTableTable,
                          PlayersTableData
                        >(
                          currentTable: table,
                          referencedTable: $$TeamsTableTableReferences
                              ._playersTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TeamsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).playersTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.teamId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (teamMatchesTableRefs)
                        await $_getPrefetchedData<
                          TeamsTableData,
                          $TeamsTableTable,
                          TeamMatchesTableData
                        >(
                          currentTable: table,
                          referencedTable: $$TeamsTableTableReferences
                              ._teamMatchesTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TeamsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).teamMatchesTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.teamId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$TeamsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TeamsTableTable,
      TeamsTableData,
      $$TeamsTableTableFilterComposer,
      $$TeamsTableTableOrderingComposer,
      $$TeamsTableTableAnnotationComposer,
      $$TeamsTableTableCreateCompanionBuilder,
      $$TeamsTableTableUpdateCompanionBuilder,
      (TeamsTableData, $$TeamsTableTableReferences),
      TeamsTableData,
      PrefetchHooks Function({
        bool userId,
        bool playersTableRefs,
        bool teamMatchesTableRefs,
      })
    >;
typedef $$PlayersTableTableCreateCompanionBuilder =
    PlayersTableCompanion Function({
      required String teamId,
      required int number,
      required String name,
      required String position,
      Value<bool> captain,
      Value<int> rowid,
    });
typedef $$PlayersTableTableUpdateCompanionBuilder =
    PlayersTableCompanion Function({
      Value<String> teamId,
      Value<int> number,
      Value<String> name,
      Value<String> position,
      Value<bool> captain,
      Value<int> rowid,
    });

final class $$PlayersTableTableReferences
    extends
        BaseReferences<_$AppDatabase, $PlayersTableTable, PlayersTableData> {
  $$PlayersTableTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TeamsTableTable _teamIdTable(_$AppDatabase db) =>
      db.teamsTable.createAlias(
        $_aliasNameGenerator(db.playersTable.teamId, db.teamsTable.id),
      );

  $$TeamsTableTableProcessedTableManager get teamId {
    final $_column = $_itemColumn<String>('team_id')!;

    final manager = $$TeamsTableTableTableManager(
      $_db,
      $_db.teamsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_teamIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PlayersTableTableFilterComposer
    extends Composer<_$AppDatabase, $PlayersTableTable> {
  $$PlayersTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get captain => $composableBuilder(
    column: $table.captain,
    builder: (column) => ColumnFilters(column),
  );

  $$TeamsTableTableFilterComposer get teamId {
    final $$TeamsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.teamId,
      referencedTable: $db.teamsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeamsTableTableFilterComposer(
            $db: $db,
            $table: $db.teamsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlayersTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PlayersTableTable> {
  $$PlayersTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get captain => $composableBuilder(
    column: $table.captain,
    builder: (column) => ColumnOrderings(column),
  );

  $$TeamsTableTableOrderingComposer get teamId {
    final $$TeamsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.teamId,
      referencedTable: $db.teamsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeamsTableTableOrderingComposer(
            $db: $db,
            $table: $db.teamsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlayersTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlayersTableTable> {
  $$PlayersTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<bool> get captain =>
      $composableBuilder(column: $table.captain, builder: (column) => column);

  $$TeamsTableTableAnnotationComposer get teamId {
    final $$TeamsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.teamId,
      referencedTable: $db.teamsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeamsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.teamsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlayersTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlayersTableTable,
          PlayersTableData,
          $$PlayersTableTableFilterComposer,
          $$PlayersTableTableOrderingComposer,
          $$PlayersTableTableAnnotationComposer,
          $$PlayersTableTableCreateCompanionBuilder,
          $$PlayersTableTableUpdateCompanionBuilder,
          (PlayersTableData, $$PlayersTableTableReferences),
          PlayersTableData,
          PrefetchHooks Function({bool teamId})
        > {
  $$PlayersTableTableTableManager(_$AppDatabase db, $PlayersTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlayersTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlayersTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlayersTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> teamId = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> position = const Value.absent(),
                Value<bool> captain = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlayersTableCompanion(
                teamId: teamId,
                number: number,
                name: name,
                position: position,
                captain: captain,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String teamId,
                required int number,
                required String name,
                required String position,
                Value<bool> captain = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlayersTableCompanion.insert(
                teamId: teamId,
                number: number,
                name: name,
                position: position,
                captain: captain,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PlayersTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({teamId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (teamId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.teamId,
                                referencedTable: $$PlayersTableTableReferences
                                    ._teamIdTable(db),
                                referencedColumn: $$PlayersTableTableReferences
                                    ._teamIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PlayersTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlayersTableTable,
      PlayersTableData,
      $$PlayersTableTableFilterComposer,
      $$PlayersTableTableOrderingComposer,
      $$PlayersTableTableAnnotationComposer,
      $$PlayersTableTableCreateCompanionBuilder,
      $$PlayersTableTableUpdateCompanionBuilder,
      (PlayersTableData, $$PlayersTableTableReferences),
      PlayersTableData,
      PrefetchHooks Function({bool teamId})
    >;
typedef $$TeamMatchesTableTableCreateCompanionBuilder =
    TeamMatchesTableCompanion Function({
      required String id,
      required String teamId,
      required String opponent,
      required String date,
      required String result,
      required String kind,
      required int numPeriods,
      required int periodLengthSeconds,
      Value<int> clips,
      Value<int> sizeMb,
      Value<String> eventsJson,
      Value<int> rowid,
    });
typedef $$TeamMatchesTableTableUpdateCompanionBuilder =
    TeamMatchesTableCompanion Function({
      Value<String> id,
      Value<String> teamId,
      Value<String> opponent,
      Value<String> date,
      Value<String> result,
      Value<String> kind,
      Value<int> numPeriods,
      Value<int> periodLengthSeconds,
      Value<int> clips,
      Value<int> sizeMb,
      Value<String> eventsJson,
      Value<int> rowid,
    });

final class $$TeamMatchesTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $TeamMatchesTableTable,
          TeamMatchesTableData
        > {
  $$TeamMatchesTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $TeamsTableTable _teamIdTable(_$AppDatabase db) =>
      db.teamsTable.createAlias(
        $_aliasNameGenerator(db.teamMatchesTable.teamId, db.teamsTable.id),
      );

  $$TeamsTableTableProcessedTableManager get teamId {
    final $_column = $_itemColumn<String>('team_id')!;

    final manager = $$TeamsTableTableTableManager(
      $_db,
      $_db.teamsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_teamIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ClipsTableTable, List<ClipsTableData>>
  _clipsTableRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.clipsTable,
    aliasName: $_aliasNameGenerator(
      db.teamMatchesTable.id,
      db.clipsTable.matchId,
    ),
  );

  $$ClipsTableTableProcessedTableManager get clipsTableRefs {
    final manager = $$ClipsTableTableTableManager(
      $_db,
      $_db.clipsTable,
    ).filter((f) => f.matchId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_clipsTableRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $RawRecordingsTableTable,
    List<RawRecordingsTableData>
  >
  _rawRecordingsTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.rawRecordingsTable,
        aliasName: $_aliasNameGenerator(
          db.teamMatchesTable.id,
          db.rawRecordingsTable.matchId,
        ),
      );

  $$RawRecordingsTableTableProcessedTableManager get rawRecordingsTableRefs {
    final manager = $$RawRecordingsTableTableTableManager(
      $_db,
      $_db.rawRecordingsTable,
    ).filter((f) => f.matchId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _rawRecordingsTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TeamMatchesTableTableFilterComposer
    extends Composer<_$AppDatabase, $TeamMatchesTableTable> {
  $$TeamMatchesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get opponent => $composableBuilder(
    column: $table.opponent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get result => $composableBuilder(
    column: $table.result,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get numPeriods => $composableBuilder(
    column: $table.numPeriods,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get periodLengthSeconds => $composableBuilder(
    column: $table.periodLengthSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get clips => $composableBuilder(
    column: $table.clips,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeMb => $composableBuilder(
    column: $table.sizeMb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventsJson => $composableBuilder(
    column: $table.eventsJson,
    builder: (column) => ColumnFilters(column),
  );

  $$TeamsTableTableFilterComposer get teamId {
    final $$TeamsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.teamId,
      referencedTable: $db.teamsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeamsTableTableFilterComposer(
            $db: $db,
            $table: $db.teamsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> clipsTableRefs(
    Expression<bool> Function($$ClipsTableTableFilterComposer f) f,
  ) {
    final $$ClipsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.clipsTable,
      getReferencedColumn: (t) => t.matchId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClipsTableTableFilterComposer(
            $db: $db,
            $table: $db.clipsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> rawRecordingsTableRefs(
    Expression<bool> Function($$RawRecordingsTableTableFilterComposer f) f,
  ) {
    final $$RawRecordingsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.rawRecordingsTable,
      getReferencedColumn: (t) => t.matchId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RawRecordingsTableTableFilterComposer(
            $db: $db,
            $table: $db.rawRecordingsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TeamMatchesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $TeamMatchesTableTable> {
  $$TeamMatchesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get opponent => $composableBuilder(
    column: $table.opponent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get result => $composableBuilder(
    column: $table.result,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get numPeriods => $composableBuilder(
    column: $table.numPeriods,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get periodLengthSeconds => $composableBuilder(
    column: $table.periodLengthSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get clips => $composableBuilder(
    column: $table.clips,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeMb => $composableBuilder(
    column: $table.sizeMb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventsJson => $composableBuilder(
    column: $table.eventsJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$TeamsTableTableOrderingComposer get teamId {
    final $$TeamsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.teamId,
      referencedTable: $db.teamsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeamsTableTableOrderingComposer(
            $db: $db,
            $table: $db.teamsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TeamMatchesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $TeamMatchesTableTable> {
  $$TeamMatchesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get opponent =>
      $composableBuilder(column: $table.opponent, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get result =>
      $composableBuilder(column: $table.result, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get numPeriods => $composableBuilder(
    column: $table.numPeriods,
    builder: (column) => column,
  );

  GeneratedColumn<int> get periodLengthSeconds => $composableBuilder(
    column: $table.periodLengthSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get clips =>
      $composableBuilder(column: $table.clips, builder: (column) => column);

  GeneratedColumn<int> get sizeMb =>
      $composableBuilder(column: $table.sizeMb, builder: (column) => column);

  GeneratedColumn<String> get eventsJson => $composableBuilder(
    column: $table.eventsJson,
    builder: (column) => column,
  );

  $$TeamsTableTableAnnotationComposer get teamId {
    final $$TeamsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.teamId,
      referencedTable: $db.teamsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeamsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.teamsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> clipsTableRefs<T extends Object>(
    Expression<T> Function($$ClipsTableTableAnnotationComposer a) f,
  ) {
    final $$ClipsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.clipsTable,
      getReferencedColumn: (t) => t.matchId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClipsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.clipsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> rawRecordingsTableRefs<T extends Object>(
    Expression<T> Function($$RawRecordingsTableTableAnnotationComposer a) f,
  ) {
    final $$RawRecordingsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.rawRecordingsTable,
          getReferencedColumn: (t) => t.matchId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RawRecordingsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.rawRecordingsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$TeamMatchesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TeamMatchesTableTable,
          TeamMatchesTableData,
          $$TeamMatchesTableTableFilterComposer,
          $$TeamMatchesTableTableOrderingComposer,
          $$TeamMatchesTableTableAnnotationComposer,
          $$TeamMatchesTableTableCreateCompanionBuilder,
          $$TeamMatchesTableTableUpdateCompanionBuilder,
          (TeamMatchesTableData, $$TeamMatchesTableTableReferences),
          TeamMatchesTableData,
          PrefetchHooks Function({
            bool teamId,
            bool clipsTableRefs,
            bool rawRecordingsTableRefs,
          })
        > {
  $$TeamMatchesTableTableTableManager(
    _$AppDatabase db,
    $TeamMatchesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TeamMatchesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TeamMatchesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TeamMatchesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> teamId = const Value.absent(),
                Value<String> opponent = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<String> result = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> numPeriods = const Value.absent(),
                Value<int> periodLengthSeconds = const Value.absent(),
                Value<int> clips = const Value.absent(),
                Value<int> sizeMb = const Value.absent(),
                Value<String> eventsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TeamMatchesTableCompanion(
                id: id,
                teamId: teamId,
                opponent: opponent,
                date: date,
                result: result,
                kind: kind,
                numPeriods: numPeriods,
                periodLengthSeconds: periodLengthSeconds,
                clips: clips,
                sizeMb: sizeMb,
                eventsJson: eventsJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String teamId,
                required String opponent,
                required String date,
                required String result,
                required String kind,
                required int numPeriods,
                required int periodLengthSeconds,
                Value<int> clips = const Value.absent(),
                Value<int> sizeMb = const Value.absent(),
                Value<String> eventsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TeamMatchesTableCompanion.insert(
                id: id,
                teamId: teamId,
                opponent: opponent,
                date: date,
                result: result,
                kind: kind,
                numPeriods: numPeriods,
                periodLengthSeconds: periodLengthSeconds,
                clips: clips,
                sizeMb: sizeMb,
                eventsJson: eventsJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TeamMatchesTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                teamId = false,
                clipsTableRefs = false,
                rawRecordingsTableRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (clipsTableRefs) db.clipsTable,
                    if (rawRecordingsTableRefs) db.rawRecordingsTable,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (teamId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.teamId,
                                    referencedTable:
                                        $$TeamMatchesTableTableReferences
                                            ._teamIdTable(db),
                                    referencedColumn:
                                        $$TeamMatchesTableTableReferences
                                            ._teamIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (clipsTableRefs)
                        await $_getPrefetchedData<
                          TeamMatchesTableData,
                          $TeamMatchesTableTable,
                          ClipsTableData
                        >(
                          currentTable: table,
                          referencedTable: $$TeamMatchesTableTableReferences
                              ._clipsTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TeamMatchesTableTableReferences(
                                db,
                                table,
                                p0,
                              ).clipsTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.matchId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (rawRecordingsTableRefs)
                        await $_getPrefetchedData<
                          TeamMatchesTableData,
                          $TeamMatchesTableTable,
                          RawRecordingsTableData
                        >(
                          currentTable: table,
                          referencedTable: $$TeamMatchesTableTableReferences
                              ._rawRecordingsTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TeamMatchesTableTableReferences(
                                db,
                                table,
                                p0,
                              ).rawRecordingsTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.matchId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$TeamMatchesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TeamMatchesTableTable,
      TeamMatchesTableData,
      $$TeamMatchesTableTableFilterComposer,
      $$TeamMatchesTableTableOrderingComposer,
      $$TeamMatchesTableTableAnnotationComposer,
      $$TeamMatchesTableTableCreateCompanionBuilder,
      $$TeamMatchesTableTableUpdateCompanionBuilder,
      (TeamMatchesTableData, $$TeamMatchesTableTableReferences),
      TeamMatchesTableData,
      PrefetchHooks Function({
        bool teamId,
        bool clipsTableRefs,
        bool rawRecordingsTableRefs,
      })
    >;
typedef $$SportPresetsTableTableCreateCompanionBuilder =
    SportPresetsTableCompanion Function({
      required String id,
      required String userId,
      required String name,
      required String sport,
      required int numPeriods,
      required int periodLengthSeconds,
      Value<bool> builtIn,
      Value<int> rowid,
    });
typedef $$SportPresetsTableTableUpdateCompanionBuilder =
    SportPresetsTableCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> name,
      Value<String> sport,
      Value<int> numPeriods,
      Value<int> periodLengthSeconds,
      Value<bool> builtIn,
      Value<int> rowid,
    });

final class $$SportPresetsTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $SportPresetsTableTable,
          SportPresetsTableData
        > {
  $$SportPresetsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $UsersTableTable _userIdTable(_$AppDatabase db) =>
      db.usersTable.createAlias(
        $_aliasNameGenerator(db.sportPresetsTable.userId, db.usersTable.id),
      );

  $$UsersTableTableProcessedTableManager get userId {
    final $_column = $_itemColumn<String>('user_id')!;

    final manager = $$UsersTableTableTableManager(
      $_db,
      $_db.usersTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_userIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SportPresetsTableTableFilterComposer
    extends Composer<_$AppDatabase, $SportPresetsTableTable> {
  $$SportPresetsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sport => $composableBuilder(
    column: $table.sport,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get numPeriods => $composableBuilder(
    column: $table.numPeriods,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get periodLengthSeconds => $composableBuilder(
    column: $table.periodLengthSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get builtIn => $composableBuilder(
    column: $table.builtIn,
    builder: (column) => ColumnFilters(column),
  );

  $$UsersTableTableFilterComposer get userId {
    final $$UsersTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.usersTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableTableFilterComposer(
            $db: $db,
            $table: $db.usersTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SportPresetsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $SportPresetsTableTable> {
  $$SportPresetsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sport => $composableBuilder(
    column: $table.sport,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get numPeriods => $composableBuilder(
    column: $table.numPeriods,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get periodLengthSeconds => $composableBuilder(
    column: $table.periodLengthSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get builtIn => $composableBuilder(
    column: $table.builtIn,
    builder: (column) => ColumnOrderings(column),
  );

  $$UsersTableTableOrderingComposer get userId {
    final $$UsersTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.usersTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableTableOrderingComposer(
            $db: $db,
            $table: $db.usersTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SportPresetsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $SportPresetsTableTable> {
  $$SportPresetsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get sport =>
      $composableBuilder(column: $table.sport, builder: (column) => column);

  GeneratedColumn<int> get numPeriods => $composableBuilder(
    column: $table.numPeriods,
    builder: (column) => column,
  );

  GeneratedColumn<int> get periodLengthSeconds => $composableBuilder(
    column: $table.periodLengthSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get builtIn =>
      $composableBuilder(column: $table.builtIn, builder: (column) => column);

  $$UsersTableTableAnnotationComposer get userId {
    final $$UsersTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.usersTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableTableAnnotationComposer(
            $db: $db,
            $table: $db.usersTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SportPresetsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SportPresetsTableTable,
          SportPresetsTableData,
          $$SportPresetsTableTableFilterComposer,
          $$SportPresetsTableTableOrderingComposer,
          $$SportPresetsTableTableAnnotationComposer,
          $$SportPresetsTableTableCreateCompanionBuilder,
          $$SportPresetsTableTableUpdateCompanionBuilder,
          (SportPresetsTableData, $$SportPresetsTableTableReferences),
          SportPresetsTableData,
          PrefetchHooks Function({bool userId})
        > {
  $$SportPresetsTableTableTableManager(
    _$AppDatabase db,
    $SportPresetsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SportPresetsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SportPresetsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SportPresetsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> sport = const Value.absent(),
                Value<int> numPeriods = const Value.absent(),
                Value<int> periodLengthSeconds = const Value.absent(),
                Value<bool> builtIn = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SportPresetsTableCompanion(
                id: id,
                userId: userId,
                name: name,
                sport: sport,
                numPeriods: numPeriods,
                periodLengthSeconds: periodLengthSeconds,
                builtIn: builtIn,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String name,
                required String sport,
                required int numPeriods,
                required int periodLengthSeconds,
                Value<bool> builtIn = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SportPresetsTableCompanion.insert(
                id: id,
                userId: userId,
                name: name,
                sport: sport,
                numPeriods: numPeriods,
                periodLengthSeconds: periodLengthSeconds,
                builtIn: builtIn,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SportPresetsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({userId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (userId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.userId,
                                referencedTable:
                                    $$SportPresetsTableTableReferences
                                        ._userIdTable(db),
                                referencedColumn:
                                    $$SportPresetsTableTableReferences
                                        ._userIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SportPresetsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SportPresetsTableTable,
      SportPresetsTableData,
      $$SportPresetsTableTableFilterComposer,
      $$SportPresetsTableTableOrderingComposer,
      $$SportPresetsTableTableAnnotationComposer,
      $$SportPresetsTableTableCreateCompanionBuilder,
      $$SportPresetsTableTableUpdateCompanionBuilder,
      (SportPresetsTableData, $$SportPresetsTableTableReferences),
      SportPresetsTableData,
      PrefetchHooks Function({bool userId})
    >;
typedef $$StreamingDestinationsTableTableCreateCompanionBuilder =
    StreamingDestinationsTableCompanion Function({
      required String id,
      required String userId,
      required String name,
      required String provider,
      required String protocol,
      required String configType,
      required String configUrl,
      Value<String?> configStreamKey,
      Value<String?> configUsername,
      Value<String?> configPassword,
      Value<int> rowid,
    });
typedef $$StreamingDestinationsTableTableUpdateCompanionBuilder =
    StreamingDestinationsTableCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> name,
      Value<String> provider,
      Value<String> protocol,
      Value<String> configType,
      Value<String> configUrl,
      Value<String?> configStreamKey,
      Value<String?> configUsername,
      Value<String?> configPassword,
      Value<int> rowid,
    });

final class $$StreamingDestinationsTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $StreamingDestinationsTableTable,
          StreamingDestinationsTableData
        > {
  $$StreamingDestinationsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $UsersTableTable _userIdTable(_$AppDatabase db) =>
      db.usersTable.createAlias(
        $_aliasNameGenerator(
          db.streamingDestinationsTable.userId,
          db.usersTable.id,
        ),
      );

  $$UsersTableTableProcessedTableManager get userId {
    final $_column = $_itemColumn<String>('user_id')!;

    final manager = $$UsersTableTableTableManager(
      $_db,
      $_db.usersTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_userIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$StreamingDestinationsTableTableFilterComposer
    extends Composer<_$AppDatabase, $StreamingDestinationsTableTable> {
  $$StreamingDestinationsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get protocol => $composableBuilder(
    column: $table.protocol,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configType => $composableBuilder(
    column: $table.configType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configUrl => $composableBuilder(
    column: $table.configUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configStreamKey => $composableBuilder(
    column: $table.configStreamKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configUsername => $composableBuilder(
    column: $table.configUsername,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configPassword => $composableBuilder(
    column: $table.configPassword,
    builder: (column) => ColumnFilters(column),
  );

  $$UsersTableTableFilterComposer get userId {
    final $$UsersTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.usersTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableTableFilterComposer(
            $db: $db,
            $table: $db.usersTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StreamingDestinationsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $StreamingDestinationsTableTable> {
  $$StreamingDestinationsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get protocol => $composableBuilder(
    column: $table.protocol,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get configType => $composableBuilder(
    column: $table.configType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get configUrl => $composableBuilder(
    column: $table.configUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get configStreamKey => $composableBuilder(
    column: $table.configStreamKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get configUsername => $composableBuilder(
    column: $table.configUsername,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get configPassword => $composableBuilder(
    column: $table.configPassword,
    builder: (column) => ColumnOrderings(column),
  );

  $$UsersTableTableOrderingComposer get userId {
    final $$UsersTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.usersTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableTableOrderingComposer(
            $db: $db,
            $table: $db.usersTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StreamingDestinationsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $StreamingDestinationsTableTable> {
  $$StreamingDestinationsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get protocol =>
      $composableBuilder(column: $table.protocol, builder: (column) => column);

  GeneratedColumn<String> get configType => $composableBuilder(
    column: $table.configType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get configUrl =>
      $composableBuilder(column: $table.configUrl, builder: (column) => column);

  GeneratedColumn<String> get configStreamKey => $composableBuilder(
    column: $table.configStreamKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get configUsername => $composableBuilder(
    column: $table.configUsername,
    builder: (column) => column,
  );

  GeneratedColumn<String> get configPassword => $composableBuilder(
    column: $table.configPassword,
    builder: (column) => column,
  );

  $$UsersTableTableAnnotationComposer get userId {
    final $$UsersTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.usersTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableTableAnnotationComposer(
            $db: $db,
            $table: $db.usersTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StreamingDestinationsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StreamingDestinationsTableTable,
          StreamingDestinationsTableData,
          $$StreamingDestinationsTableTableFilterComposer,
          $$StreamingDestinationsTableTableOrderingComposer,
          $$StreamingDestinationsTableTableAnnotationComposer,
          $$StreamingDestinationsTableTableCreateCompanionBuilder,
          $$StreamingDestinationsTableTableUpdateCompanionBuilder,
          (
            StreamingDestinationsTableData,
            $$StreamingDestinationsTableTableReferences,
          ),
          StreamingDestinationsTableData,
          PrefetchHooks Function({bool userId})
        > {
  $$StreamingDestinationsTableTableTableManager(
    _$AppDatabase db,
    $StreamingDestinationsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StreamingDestinationsTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$StreamingDestinationsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$StreamingDestinationsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> provider = const Value.absent(),
                Value<String> protocol = const Value.absent(),
                Value<String> configType = const Value.absent(),
                Value<String> configUrl = const Value.absent(),
                Value<String?> configStreamKey = const Value.absent(),
                Value<String?> configUsername = const Value.absent(),
                Value<String?> configPassword = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StreamingDestinationsTableCompanion(
                id: id,
                userId: userId,
                name: name,
                provider: provider,
                protocol: protocol,
                configType: configType,
                configUrl: configUrl,
                configStreamKey: configStreamKey,
                configUsername: configUsername,
                configPassword: configPassword,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String name,
                required String provider,
                required String protocol,
                required String configType,
                required String configUrl,
                Value<String?> configStreamKey = const Value.absent(),
                Value<String?> configUsername = const Value.absent(),
                Value<String?> configPassword = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StreamingDestinationsTableCompanion.insert(
                id: id,
                userId: userId,
                name: name,
                provider: provider,
                protocol: protocol,
                configType: configType,
                configUrl: configUrl,
                configStreamKey: configStreamKey,
                configUsername: configUsername,
                configPassword: configPassword,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$StreamingDestinationsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({userId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (userId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.userId,
                                referencedTable:
                                    $$StreamingDestinationsTableTableReferences
                                        ._userIdTable(db),
                                referencedColumn:
                                    $$StreamingDestinationsTableTableReferences
                                        ._userIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$StreamingDestinationsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StreamingDestinationsTableTable,
      StreamingDestinationsTableData,
      $$StreamingDestinationsTableTableFilterComposer,
      $$StreamingDestinationsTableTableOrderingComposer,
      $$StreamingDestinationsTableTableAnnotationComposer,
      $$StreamingDestinationsTableTableCreateCompanionBuilder,
      $$StreamingDestinationsTableTableUpdateCompanionBuilder,
      (
        StreamingDestinationsTableData,
        $$StreamingDestinationsTableTableReferences,
      ),
      StreamingDestinationsTableData,
      PrefetchHooks Function({bool userId})
    >;
typedef $$ClipsTableTableCreateCompanionBuilder =
    ClipsTableCompanion Function({
      required String id,
      required String matchId,
      Value<int> startSeconds,
      required int durationSeconds,
      required int sizeBytes,
      required String startedAt,
      Value<String?> label,
      Value<int> rowid,
    });
typedef $$ClipsTableTableUpdateCompanionBuilder =
    ClipsTableCompanion Function({
      Value<String> id,
      Value<String> matchId,
      Value<int> startSeconds,
      Value<int> durationSeconds,
      Value<int> sizeBytes,
      Value<String> startedAt,
      Value<String?> label,
      Value<int> rowid,
    });

final class $$ClipsTableTableReferences
    extends BaseReferences<_$AppDatabase, $ClipsTableTable, ClipsTableData> {
  $$ClipsTableTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TeamMatchesTableTable _matchIdTable(_$AppDatabase db) =>
      db.teamMatchesTable.createAlias(
        $_aliasNameGenerator(db.clipsTable.matchId, db.teamMatchesTable.id),
      );

  $$TeamMatchesTableTableProcessedTableManager get matchId {
    final $_column = $_itemColumn<String>('match_id')!;

    final manager = $$TeamMatchesTableTableTableManager(
      $_db,
      $_db.teamMatchesTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_matchIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ThumbnailsTableTable, List<ThumbnailsTableData>>
  _thumbnailsTableRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.thumbnailsTable,
    aliasName: $_aliasNameGenerator(
      db.clipsTable.id,
      db.thumbnailsTable.clipId,
    ),
  );

  $$ThumbnailsTableTableProcessedTableManager get thumbnailsTableRefs {
    final manager = $$ThumbnailsTableTableTableManager(
      $_db,
      $_db.thumbnailsTable,
    ).filter((f) => f.clipId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _thumbnailsTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ClipsTableTableFilterComposer
    extends Composer<_$AppDatabase, $ClipsTableTable> {
  $$ClipsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startSeconds => $composableBuilder(
    column: $table.startSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  $$TeamMatchesTableTableFilterComposer get matchId {
    final $$TeamMatchesTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.matchId,
      referencedTable: $db.teamMatchesTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeamMatchesTableTableFilterComposer(
            $db: $db,
            $table: $db.teamMatchesTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> thumbnailsTableRefs(
    Expression<bool> Function($$ThumbnailsTableTableFilterComposer f) f,
  ) {
    final $$ThumbnailsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.thumbnailsTable,
      getReferencedColumn: (t) => t.clipId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ThumbnailsTableTableFilterComposer(
            $db: $db,
            $table: $db.thumbnailsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ClipsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ClipsTableTable> {
  $$ClipsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startSeconds => $composableBuilder(
    column: $table.startSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  $$TeamMatchesTableTableOrderingComposer get matchId {
    final $$TeamMatchesTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.matchId,
      referencedTable: $db.teamMatchesTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeamMatchesTableTableOrderingComposer(
            $db: $db,
            $table: $db.teamMatchesTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ClipsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClipsTableTable> {
  $$ClipsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get startSeconds => $composableBuilder(
    column: $table.startSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  $$TeamMatchesTableTableAnnotationComposer get matchId {
    final $$TeamMatchesTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.matchId,
      referencedTable: $db.teamMatchesTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeamMatchesTableTableAnnotationComposer(
            $db: $db,
            $table: $db.teamMatchesTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> thumbnailsTableRefs<T extends Object>(
    Expression<T> Function($$ThumbnailsTableTableAnnotationComposer a) f,
  ) {
    final $$ThumbnailsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.thumbnailsTable,
      getReferencedColumn: (t) => t.clipId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ThumbnailsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.thumbnailsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ClipsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClipsTableTable,
          ClipsTableData,
          $$ClipsTableTableFilterComposer,
          $$ClipsTableTableOrderingComposer,
          $$ClipsTableTableAnnotationComposer,
          $$ClipsTableTableCreateCompanionBuilder,
          $$ClipsTableTableUpdateCompanionBuilder,
          (ClipsTableData, $$ClipsTableTableReferences),
          ClipsTableData,
          PrefetchHooks Function({bool matchId, bool thumbnailsTableRefs})
        > {
  $$ClipsTableTableTableManager(_$AppDatabase db, $ClipsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClipsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClipsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClipsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> matchId = const Value.absent(),
                Value<int> startSeconds = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<String> startedAt = const Value.absent(),
                Value<String?> label = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClipsTableCompanion(
                id: id,
                matchId: matchId,
                startSeconds: startSeconds,
                durationSeconds: durationSeconds,
                sizeBytes: sizeBytes,
                startedAt: startedAt,
                label: label,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String matchId,
                Value<int> startSeconds = const Value.absent(),
                required int durationSeconds,
                required int sizeBytes,
                required String startedAt,
                Value<String?> label = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClipsTableCompanion.insert(
                id: id,
                matchId: matchId,
                startSeconds: startSeconds,
                durationSeconds: durationSeconds,
                sizeBytes: sizeBytes,
                startedAt: startedAt,
                label: label,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ClipsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({matchId = false, thumbnailsTableRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (thumbnailsTableRefs) db.thumbnailsTable,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (matchId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.matchId,
                                    referencedTable: $$ClipsTableTableReferences
                                        ._matchIdTable(db),
                                    referencedColumn:
                                        $$ClipsTableTableReferences
                                            ._matchIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (thumbnailsTableRefs)
                        await $_getPrefetchedData<
                          ClipsTableData,
                          $ClipsTableTable,
                          ThumbnailsTableData
                        >(
                          currentTable: table,
                          referencedTable: $$ClipsTableTableReferences
                              ._thumbnailsTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ClipsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).thumbnailsTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.clipId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ClipsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClipsTableTable,
      ClipsTableData,
      $$ClipsTableTableFilterComposer,
      $$ClipsTableTableOrderingComposer,
      $$ClipsTableTableAnnotationComposer,
      $$ClipsTableTableCreateCompanionBuilder,
      $$ClipsTableTableUpdateCompanionBuilder,
      (ClipsTableData, $$ClipsTableTableReferences),
      ClipsTableData,
      PrefetchHooks Function({bool matchId, bool thumbnailsTableRefs})
    >;
typedef $$ThumbnailsTableTableCreateCompanionBuilder =
    ThumbnailsTableCompanion Function({
      required String clipId,
      required String localPath,
      Value<int> rowid,
    });
typedef $$ThumbnailsTableTableUpdateCompanionBuilder =
    ThumbnailsTableCompanion Function({
      Value<String> clipId,
      Value<String> localPath,
      Value<int> rowid,
    });

final class $$ThumbnailsTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ThumbnailsTableTable,
          ThumbnailsTableData
        > {
  $$ThumbnailsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ClipsTableTable _clipIdTable(_$AppDatabase db) =>
      db.clipsTable.createAlias(
        $_aliasNameGenerator(db.thumbnailsTable.clipId, db.clipsTable.id),
      );

  $$ClipsTableTableProcessedTableManager get clipId {
    final $_column = $_itemColumn<String>('clip_id')!;

    final manager = $$ClipsTableTableTableManager(
      $_db,
      $_db.clipsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_clipIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ThumbnailsTableTableFilterComposer
    extends Composer<_$AppDatabase, $ThumbnailsTableTable> {
  $$ThumbnailsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  $$ClipsTableTableFilterComposer get clipId {
    final $$ClipsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clipId,
      referencedTable: $db.clipsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClipsTableTableFilterComposer(
            $db: $db,
            $table: $db.clipsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ThumbnailsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ThumbnailsTableTable> {
  $$ThumbnailsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  $$ClipsTableTableOrderingComposer get clipId {
    final $$ClipsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clipId,
      referencedTable: $db.clipsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClipsTableTableOrderingComposer(
            $db: $db,
            $table: $db.clipsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ThumbnailsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ThumbnailsTableTable> {
  $$ThumbnailsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  $$ClipsTableTableAnnotationComposer get clipId {
    final $$ClipsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clipId,
      referencedTable: $db.clipsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClipsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.clipsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ThumbnailsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ThumbnailsTableTable,
          ThumbnailsTableData,
          $$ThumbnailsTableTableFilterComposer,
          $$ThumbnailsTableTableOrderingComposer,
          $$ThumbnailsTableTableAnnotationComposer,
          $$ThumbnailsTableTableCreateCompanionBuilder,
          $$ThumbnailsTableTableUpdateCompanionBuilder,
          (ThumbnailsTableData, $$ThumbnailsTableTableReferences),
          ThumbnailsTableData,
          PrefetchHooks Function({bool clipId})
        > {
  $$ThumbnailsTableTableTableManager(
    _$AppDatabase db,
    $ThumbnailsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ThumbnailsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ThumbnailsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ThumbnailsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> clipId = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ThumbnailsTableCompanion(
                clipId: clipId,
                localPath: localPath,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String clipId,
                required String localPath,
                Value<int> rowid = const Value.absent(),
              }) => ThumbnailsTableCompanion.insert(
                clipId: clipId,
                localPath: localPath,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ThumbnailsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({clipId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (clipId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.clipId,
                                referencedTable:
                                    $$ThumbnailsTableTableReferences
                                        ._clipIdTable(db),
                                referencedColumn:
                                    $$ThumbnailsTableTableReferences
                                        ._clipIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ThumbnailsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ThumbnailsTableTable,
      ThumbnailsTableData,
      $$ThumbnailsTableTableFilterComposer,
      $$ThumbnailsTableTableOrderingComposer,
      $$ThumbnailsTableTableAnnotationComposer,
      $$ThumbnailsTableTableCreateCompanionBuilder,
      $$ThumbnailsTableTableUpdateCompanionBuilder,
      (ThumbnailsTableData, $$ThumbnailsTableTableReferences),
      ThumbnailsTableData,
      PrefetchHooks Function({bool clipId})
    >;
typedef $$RawRecordingsTableTableCreateCompanionBuilder =
    RawRecordingsTableCompanion Function({
      required String id,
      required String captureGroupId,
      required int cameraIndex,
      Value<String?> matchId,
      Value<String?> localPath,
      Value<int> sizeBytes,
      Value<bool> isRaw,
      Value<bool> isComplete,
      required String startedAt,
      Value<int> rowid,
    });
typedef $$RawRecordingsTableTableUpdateCompanionBuilder =
    RawRecordingsTableCompanion Function({
      Value<String> id,
      Value<String> captureGroupId,
      Value<int> cameraIndex,
      Value<String?> matchId,
      Value<String?> localPath,
      Value<int> sizeBytes,
      Value<bool> isRaw,
      Value<bool> isComplete,
      Value<String> startedAt,
      Value<int> rowid,
    });

final class $$RawRecordingsTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $RawRecordingsTableTable,
          RawRecordingsTableData
        > {
  $$RawRecordingsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $TeamMatchesTableTable _matchIdTable(_$AppDatabase db) =>
      db.teamMatchesTable.createAlias(
        $_aliasNameGenerator(
          db.rawRecordingsTable.matchId,
          db.teamMatchesTable.id,
        ),
      );

  $$TeamMatchesTableTableProcessedTableManager? get matchId {
    final $_column = $_itemColumn<String>('match_id');
    if ($_column == null) return null;
    final manager = $$TeamMatchesTableTableTableManager(
      $_db,
      $_db.teamMatchesTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_matchIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RawRecordingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $RawRecordingsTableTable> {
  $$RawRecordingsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get captureGroupId => $composableBuilder(
    column: $table.captureGroupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cameraIndex => $composableBuilder(
    column: $table.cameraIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRaw => $composableBuilder(
    column: $table.isRaw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isComplete => $composableBuilder(
    column: $table.isComplete,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$TeamMatchesTableTableFilterComposer get matchId {
    final $$TeamMatchesTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.matchId,
      referencedTable: $db.teamMatchesTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeamMatchesTableTableFilterComposer(
            $db: $db,
            $table: $db.teamMatchesTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RawRecordingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $RawRecordingsTableTable> {
  $$RawRecordingsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get captureGroupId => $composableBuilder(
    column: $table.captureGroupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cameraIndex => $composableBuilder(
    column: $table.cameraIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRaw => $composableBuilder(
    column: $table.isRaw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isComplete => $composableBuilder(
    column: $table.isComplete,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$TeamMatchesTableTableOrderingComposer get matchId {
    final $$TeamMatchesTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.matchId,
      referencedTable: $db.teamMatchesTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeamMatchesTableTableOrderingComposer(
            $db: $db,
            $table: $db.teamMatchesTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RawRecordingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $RawRecordingsTableTable> {
  $$RawRecordingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get captureGroupId => $composableBuilder(
    column: $table.captureGroupId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cameraIndex => $composableBuilder(
    column: $table.cameraIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<bool> get isRaw =>
      $composableBuilder(column: $table.isRaw, builder: (column) => column);

  GeneratedColumn<bool> get isComplete => $composableBuilder(
    column: $table.isComplete,
    builder: (column) => column,
  );

  GeneratedColumn<String> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  $$TeamMatchesTableTableAnnotationComposer get matchId {
    final $$TeamMatchesTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.matchId,
      referencedTable: $db.teamMatchesTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeamMatchesTableTableAnnotationComposer(
            $db: $db,
            $table: $db.teamMatchesTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RawRecordingsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RawRecordingsTableTable,
          RawRecordingsTableData,
          $$RawRecordingsTableTableFilterComposer,
          $$RawRecordingsTableTableOrderingComposer,
          $$RawRecordingsTableTableAnnotationComposer,
          $$RawRecordingsTableTableCreateCompanionBuilder,
          $$RawRecordingsTableTableUpdateCompanionBuilder,
          (RawRecordingsTableData, $$RawRecordingsTableTableReferences),
          RawRecordingsTableData,
          PrefetchHooks Function({bool matchId})
        > {
  $$RawRecordingsTableTableTableManager(
    _$AppDatabase db,
    $RawRecordingsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RawRecordingsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RawRecordingsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RawRecordingsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> captureGroupId = const Value.absent(),
                Value<int> cameraIndex = const Value.absent(),
                Value<String?> matchId = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<bool> isRaw = const Value.absent(),
                Value<bool> isComplete = const Value.absent(),
                Value<String> startedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RawRecordingsTableCompanion(
                id: id,
                captureGroupId: captureGroupId,
                cameraIndex: cameraIndex,
                matchId: matchId,
                localPath: localPath,
                sizeBytes: sizeBytes,
                isRaw: isRaw,
                isComplete: isComplete,
                startedAt: startedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String captureGroupId,
                required int cameraIndex,
                Value<String?> matchId = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<bool> isRaw = const Value.absent(),
                Value<bool> isComplete = const Value.absent(),
                required String startedAt,
                Value<int> rowid = const Value.absent(),
              }) => RawRecordingsTableCompanion.insert(
                id: id,
                captureGroupId: captureGroupId,
                cameraIndex: cameraIndex,
                matchId: matchId,
                localPath: localPath,
                sizeBytes: sizeBytes,
                isRaw: isRaw,
                isComplete: isComplete,
                startedAt: startedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RawRecordingsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({matchId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (matchId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.matchId,
                                referencedTable:
                                    $$RawRecordingsTableTableReferences
                                        ._matchIdTable(db),
                                referencedColumn:
                                    $$RawRecordingsTableTableReferences
                                        ._matchIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RawRecordingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RawRecordingsTableTable,
      RawRecordingsTableData,
      $$RawRecordingsTableTableFilterComposer,
      $$RawRecordingsTableTableOrderingComposer,
      $$RawRecordingsTableTableAnnotationComposer,
      $$RawRecordingsTableTableCreateCompanionBuilder,
      $$RawRecordingsTableTableUpdateCompanionBuilder,
      (RawRecordingsTableData, $$RawRecordingsTableTableReferences),
      RawRecordingsTableData,
      PrefetchHooks Function({bool matchId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$UsersTableTableTableManager get usersTable =>
      $$UsersTableTableTableManager(_db, _db.usersTable);
  $$TeamsTableTableTableManager get teamsTable =>
      $$TeamsTableTableTableManager(_db, _db.teamsTable);
  $$PlayersTableTableTableManager get playersTable =>
      $$PlayersTableTableTableManager(_db, _db.playersTable);
  $$TeamMatchesTableTableTableManager get teamMatchesTable =>
      $$TeamMatchesTableTableTableManager(_db, _db.teamMatchesTable);
  $$SportPresetsTableTableTableManager get sportPresetsTable =>
      $$SportPresetsTableTableTableManager(_db, _db.sportPresetsTable);
  $$StreamingDestinationsTableTableTableManager
  get streamingDestinationsTable =>
      $$StreamingDestinationsTableTableTableManager(
        _db,
        _db.streamingDestinationsTable,
      );
  $$ClipsTableTableTableManager get clipsTable =>
      $$ClipsTableTableTableManager(_db, _db.clipsTable);
  $$ThumbnailsTableTableTableManager get thumbnailsTable =>
      $$ThumbnailsTableTableTableManager(_db, _db.thumbnailsTable);
  $$RawRecordingsTableTableTableManager get rawRecordingsTable =>
      $$RawRecordingsTableTableTableManager(_db, _db.rawRecordingsTable);
}
