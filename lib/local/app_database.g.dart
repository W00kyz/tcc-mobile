// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $PendingOperationsTable extends PendingOperations
    with TableInfo<$PendingOperationsTable, PendingOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _routeIdMeta = const VerificationMeta(
    'routeId',
  );
  @override
  late final GeneratedColumn<String> routeId = GeneratedColumn<String>(
    'route_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<int> nextAttemptAt = GeneratedColumn<int>(
    'next_attempt_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _releasedStopIdMeta = const VerificationMeta(
    'releasedStopId',
  );
  @override
  late final GeneratedColumn<String> releasedStopId = GeneratedColumn<String>(
    'released_stop_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    routeId,
    payloadJson,
    createdAt,
    state,
    lastError,
    attempts,
    nextAttemptAt,
    releasedStopId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('route_id')) {
      context.handle(
        _routeIdMeta,
        routeId.isAcceptableOrUnknown(data['route_id']!, _routeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_routeIdMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('released_stop_id')) {
      context.handle(
        _releasedStopIdMeta,
        releasedStopId.isAcceptableOrUnknown(
          data['released_stop_id']!,
          _releasedStopIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingOperation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      routeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route_id'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_attempt_at'],
      ),
      releasedStopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}released_stop_id'],
      ),
    );
  }

  @override
  $PendingOperationsTable createAlias(String alias) {
    return $PendingOperationsTable(attachedDatabase, alias);
  }
}

class PendingOperation extends DataClass
    implements Insertable<PendingOperation> {
  /// Equals the operation's idempotency key (UUID v4 generated on the device).
  final String id;
  final String kind;
  final String routeId;
  final String payloadJson;

  /// Epoch milliseconds from the device clock at enqueue time.
  final int createdAt;
  final String state;
  final String? lastError;

  /// How many sync attempts this row has already burned (spec Ruling 6).
  final int attempts;

  /// Epoch milliseconds before which the worker must not retry this row.
  /// Null means "eligible now" (never attempted, or retry window elapsed).
  final int? nextAttemptAt;

  /// The released stop a `409 STOP_RELEASED` parked this `blocked` row on
  /// (spec 2026-10-20-alocacao-automatica §7.5) — named by the server, since
  /// an evidence row carries no stop of its own. Null for any other row.
  final String? releasedStopId;
  const PendingOperation({
    required this.id,
    required this.kind,
    required this.routeId,
    required this.payloadJson,
    required this.createdAt,
    required this.state,
    this.lastError,
    required this.attempts,
    this.nextAttemptAt,
    this.releasedStopId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    map['route_id'] = Variable<String>(routeId);
    map['payload_json'] = Variable<String>(payloadJson);
    map['created_at'] = Variable<int>(createdAt);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<int>(nextAttemptAt);
    }
    if (!nullToAbsent || releasedStopId != null) {
      map['released_stop_id'] = Variable<String>(releasedStopId);
    }
    return map;
  }

  PendingOperationsCompanion toCompanion(bool nullToAbsent) {
    return PendingOperationsCompanion(
      id: Value(id),
      kind: Value(kind),
      routeId: Value(routeId),
      payloadJson: Value(payloadJson),
      createdAt: Value(createdAt),
      state: Value(state),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      attempts: Value(attempts),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      releasedStopId: releasedStopId == null && nullToAbsent
          ? const Value.absent()
          : Value(releasedStopId),
    );
  }

  factory PendingOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingOperation(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      routeId: serializer.fromJson<String>(json['routeId']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      state: serializer.fromJson<String>(json['state']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<int?>(json['nextAttemptAt']),
      releasedStopId: serializer.fromJson<String?>(json['releasedStopId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'routeId': serializer.toJson<String>(routeId),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'createdAt': serializer.toJson<int>(createdAt),
      'state': serializer.toJson<String>(state),
      'lastError': serializer.toJson<String?>(lastError),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<int?>(nextAttemptAt),
      'releasedStopId': serializer.toJson<String?>(releasedStopId),
    };
  }

  PendingOperation copyWith({
    String? id,
    String? kind,
    String? routeId,
    String? payloadJson,
    int? createdAt,
    String? state,
    Value<String?> lastError = const Value.absent(),
    int? attempts,
    Value<int?> nextAttemptAt = const Value.absent(),
    Value<String?> releasedStopId = const Value.absent(),
  }) => PendingOperation(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    routeId: routeId ?? this.routeId,
    payloadJson: payloadJson ?? this.payloadJson,
    createdAt: createdAt ?? this.createdAt,
    state: state ?? this.state,
    lastError: lastError.present ? lastError.value : this.lastError,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    releasedStopId: releasedStopId.present
        ? releasedStopId.value
        : this.releasedStopId,
  );
  PendingOperation copyWithCompanion(PendingOperationsCompanion data) {
    return PendingOperation(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      routeId: data.routeId.present ? data.routeId.value : this.routeId,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      state: data.state.present ? data.state.value : this.state,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      releasedStopId: data.releasedStopId.present
          ? data.releasedStopId.value
          : this.releasedStopId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingOperation(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('routeId: $routeId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('state: $state, ')
          ..write('lastError: $lastError, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('releasedStopId: $releasedStopId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    routeId,
    payloadJson,
    createdAt,
    state,
    lastError,
    attempts,
    nextAttemptAt,
    releasedStopId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingOperation &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.routeId == this.routeId &&
          other.payloadJson == this.payloadJson &&
          other.createdAt == this.createdAt &&
          other.state == this.state &&
          other.lastError == this.lastError &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.releasedStopId == this.releasedStopId);
}

class PendingOperationsCompanion extends UpdateCompanion<PendingOperation> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String> routeId;
  final Value<String> payloadJson;
  final Value<int> createdAt;
  final Value<String> state;
  final Value<String?> lastError;
  final Value<int> attempts;
  final Value<int?> nextAttemptAt;
  final Value<String?> releasedStopId;
  final Value<int> rowid;
  const PendingOperationsCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.routeId = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.state = const Value.absent(),
    this.lastError = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.releasedStopId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingOperationsCompanion.insert({
    required String id,
    required String kind,
    required String routeId,
    required String payloadJson,
    required int createdAt,
    this.state = const Value.absent(),
    this.lastError = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.releasedStopId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       routeId = Value(routeId),
       payloadJson = Value(payloadJson),
       createdAt = Value(createdAt);
  static Insertable<PendingOperation> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? routeId,
    Expression<String>? payloadJson,
    Expression<int>? createdAt,
    Expression<String>? state,
    Expression<String>? lastError,
    Expression<int>? attempts,
    Expression<int>? nextAttemptAt,
    Expression<String>? releasedStopId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (routeId != null) 'route_id': routeId,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (createdAt != null) 'created_at': createdAt,
      if (state != null) 'state': state,
      if (lastError != null) 'last_error': lastError,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (releasedStopId != null) 'released_stop_id': releasedStopId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingOperationsCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<String>? routeId,
    Value<String>? payloadJson,
    Value<int>? createdAt,
    Value<String>? state,
    Value<String?>? lastError,
    Value<int>? attempts,
    Value<int?>? nextAttemptAt,
    Value<String?>? releasedStopId,
    Value<int>? rowid,
  }) {
    return PendingOperationsCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      routeId: routeId ?? this.routeId,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAt: createdAt ?? this.createdAt,
      state: state ?? this.state,
      lastError: lastError ?? this.lastError,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      releasedStopId: releasedStopId ?? this.releasedStopId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (routeId.present) {
      map['route_id'] = Variable<String>(routeId.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<int>(nextAttemptAt.value);
    }
    if (releasedStopId.present) {
      map['released_stop_id'] = Variable<String>(releasedStopId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingOperationsCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('routeId: $routeId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('state: $state, ')
          ..write('lastError: $lastError, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('releasedStopId: $releasedStopId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StopProgressTable extends StopProgress
    with TableInfo<$StopProgressTable, StopProgressData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StopProgressTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _routeStopIdMeta = const VerificationMeta(
    'routeStopId',
  );
  @override
  late final GeneratedColumn<String> routeStopId = GeneratedColumn<String>(
    'route_stop_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _executionIdMeta = const VerificationMeta(
    'executionId',
  );
  @override
  late final GeneratedColumn<String> executionId = GeneratedColumn<String>(
    'execution_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localStatusMeta = const VerificationMeta(
    'localStatus',
  );
  @override
  late final GeneratedColumn<String> localStatus = GeneratedColumn<String>(
    'local_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    routeStopId,
    executionId,
    localStatus,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stop_progress';
  @override
  VerificationContext validateIntegrity(
    Insertable<StopProgressData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('route_stop_id')) {
      context.handle(
        _routeStopIdMeta,
        routeStopId.isAcceptableOrUnknown(
          data['route_stop_id']!,
          _routeStopIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_routeStopIdMeta);
    }
    if (data.containsKey('execution_id')) {
      context.handle(
        _executionIdMeta,
        executionId.isAcceptableOrUnknown(
          data['execution_id']!,
          _executionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_executionIdMeta);
    }
    if (data.containsKey('local_status')) {
      context.handle(
        _localStatusMeta,
        localStatus.isAcceptableOrUnknown(
          data['local_status']!,
          _localStatusMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localStatusMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {routeStopId};
  @override
  StopProgressData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StopProgressData(
      routeStopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route_stop_id'],
      )!,
      executionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}execution_id'],
      )!,
      localStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_status'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $StopProgressTable createAlias(String alias) {
    return $StopProgressTable(attachedDatabase, alias);
  }
}

class StopProgressData extends DataClass
    implements Insertable<StopProgressData> {
  final String routeStopId;
  final String executionId;

  /// `'IN_PROGRESS'` | `'DONE'`.
  final String localStatus;

  /// Epoch milliseconds of the last local transition for this stop.
  final int updatedAt;
  const StopProgressData({
    required this.routeStopId,
    required this.executionId,
    required this.localStatus,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['route_stop_id'] = Variable<String>(routeStopId);
    map['execution_id'] = Variable<String>(executionId);
    map['local_status'] = Variable<String>(localStatus);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  StopProgressCompanion toCompanion(bool nullToAbsent) {
    return StopProgressCompanion(
      routeStopId: Value(routeStopId),
      executionId: Value(executionId),
      localStatus: Value(localStatus),
      updatedAt: Value(updatedAt),
    );
  }

  factory StopProgressData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StopProgressData(
      routeStopId: serializer.fromJson<String>(json['routeStopId']),
      executionId: serializer.fromJson<String>(json['executionId']),
      localStatus: serializer.fromJson<String>(json['localStatus']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'routeStopId': serializer.toJson<String>(routeStopId),
      'executionId': serializer.toJson<String>(executionId),
      'localStatus': serializer.toJson<String>(localStatus),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  StopProgressData copyWith({
    String? routeStopId,
    String? executionId,
    String? localStatus,
    int? updatedAt,
  }) => StopProgressData(
    routeStopId: routeStopId ?? this.routeStopId,
    executionId: executionId ?? this.executionId,
    localStatus: localStatus ?? this.localStatus,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  StopProgressData copyWithCompanion(StopProgressCompanion data) {
    return StopProgressData(
      routeStopId: data.routeStopId.present
          ? data.routeStopId.value
          : this.routeStopId,
      executionId: data.executionId.present
          ? data.executionId.value
          : this.executionId,
      localStatus: data.localStatus.present
          ? data.localStatus.value
          : this.localStatus,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StopProgressData(')
          ..write('routeStopId: $routeStopId, ')
          ..write('executionId: $executionId, ')
          ..write('localStatus: $localStatus, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(routeStopId, executionId, localStatus, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StopProgressData &&
          other.routeStopId == this.routeStopId &&
          other.executionId == this.executionId &&
          other.localStatus == this.localStatus &&
          other.updatedAt == this.updatedAt);
}

class StopProgressCompanion extends UpdateCompanion<StopProgressData> {
  final Value<String> routeStopId;
  final Value<String> executionId;
  final Value<String> localStatus;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const StopProgressCompanion({
    this.routeStopId = const Value.absent(),
    this.executionId = const Value.absent(),
    this.localStatus = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StopProgressCompanion.insert({
    required String routeStopId,
    required String executionId,
    required String localStatus,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : routeStopId = Value(routeStopId),
       executionId = Value(executionId),
       localStatus = Value(localStatus),
       updatedAt = Value(updatedAt);
  static Insertable<StopProgressData> custom({
    Expression<String>? routeStopId,
    Expression<String>? executionId,
    Expression<String>? localStatus,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (routeStopId != null) 'route_stop_id': routeStopId,
      if (executionId != null) 'execution_id': executionId,
      if (localStatus != null) 'local_status': localStatus,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StopProgressCompanion copyWith({
    Value<String>? routeStopId,
    Value<String>? executionId,
    Value<String>? localStatus,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return StopProgressCompanion(
      routeStopId: routeStopId ?? this.routeStopId,
      executionId: executionId ?? this.executionId,
      localStatus: localStatus ?? this.localStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (routeStopId.present) {
      map['route_stop_id'] = Variable<String>(routeStopId.value);
    }
    if (executionId.present) {
      map['execution_id'] = Variable<String>(executionId.value);
    }
    if (localStatus.present) {
      map['local_status'] = Variable<String>(localStatus.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StopProgressCompanion(')
          ..write('routeStopId: $routeStopId, ')
          ..write('executionId: $executionId, ')
          ..write('localStatus: $localStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncMetaTable extends SyncMeta
    with TableInfo<$SyncMetaTable, SyncMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetaData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SyncMetaTable createAlias(String alias) {
    return $SyncMetaTable(attachedDatabase, alias);
  }
}

class SyncMetaData extends DataClass implements Insertable<SyncMetaData> {
  final String key;
  final String value;
  const SyncMetaData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SyncMetaCompanion toCompanion(bool nullToAbsent) {
    return SyncMetaCompanion(key: Value(key), value: Value(value));
  }

  factory SyncMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetaData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SyncMetaData copyWith({String? key, String? value}) =>
      SyncMetaData(key: key ?? this.key, value: value ?? this.value);
  SyncMetaData copyWithCompanion(SyncMetaCompanion data) {
    return SyncMetaData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetaData &&
          other.key == this.key &&
          other.value == this.value);
}

class SyncMetaCompanion extends UpdateCompanion<SyncMetaData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SyncMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SyncMetaData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SyncMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FormDraftItemsTable extends FormDraftItems
    with TableInfo<$FormDraftItemsTable, FormDraftItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FormDraftItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _executionIdMeta = const VerificationMeta(
    'executionId',
  );
  @override
  late final GeneratedColumn<String> executionId = GeneratedColumn<String>(
    'execution_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stableKeyMeta = const VerificationMeta(
    'stableKey',
  );
  @override
  late final GeneratedColumn<String> stableKey = GeneratedColumn<String>(
    'stable_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _routeStopIdMeta = const VerificationMeta(
    'routeStopId',
  );
  @override
  late final GeneratedColumn<String> routeStopId = GeneratedColumn<String>(
    'route_stop_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _formVersionIdMeta = const VerificationMeta(
    'formVersionId',
  );
  @override
  late final GeneratedColumn<String> formVersionId = GeneratedColumn<String>(
    'form_version_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orderIndexMeta = const VerificationMeta(
    'orderIndex',
  );
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
    'order_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _promptMeta = const VerificationMeta('prompt');
  @override
  late final GeneratedColumn<String> prompt = GeneratedColumn<String>(
    'prompt',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _questionTypeMeta = const VerificationMeta(
    'questionType',
  );
  @override
  late final GeneratedColumn<String> questionType = GeneratedColumn<String>(
    'question_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requiredMeta = const VerificationMeta(
    'required',
  );
  @override
  late final GeneratedColumn<bool> required = GeneratedColumn<bool>(
    'required',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("required" IN (0, 1))',
    ),
  );
  static const VerificationMeta _optionsJsonMeta = const VerificationMeta(
    'optionsJson',
  );
  @override
  late final GeneratedColumn<String> optionsJson = GeneratedColumn<String>(
    'options_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueJsonMeta = const VerificationMeta(
    'valueJson',
  );
  @override
  late final GeneratedColumn<String> valueJson = GeneratedColumn<String>(
    'value_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _needsReanswerMeta = const VerificationMeta(
    'needsReanswer',
  );
  @override
  late final GeneratedColumn<bool> needsReanswer = GeneratedColumn<bool>(
    'needs_reanswer',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("needs_reanswer" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    executionId,
    stableKey,
    routeStopId,
    formVersionId,
    orderIndex,
    prompt,
    questionType,
    required,
    optionsJson,
    contentHash,
    valueJson,
    needsReanswer,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'form_draft_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<FormDraftItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('execution_id')) {
      context.handle(
        _executionIdMeta,
        executionId.isAcceptableOrUnknown(
          data['execution_id']!,
          _executionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_executionIdMeta);
    }
    if (data.containsKey('stable_key')) {
      context.handle(
        _stableKeyMeta,
        stableKey.isAcceptableOrUnknown(data['stable_key']!, _stableKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_stableKeyMeta);
    }
    if (data.containsKey('route_stop_id')) {
      context.handle(
        _routeStopIdMeta,
        routeStopId.isAcceptableOrUnknown(
          data['route_stop_id']!,
          _routeStopIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_routeStopIdMeta);
    }
    if (data.containsKey('form_version_id')) {
      context.handle(
        _formVersionIdMeta,
        formVersionId.isAcceptableOrUnknown(
          data['form_version_id']!,
          _formVersionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_formVersionIdMeta);
    }
    if (data.containsKey('order_index')) {
      context.handle(
        _orderIndexMeta,
        orderIndex.isAcceptableOrUnknown(data['order_index']!, _orderIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_orderIndexMeta);
    }
    if (data.containsKey('prompt')) {
      context.handle(
        _promptMeta,
        prompt.isAcceptableOrUnknown(data['prompt']!, _promptMeta),
      );
    } else if (isInserting) {
      context.missing(_promptMeta);
    }
    if (data.containsKey('question_type')) {
      context.handle(
        _questionTypeMeta,
        questionType.isAcceptableOrUnknown(
          data['question_type']!,
          _questionTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_questionTypeMeta);
    }
    if (data.containsKey('required')) {
      context.handle(
        _requiredMeta,
        required.isAcceptableOrUnknown(data['required']!, _requiredMeta),
      );
    } else if (isInserting) {
      context.missing(_requiredMeta);
    }
    if (data.containsKey('options_json')) {
      context.handle(
        _optionsJsonMeta,
        optionsJson.isAcceptableOrUnknown(
          data['options_json']!,
          _optionsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_optionsJsonMeta);
    }
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentHashMeta);
    }
    if (data.containsKey('value_json')) {
      context.handle(
        _valueJsonMeta,
        valueJson.isAcceptableOrUnknown(data['value_json']!, _valueJsonMeta),
      );
    }
    if (data.containsKey('needs_reanswer')) {
      context.handle(
        _needsReanswerMeta,
        needsReanswer.isAcceptableOrUnknown(
          data['needs_reanswer']!,
          _needsReanswerMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {executionId, stableKey};
  @override
  FormDraftItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FormDraftItem(
      executionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}execution_id'],
      )!,
      stableKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stable_key'],
      )!,
      routeStopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route_stop_id'],
      )!,
      formVersionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}form_version_id'],
      )!,
      orderIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_index'],
      )!,
      prompt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prompt'],
      )!,
      questionType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}question_type'],
      )!,
      required: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}required'],
      )!,
      optionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}options_json'],
      )!,
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      )!,
      valueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_json'],
      ),
      needsReanswer: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}needs_reanswer'],
      )!,
    );
  }

  @override
  $FormDraftItemsTable createAlias(String alias) {
    return $FormDraftItemsTable(attachedDatabase, alias);
  }
}

class FormDraftItem extends DataClass implements Insertable<FormDraftItem> {
  final String executionId;
  final String stableKey;
  final String routeStopId;
  final String formVersionId;
  final int orderIndex;
  final String prompt;
  final String questionType;
  final bool required;
  final String optionsJson;
  final String contentHash;
  final String? valueJson;
  final bool needsReanswer;
  const FormDraftItem({
    required this.executionId,
    required this.stableKey,
    required this.routeStopId,
    required this.formVersionId,
    required this.orderIndex,
    required this.prompt,
    required this.questionType,
    required this.required,
    required this.optionsJson,
    required this.contentHash,
    this.valueJson,
    required this.needsReanswer,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['execution_id'] = Variable<String>(executionId);
    map['stable_key'] = Variable<String>(stableKey);
    map['route_stop_id'] = Variable<String>(routeStopId);
    map['form_version_id'] = Variable<String>(formVersionId);
    map['order_index'] = Variable<int>(orderIndex);
    map['prompt'] = Variable<String>(prompt);
    map['question_type'] = Variable<String>(questionType);
    map['required'] = Variable<bool>(required);
    map['options_json'] = Variable<String>(optionsJson);
    map['content_hash'] = Variable<String>(contentHash);
    if (!nullToAbsent || valueJson != null) {
      map['value_json'] = Variable<String>(valueJson);
    }
    map['needs_reanswer'] = Variable<bool>(needsReanswer);
    return map;
  }

  FormDraftItemsCompanion toCompanion(bool nullToAbsent) {
    return FormDraftItemsCompanion(
      executionId: Value(executionId),
      stableKey: Value(stableKey),
      routeStopId: Value(routeStopId),
      formVersionId: Value(formVersionId),
      orderIndex: Value(orderIndex),
      prompt: Value(prompt),
      questionType: Value(questionType),
      required: Value(required),
      optionsJson: Value(optionsJson),
      contentHash: Value(contentHash),
      valueJson: valueJson == null && nullToAbsent
          ? const Value.absent()
          : Value(valueJson),
      needsReanswer: Value(needsReanswer),
    );
  }

  factory FormDraftItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FormDraftItem(
      executionId: serializer.fromJson<String>(json['executionId']),
      stableKey: serializer.fromJson<String>(json['stableKey']),
      routeStopId: serializer.fromJson<String>(json['routeStopId']),
      formVersionId: serializer.fromJson<String>(json['formVersionId']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
      prompt: serializer.fromJson<String>(json['prompt']),
      questionType: serializer.fromJson<String>(json['questionType']),
      required: serializer.fromJson<bool>(json['required']),
      optionsJson: serializer.fromJson<String>(json['optionsJson']),
      contentHash: serializer.fromJson<String>(json['contentHash']),
      valueJson: serializer.fromJson<String?>(json['valueJson']),
      needsReanswer: serializer.fromJson<bool>(json['needsReanswer']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'executionId': serializer.toJson<String>(executionId),
      'stableKey': serializer.toJson<String>(stableKey),
      'routeStopId': serializer.toJson<String>(routeStopId),
      'formVersionId': serializer.toJson<String>(formVersionId),
      'orderIndex': serializer.toJson<int>(orderIndex),
      'prompt': serializer.toJson<String>(prompt),
      'questionType': serializer.toJson<String>(questionType),
      'required': serializer.toJson<bool>(required),
      'optionsJson': serializer.toJson<String>(optionsJson),
      'contentHash': serializer.toJson<String>(contentHash),
      'valueJson': serializer.toJson<String?>(valueJson),
      'needsReanswer': serializer.toJson<bool>(needsReanswer),
    };
  }

  FormDraftItem copyWith({
    String? executionId,
    String? stableKey,
    String? routeStopId,
    String? formVersionId,
    int? orderIndex,
    String? prompt,
    String? questionType,
    bool? required,
    String? optionsJson,
    String? contentHash,
    Value<String?> valueJson = const Value.absent(),
    bool? needsReanswer,
  }) => FormDraftItem(
    executionId: executionId ?? this.executionId,
    stableKey: stableKey ?? this.stableKey,
    routeStopId: routeStopId ?? this.routeStopId,
    formVersionId: formVersionId ?? this.formVersionId,
    orderIndex: orderIndex ?? this.orderIndex,
    prompt: prompt ?? this.prompt,
    questionType: questionType ?? this.questionType,
    required: required ?? this.required,
    optionsJson: optionsJson ?? this.optionsJson,
    contentHash: contentHash ?? this.contentHash,
    valueJson: valueJson.present ? valueJson.value : this.valueJson,
    needsReanswer: needsReanswer ?? this.needsReanswer,
  );
  FormDraftItem copyWithCompanion(FormDraftItemsCompanion data) {
    return FormDraftItem(
      executionId: data.executionId.present
          ? data.executionId.value
          : this.executionId,
      stableKey: data.stableKey.present ? data.stableKey.value : this.stableKey,
      routeStopId: data.routeStopId.present
          ? data.routeStopId.value
          : this.routeStopId,
      formVersionId: data.formVersionId.present
          ? data.formVersionId.value
          : this.formVersionId,
      orderIndex: data.orderIndex.present
          ? data.orderIndex.value
          : this.orderIndex,
      prompt: data.prompt.present ? data.prompt.value : this.prompt,
      questionType: data.questionType.present
          ? data.questionType.value
          : this.questionType,
      required: data.required.present ? data.required.value : this.required,
      optionsJson: data.optionsJson.present
          ? data.optionsJson.value
          : this.optionsJson,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      valueJson: data.valueJson.present ? data.valueJson.value : this.valueJson,
      needsReanswer: data.needsReanswer.present
          ? data.needsReanswer.value
          : this.needsReanswer,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FormDraftItem(')
          ..write('executionId: $executionId, ')
          ..write('stableKey: $stableKey, ')
          ..write('routeStopId: $routeStopId, ')
          ..write('formVersionId: $formVersionId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('prompt: $prompt, ')
          ..write('questionType: $questionType, ')
          ..write('required: $required, ')
          ..write('optionsJson: $optionsJson, ')
          ..write('contentHash: $contentHash, ')
          ..write('valueJson: $valueJson, ')
          ..write('needsReanswer: $needsReanswer')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    executionId,
    stableKey,
    routeStopId,
    formVersionId,
    orderIndex,
    prompt,
    questionType,
    required,
    optionsJson,
    contentHash,
    valueJson,
    needsReanswer,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FormDraftItem &&
          other.executionId == this.executionId &&
          other.stableKey == this.stableKey &&
          other.routeStopId == this.routeStopId &&
          other.formVersionId == this.formVersionId &&
          other.orderIndex == this.orderIndex &&
          other.prompt == this.prompt &&
          other.questionType == this.questionType &&
          other.required == this.required &&
          other.optionsJson == this.optionsJson &&
          other.contentHash == this.contentHash &&
          other.valueJson == this.valueJson &&
          other.needsReanswer == this.needsReanswer);
}

class FormDraftItemsCompanion extends UpdateCompanion<FormDraftItem> {
  final Value<String> executionId;
  final Value<String> stableKey;
  final Value<String> routeStopId;
  final Value<String> formVersionId;
  final Value<int> orderIndex;
  final Value<String> prompt;
  final Value<String> questionType;
  final Value<bool> required;
  final Value<String> optionsJson;
  final Value<String> contentHash;
  final Value<String?> valueJson;
  final Value<bool> needsReanswer;
  final Value<int> rowid;
  const FormDraftItemsCompanion({
    this.executionId = const Value.absent(),
    this.stableKey = const Value.absent(),
    this.routeStopId = const Value.absent(),
    this.formVersionId = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.prompt = const Value.absent(),
    this.questionType = const Value.absent(),
    this.required = const Value.absent(),
    this.optionsJson = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.needsReanswer = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FormDraftItemsCompanion.insert({
    required String executionId,
    required String stableKey,
    required String routeStopId,
    required String formVersionId,
    required int orderIndex,
    required String prompt,
    required String questionType,
    required bool required,
    required String optionsJson,
    required String contentHash,
    this.valueJson = const Value.absent(),
    this.needsReanswer = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : executionId = Value(executionId),
       stableKey = Value(stableKey),
       routeStopId = Value(routeStopId),
       formVersionId = Value(formVersionId),
       orderIndex = Value(orderIndex),
       prompt = Value(prompt),
       questionType = Value(questionType),
       required = Value(required),
       optionsJson = Value(optionsJson),
       contentHash = Value(contentHash);
  static Insertable<FormDraftItem> custom({
    Expression<String>? executionId,
    Expression<String>? stableKey,
    Expression<String>? routeStopId,
    Expression<String>? formVersionId,
    Expression<int>? orderIndex,
    Expression<String>? prompt,
    Expression<String>? questionType,
    Expression<bool>? required,
    Expression<String>? optionsJson,
    Expression<String>? contentHash,
    Expression<String>? valueJson,
    Expression<bool>? needsReanswer,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (executionId != null) 'execution_id': executionId,
      if (stableKey != null) 'stable_key': stableKey,
      if (routeStopId != null) 'route_stop_id': routeStopId,
      if (formVersionId != null) 'form_version_id': formVersionId,
      if (orderIndex != null) 'order_index': orderIndex,
      if (prompt != null) 'prompt': prompt,
      if (questionType != null) 'question_type': questionType,
      if (required != null) 'required': required,
      if (optionsJson != null) 'options_json': optionsJson,
      if (contentHash != null) 'content_hash': contentHash,
      if (valueJson != null) 'value_json': valueJson,
      if (needsReanswer != null) 'needs_reanswer': needsReanswer,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FormDraftItemsCompanion copyWith({
    Value<String>? executionId,
    Value<String>? stableKey,
    Value<String>? routeStopId,
    Value<String>? formVersionId,
    Value<int>? orderIndex,
    Value<String>? prompt,
    Value<String>? questionType,
    Value<bool>? required,
    Value<String>? optionsJson,
    Value<String>? contentHash,
    Value<String?>? valueJson,
    Value<bool>? needsReanswer,
    Value<int>? rowid,
  }) {
    return FormDraftItemsCompanion(
      executionId: executionId ?? this.executionId,
      stableKey: stableKey ?? this.stableKey,
      routeStopId: routeStopId ?? this.routeStopId,
      formVersionId: formVersionId ?? this.formVersionId,
      orderIndex: orderIndex ?? this.orderIndex,
      prompt: prompt ?? this.prompt,
      questionType: questionType ?? this.questionType,
      required: required ?? this.required,
      optionsJson: optionsJson ?? this.optionsJson,
      contentHash: contentHash ?? this.contentHash,
      valueJson: valueJson ?? this.valueJson,
      needsReanswer: needsReanswer ?? this.needsReanswer,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (executionId.present) {
      map['execution_id'] = Variable<String>(executionId.value);
    }
    if (stableKey.present) {
      map['stable_key'] = Variable<String>(stableKey.value);
    }
    if (routeStopId.present) {
      map['route_stop_id'] = Variable<String>(routeStopId.value);
    }
    if (formVersionId.present) {
      map['form_version_id'] = Variable<String>(formVersionId.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    if (prompt.present) {
      map['prompt'] = Variable<String>(prompt.value);
    }
    if (questionType.present) {
      map['question_type'] = Variable<String>(questionType.value);
    }
    if (required.present) {
      map['required'] = Variable<bool>(required.value);
    }
    if (optionsJson.present) {
      map['options_json'] = Variable<String>(optionsJson.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (valueJson.present) {
      map['value_json'] = Variable<String>(valueJson.value);
    }
    if (needsReanswer.present) {
      map['needs_reanswer'] = Variable<bool>(needsReanswer.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FormDraftItemsCompanion(')
          ..write('executionId: $executionId, ')
          ..write('stableKey: $stableKey, ')
          ..write('routeStopId: $routeStopId, ')
          ..write('formVersionId: $formVersionId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('prompt: $prompt, ')
          ..write('questionType: $questionType, ')
          ..write('required: $required, ')
          ..write('optionsJson: $optionsJson, ')
          ..write('contentHash: $contentHash, ')
          ..write('valueJson: $valueJson, ')
          ..write('needsReanswer: $needsReanswer, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReleasedStopsTable extends ReleasedStops
    with TableInfo<$ReleasedStopsTable, ReleasedStop> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReleasedStopsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _routeStopIdMeta = const VerificationMeta(
    'routeStopId',
  );
  @override
  late final GeneratedColumn<String> routeStopId = GeneratedColumn<String>(
    'route_stop_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _releaseReasonMeta = const VerificationMeta(
    'releaseReason',
  );
  @override
  late final GeneratedColumn<String> releaseReason = GeneratedColumn<String>(
    'release_reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _appealableMeta = const VerificationMeta(
    'appealable',
  );
  @override
  late final GeneratedColumn<bool> appealable = GeneratedColumn<bool>(
    'appealable',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("appealable" IN (0, 1))',
    ),
  );
  static const VerificationMeta _localCheckInAtMeta = const VerificationMeta(
    'localCheckInAt',
  );
  @override
  late final GeneratedColumn<int> localCheckInAt = GeneratedColumn<int>(
    'local_check_in_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localCheckOutAtMeta = const VerificationMeta(
    'localCheckOutAt',
  );
  @override
  late final GeneratedColumn<int> localCheckOutAt = GeneratedColumn<int>(
    'local_check_out_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    routeStopId,
    releaseReason,
    appealable,
    localCheckInAt,
    localCheckOutAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'released_stops';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReleasedStop> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('route_stop_id')) {
      context.handle(
        _routeStopIdMeta,
        routeStopId.isAcceptableOrUnknown(
          data['route_stop_id']!,
          _routeStopIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_routeStopIdMeta);
    }
    if (data.containsKey('release_reason')) {
      context.handle(
        _releaseReasonMeta,
        releaseReason.isAcceptableOrUnknown(
          data['release_reason']!,
          _releaseReasonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_releaseReasonMeta);
    }
    if (data.containsKey('appealable')) {
      context.handle(
        _appealableMeta,
        appealable.isAcceptableOrUnknown(data['appealable']!, _appealableMeta),
      );
    } else if (isInserting) {
      context.missing(_appealableMeta);
    }
    if (data.containsKey('local_check_in_at')) {
      context.handle(
        _localCheckInAtMeta,
        localCheckInAt.isAcceptableOrUnknown(
          data['local_check_in_at']!,
          _localCheckInAtMeta,
        ),
      );
    }
    if (data.containsKey('local_check_out_at')) {
      context.handle(
        _localCheckOutAtMeta,
        localCheckOutAt.isAcceptableOrUnknown(
          data['local_check_out_at']!,
          _localCheckOutAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {routeStopId};
  @override
  ReleasedStop map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReleasedStop(
      routeStopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route_stop_id'],
      )!,
      releaseReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}release_reason'],
      )!,
      appealable: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}appealable'],
      )!,
      localCheckInAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_check_in_at'],
      ),
      localCheckOutAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_check_out_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ReleasedStopsTable createAlias(String alias) {
    return $ReleasedStopsTable(attachedDatabase, alias);
  }
}

class ReleasedStop extends DataClass implements Insertable<ReleasedStop> {
  final String routeStopId;

  /// The server's `release_reason` (`LEFT_CAMPUS`, `LOCATION_SILENCE`, …).
  final String releaseReason;
  final bool appealable;

  /// Epoch milliseconds of the device scans this stop's outbox rows held.
  final int? localCheckInAt;
  final int? localCheckOutAt;

  /// Epoch milliseconds when the 409 was first seen.
  final int createdAt;
  const ReleasedStop({
    required this.routeStopId,
    required this.releaseReason,
    required this.appealable,
    this.localCheckInAt,
    this.localCheckOutAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['route_stop_id'] = Variable<String>(routeStopId);
    map['release_reason'] = Variable<String>(releaseReason);
    map['appealable'] = Variable<bool>(appealable);
    if (!nullToAbsent || localCheckInAt != null) {
      map['local_check_in_at'] = Variable<int>(localCheckInAt);
    }
    if (!nullToAbsent || localCheckOutAt != null) {
      map['local_check_out_at'] = Variable<int>(localCheckOutAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ReleasedStopsCompanion toCompanion(bool nullToAbsent) {
    return ReleasedStopsCompanion(
      routeStopId: Value(routeStopId),
      releaseReason: Value(releaseReason),
      appealable: Value(appealable),
      localCheckInAt: localCheckInAt == null && nullToAbsent
          ? const Value.absent()
          : Value(localCheckInAt),
      localCheckOutAt: localCheckOutAt == null && nullToAbsent
          ? const Value.absent()
          : Value(localCheckOutAt),
      createdAt: Value(createdAt),
    );
  }

  factory ReleasedStop.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReleasedStop(
      routeStopId: serializer.fromJson<String>(json['routeStopId']),
      releaseReason: serializer.fromJson<String>(json['releaseReason']),
      appealable: serializer.fromJson<bool>(json['appealable']),
      localCheckInAt: serializer.fromJson<int?>(json['localCheckInAt']),
      localCheckOutAt: serializer.fromJson<int?>(json['localCheckOutAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'routeStopId': serializer.toJson<String>(routeStopId),
      'releaseReason': serializer.toJson<String>(releaseReason),
      'appealable': serializer.toJson<bool>(appealable),
      'localCheckInAt': serializer.toJson<int?>(localCheckInAt),
      'localCheckOutAt': serializer.toJson<int?>(localCheckOutAt),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ReleasedStop copyWith({
    String? routeStopId,
    String? releaseReason,
    bool? appealable,
    Value<int?> localCheckInAt = const Value.absent(),
    Value<int?> localCheckOutAt = const Value.absent(),
    int? createdAt,
  }) => ReleasedStop(
    routeStopId: routeStopId ?? this.routeStopId,
    releaseReason: releaseReason ?? this.releaseReason,
    appealable: appealable ?? this.appealable,
    localCheckInAt: localCheckInAt.present
        ? localCheckInAt.value
        : this.localCheckInAt,
    localCheckOutAt: localCheckOutAt.present
        ? localCheckOutAt.value
        : this.localCheckOutAt,
    createdAt: createdAt ?? this.createdAt,
  );
  ReleasedStop copyWithCompanion(ReleasedStopsCompanion data) {
    return ReleasedStop(
      routeStopId: data.routeStopId.present
          ? data.routeStopId.value
          : this.routeStopId,
      releaseReason: data.releaseReason.present
          ? data.releaseReason.value
          : this.releaseReason,
      appealable: data.appealable.present
          ? data.appealable.value
          : this.appealable,
      localCheckInAt: data.localCheckInAt.present
          ? data.localCheckInAt.value
          : this.localCheckInAt,
      localCheckOutAt: data.localCheckOutAt.present
          ? data.localCheckOutAt.value
          : this.localCheckOutAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReleasedStop(')
          ..write('routeStopId: $routeStopId, ')
          ..write('releaseReason: $releaseReason, ')
          ..write('appealable: $appealable, ')
          ..write('localCheckInAt: $localCheckInAt, ')
          ..write('localCheckOutAt: $localCheckOutAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    routeStopId,
    releaseReason,
    appealable,
    localCheckInAt,
    localCheckOutAt,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReleasedStop &&
          other.routeStopId == this.routeStopId &&
          other.releaseReason == this.releaseReason &&
          other.appealable == this.appealable &&
          other.localCheckInAt == this.localCheckInAt &&
          other.localCheckOutAt == this.localCheckOutAt &&
          other.createdAt == this.createdAt);
}

class ReleasedStopsCompanion extends UpdateCompanion<ReleasedStop> {
  final Value<String> routeStopId;
  final Value<String> releaseReason;
  final Value<bool> appealable;
  final Value<int?> localCheckInAt;
  final Value<int?> localCheckOutAt;
  final Value<int> createdAt;
  final Value<int> rowid;
  const ReleasedStopsCompanion({
    this.routeStopId = const Value.absent(),
    this.releaseReason = const Value.absent(),
    this.appealable = const Value.absent(),
    this.localCheckInAt = const Value.absent(),
    this.localCheckOutAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReleasedStopsCompanion.insert({
    required String routeStopId,
    required String releaseReason,
    required bool appealable,
    this.localCheckInAt = const Value.absent(),
    this.localCheckOutAt = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : routeStopId = Value(routeStopId),
       releaseReason = Value(releaseReason),
       appealable = Value(appealable),
       createdAt = Value(createdAt);
  static Insertable<ReleasedStop> custom({
    Expression<String>? routeStopId,
    Expression<String>? releaseReason,
    Expression<bool>? appealable,
    Expression<int>? localCheckInAt,
    Expression<int>? localCheckOutAt,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (routeStopId != null) 'route_stop_id': routeStopId,
      if (releaseReason != null) 'release_reason': releaseReason,
      if (appealable != null) 'appealable': appealable,
      if (localCheckInAt != null) 'local_check_in_at': localCheckInAt,
      if (localCheckOutAt != null) 'local_check_out_at': localCheckOutAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReleasedStopsCompanion copyWith({
    Value<String>? routeStopId,
    Value<String>? releaseReason,
    Value<bool>? appealable,
    Value<int?>? localCheckInAt,
    Value<int?>? localCheckOutAt,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return ReleasedStopsCompanion(
      routeStopId: routeStopId ?? this.routeStopId,
      releaseReason: releaseReason ?? this.releaseReason,
      appealable: appealable ?? this.appealable,
      localCheckInAt: localCheckInAt ?? this.localCheckInAt,
      localCheckOutAt: localCheckOutAt ?? this.localCheckOutAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (routeStopId.present) {
      map['route_stop_id'] = Variable<String>(routeStopId.value);
    }
    if (releaseReason.present) {
      map['release_reason'] = Variable<String>(releaseReason.value);
    }
    if (appealable.present) {
      map['appealable'] = Variable<bool>(appealable.value);
    }
    if (localCheckInAt.present) {
      map['local_check_in_at'] = Variable<int>(localCheckInAt.value);
    }
    if (localCheckOutAt.present) {
      map['local_check_out_at'] = Variable<int>(localCheckOutAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReleasedStopsCompanion(')
          ..write('routeStopId: $routeStopId, ')
          ..write('releaseReason: $releaseReason, ')
          ..write('appealable: $appealable, ')
          ..write('localCheckInAt: $localCheckInAt, ')
          ..write('localCheckOutAt: $localCheckOutAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PendingOperationsTable pendingOperations =
      $PendingOperationsTable(this);
  late final $StopProgressTable stopProgress = $StopProgressTable(this);
  late final $SyncMetaTable syncMeta = $SyncMetaTable(this);
  late final $FormDraftItemsTable formDraftItems = $FormDraftItemsTable(this);
  late final $ReleasedStopsTable releasedStops = $ReleasedStopsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    pendingOperations,
    stopProgress,
    syncMeta,
    formDraftItems,
    releasedStops,
  ];
}

typedef $$PendingOperationsTableCreateCompanionBuilder =
    PendingOperationsCompanion Function({
      required String id,
      required String kind,
      required String routeId,
      required String payloadJson,
      required int createdAt,
      Value<String> state,
      Value<String?> lastError,
      Value<int> attempts,
      Value<int?> nextAttemptAt,
      Value<String?> releasedStopId,
      Value<int> rowid,
    });
typedef $$PendingOperationsTableUpdateCompanionBuilder =
    PendingOperationsCompanion Function({
      Value<String> id,
      Value<String> kind,
      Value<String> routeId,
      Value<String> payloadJson,
      Value<int> createdAt,
      Value<String> state,
      Value<String?> lastError,
      Value<int> attempts,
      Value<int?> nextAttemptAt,
      Value<String?> releasedStopId,
      Value<int> rowid,
    });

class $$PendingOperationsTableFilterComposer
    extends Composer<_$AppDatabase, $PendingOperationsTable> {
  $$PendingOperationsTableFilterComposer({
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

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get routeId => $composableBuilder(
    column: $table.routeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get releasedStopId => $composableBuilder(
    column: $table.releasedStopId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingOperationsTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingOperationsTable> {
  $$PendingOperationsTableOrderingComposer({
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

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get routeId => $composableBuilder(
    column: $table.routeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get releasedStopId => $composableBuilder(
    column: $table.releasedStopId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingOperationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingOperationsTable> {
  $$PendingOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get routeId =>
      $composableBuilder(column: $table.routeId, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get releasedStopId => $composableBuilder(
    column: $table.releasedStopId,
    builder: (column) => column,
  );
}

class $$PendingOperationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingOperationsTable,
          PendingOperation,
          $$PendingOperationsTableFilterComposer,
          $$PendingOperationsTableOrderingComposer,
          $$PendingOperationsTableAnnotationComposer,
          $$PendingOperationsTableCreateCompanionBuilder,
          $$PendingOperationsTableUpdateCompanionBuilder,
          (
            PendingOperation,
            BaseReferences<
              _$AppDatabase,
              $PendingOperationsTable,
              PendingOperation
            >,
          ),
          PendingOperation,
          PrefetchHooks Function()
        > {
  $$PendingOperationsTableTableManager(
    _$AppDatabase db,
    $PendingOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingOperationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> routeId = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int?> nextAttemptAt = const Value.absent(),
                Value<String?> releasedStopId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingOperationsCompanion(
                id: id,
                kind: kind,
                routeId: routeId,
                payloadJson: payloadJson,
                createdAt: createdAt,
                state: state,
                lastError: lastError,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                releasedStopId: releasedStopId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String kind,
                required String routeId,
                required String payloadJson,
                required int createdAt,
                Value<String> state = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int?> nextAttemptAt = const Value.absent(),
                Value<String?> releasedStopId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingOperationsCompanion.insert(
                id: id,
                kind: kind,
                routeId: routeId,
                payloadJson: payloadJson,
                createdAt: createdAt,
                state: state,
                lastError: lastError,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                releasedStopId: releasedStopId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingOperationsTable,
      PendingOperation,
      $$PendingOperationsTableFilterComposer,
      $$PendingOperationsTableOrderingComposer,
      $$PendingOperationsTableAnnotationComposer,
      $$PendingOperationsTableCreateCompanionBuilder,
      $$PendingOperationsTableUpdateCompanionBuilder,
      (
        PendingOperation,
        BaseReferences<
          _$AppDatabase,
          $PendingOperationsTable,
          PendingOperation
        >,
      ),
      PendingOperation,
      PrefetchHooks Function()
    >;
typedef $$StopProgressTableCreateCompanionBuilder =
    StopProgressCompanion Function({
      required String routeStopId,
      required String executionId,
      required String localStatus,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$StopProgressTableUpdateCompanionBuilder =
    StopProgressCompanion Function({
      Value<String> routeStopId,
      Value<String> executionId,
      Value<String> localStatus,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$StopProgressTableFilterComposer
    extends Composer<_$AppDatabase, $StopProgressTable> {
  $$StopProgressTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get routeStopId => $composableBuilder(
    column: $table.routeStopId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get executionId => $composableBuilder(
    column: $table.executionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localStatus => $composableBuilder(
    column: $table.localStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StopProgressTableOrderingComposer
    extends Composer<_$AppDatabase, $StopProgressTable> {
  $$StopProgressTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get routeStopId => $composableBuilder(
    column: $table.routeStopId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get executionId => $composableBuilder(
    column: $table.executionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localStatus => $composableBuilder(
    column: $table.localStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StopProgressTableAnnotationComposer
    extends Composer<_$AppDatabase, $StopProgressTable> {
  $$StopProgressTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get routeStopId => $composableBuilder(
    column: $table.routeStopId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get executionId => $composableBuilder(
    column: $table.executionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localStatus => $composableBuilder(
    column: $table.localStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$StopProgressTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StopProgressTable,
          StopProgressData,
          $$StopProgressTableFilterComposer,
          $$StopProgressTableOrderingComposer,
          $$StopProgressTableAnnotationComposer,
          $$StopProgressTableCreateCompanionBuilder,
          $$StopProgressTableUpdateCompanionBuilder,
          (
            StopProgressData,
            BaseReferences<_$AppDatabase, $StopProgressTable, StopProgressData>,
          ),
          StopProgressData,
          PrefetchHooks Function()
        > {
  $$StopProgressTableTableManager(_$AppDatabase db, $StopProgressTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StopProgressTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StopProgressTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StopProgressTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> routeStopId = const Value.absent(),
                Value<String> executionId = const Value.absent(),
                Value<String> localStatus = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StopProgressCompanion(
                routeStopId: routeStopId,
                executionId: executionId,
                localStatus: localStatus,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String routeStopId,
                required String executionId,
                required String localStatus,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => StopProgressCompanion.insert(
                routeStopId: routeStopId,
                executionId: executionId,
                localStatus: localStatus,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StopProgressTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StopProgressTable,
      StopProgressData,
      $$StopProgressTableFilterComposer,
      $$StopProgressTableOrderingComposer,
      $$StopProgressTableAnnotationComposer,
      $$StopProgressTableCreateCompanionBuilder,
      $$StopProgressTableUpdateCompanionBuilder,
      (
        StopProgressData,
        BaseReferences<_$AppDatabase, $StopProgressTable, StopProgressData>,
      ),
      StopProgressData,
      PrefetchHooks Function()
    >;
typedef $$SyncMetaTableCreateCompanionBuilder =
    SyncMetaCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SyncMetaTableUpdateCompanionBuilder =
    SyncMetaCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SyncMetaTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SyncMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncMetaTable,
          SyncMetaData,
          $$SyncMetaTableFilterComposer,
          $$SyncMetaTableOrderingComposer,
          $$SyncMetaTableAnnotationComposer,
          $$SyncMetaTableCreateCompanionBuilder,
          $$SyncMetaTableUpdateCompanionBuilder,
          (
            SyncMetaData,
            BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaData>,
          ),
          SyncMetaData,
          PrefetchHooks Function()
        > {
  $$SyncMetaTableTableManager(_$AppDatabase db, $SyncMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncMetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SyncMetaCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncMetaTable,
      SyncMetaData,
      $$SyncMetaTableFilterComposer,
      $$SyncMetaTableOrderingComposer,
      $$SyncMetaTableAnnotationComposer,
      $$SyncMetaTableCreateCompanionBuilder,
      $$SyncMetaTableUpdateCompanionBuilder,
      (
        SyncMetaData,
        BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaData>,
      ),
      SyncMetaData,
      PrefetchHooks Function()
    >;
typedef $$FormDraftItemsTableCreateCompanionBuilder =
    FormDraftItemsCompanion Function({
      required String executionId,
      required String stableKey,
      required String routeStopId,
      required String formVersionId,
      required int orderIndex,
      required String prompt,
      required String questionType,
      required bool required,
      required String optionsJson,
      required String contentHash,
      Value<String?> valueJson,
      Value<bool> needsReanswer,
      Value<int> rowid,
    });
typedef $$FormDraftItemsTableUpdateCompanionBuilder =
    FormDraftItemsCompanion Function({
      Value<String> executionId,
      Value<String> stableKey,
      Value<String> routeStopId,
      Value<String> formVersionId,
      Value<int> orderIndex,
      Value<String> prompt,
      Value<String> questionType,
      Value<bool> required,
      Value<String> optionsJson,
      Value<String> contentHash,
      Value<String?> valueJson,
      Value<bool> needsReanswer,
      Value<int> rowid,
    });

class $$FormDraftItemsTableFilterComposer
    extends Composer<_$AppDatabase, $FormDraftItemsTable> {
  $$FormDraftItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get executionId => $composableBuilder(
    column: $table.executionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stableKey => $composableBuilder(
    column: $table.stableKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get routeStopId => $composableBuilder(
    column: $table.routeStopId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get formVersionId => $composableBuilder(
    column: $table.formVersionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get prompt => $composableBuilder(
    column: $table.prompt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get questionType => $composableBuilder(
    column: $table.questionType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get required => $composableBuilder(
    column: $table.required,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get optionsJson => $composableBuilder(
    column: $table.optionsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get needsReanswer => $composableBuilder(
    column: $table.needsReanswer,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FormDraftItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $FormDraftItemsTable> {
  $$FormDraftItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get executionId => $composableBuilder(
    column: $table.executionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stableKey => $composableBuilder(
    column: $table.stableKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get routeStopId => $composableBuilder(
    column: $table.routeStopId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get formVersionId => $composableBuilder(
    column: $table.formVersionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get prompt => $composableBuilder(
    column: $table.prompt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get questionType => $composableBuilder(
    column: $table.questionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get required => $composableBuilder(
    column: $table.required,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get optionsJson => $composableBuilder(
    column: $table.optionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get needsReanswer => $composableBuilder(
    column: $table.needsReanswer,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FormDraftItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FormDraftItemsTable> {
  $$FormDraftItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get executionId => $composableBuilder(
    column: $table.executionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stableKey =>
      $composableBuilder(column: $table.stableKey, builder: (column) => column);

  GeneratedColumn<String> get routeStopId => $composableBuilder(
    column: $table.routeStopId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get formVersionId => $composableBuilder(
    column: $table.formVersionId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get prompt =>
      $composableBuilder(column: $table.prompt, builder: (column) => column);

  GeneratedColumn<String> get questionType => $composableBuilder(
    column: $table.questionType,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get required =>
      $composableBuilder(column: $table.required, builder: (column) => column);

  GeneratedColumn<String> get optionsJson => $composableBuilder(
    column: $table.optionsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get valueJson =>
      $composableBuilder(column: $table.valueJson, builder: (column) => column);

  GeneratedColumn<bool> get needsReanswer => $composableBuilder(
    column: $table.needsReanswer,
    builder: (column) => column,
  );
}

class $$FormDraftItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FormDraftItemsTable,
          FormDraftItem,
          $$FormDraftItemsTableFilterComposer,
          $$FormDraftItemsTableOrderingComposer,
          $$FormDraftItemsTableAnnotationComposer,
          $$FormDraftItemsTableCreateCompanionBuilder,
          $$FormDraftItemsTableUpdateCompanionBuilder,
          (
            FormDraftItem,
            BaseReferences<_$AppDatabase, $FormDraftItemsTable, FormDraftItem>,
          ),
          FormDraftItem,
          PrefetchHooks Function()
        > {
  $$FormDraftItemsTableTableManager(
    _$AppDatabase db,
    $FormDraftItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FormDraftItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FormDraftItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FormDraftItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> executionId = const Value.absent(),
                Value<String> stableKey = const Value.absent(),
                Value<String> routeStopId = const Value.absent(),
                Value<String> formVersionId = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
                Value<String> prompt = const Value.absent(),
                Value<String> questionType = const Value.absent(),
                Value<bool> required = const Value.absent(),
                Value<String> optionsJson = const Value.absent(),
                Value<String> contentHash = const Value.absent(),
                Value<String?> valueJson = const Value.absent(),
                Value<bool> needsReanswer = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FormDraftItemsCompanion(
                executionId: executionId,
                stableKey: stableKey,
                routeStopId: routeStopId,
                formVersionId: formVersionId,
                orderIndex: orderIndex,
                prompt: prompt,
                questionType: questionType,
                required: required,
                optionsJson: optionsJson,
                contentHash: contentHash,
                valueJson: valueJson,
                needsReanswer: needsReanswer,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String executionId,
                required String stableKey,
                required String routeStopId,
                required String formVersionId,
                required int orderIndex,
                required String prompt,
                required String questionType,
                required bool required,
                required String optionsJson,
                required String contentHash,
                Value<String?> valueJson = const Value.absent(),
                Value<bool> needsReanswer = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FormDraftItemsCompanion.insert(
                executionId: executionId,
                stableKey: stableKey,
                routeStopId: routeStopId,
                formVersionId: formVersionId,
                orderIndex: orderIndex,
                prompt: prompt,
                questionType: questionType,
                required: required,
                optionsJson: optionsJson,
                contentHash: contentHash,
                valueJson: valueJson,
                needsReanswer: needsReanswer,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FormDraftItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FormDraftItemsTable,
      FormDraftItem,
      $$FormDraftItemsTableFilterComposer,
      $$FormDraftItemsTableOrderingComposer,
      $$FormDraftItemsTableAnnotationComposer,
      $$FormDraftItemsTableCreateCompanionBuilder,
      $$FormDraftItemsTableUpdateCompanionBuilder,
      (
        FormDraftItem,
        BaseReferences<_$AppDatabase, $FormDraftItemsTable, FormDraftItem>,
      ),
      FormDraftItem,
      PrefetchHooks Function()
    >;
typedef $$ReleasedStopsTableCreateCompanionBuilder =
    ReleasedStopsCompanion Function({
      required String routeStopId,
      required String releaseReason,
      required bool appealable,
      Value<int?> localCheckInAt,
      Value<int?> localCheckOutAt,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$ReleasedStopsTableUpdateCompanionBuilder =
    ReleasedStopsCompanion Function({
      Value<String> routeStopId,
      Value<String> releaseReason,
      Value<bool> appealable,
      Value<int?> localCheckInAt,
      Value<int?> localCheckOutAt,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$ReleasedStopsTableFilterComposer
    extends Composer<_$AppDatabase, $ReleasedStopsTable> {
  $$ReleasedStopsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get routeStopId => $composableBuilder(
    column: $table.routeStopId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get releaseReason => $composableBuilder(
    column: $table.releaseReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get appealable => $composableBuilder(
    column: $table.appealable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localCheckInAt => $composableBuilder(
    column: $table.localCheckInAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localCheckOutAt => $composableBuilder(
    column: $table.localCheckOutAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReleasedStopsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReleasedStopsTable> {
  $$ReleasedStopsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get routeStopId => $composableBuilder(
    column: $table.routeStopId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get releaseReason => $composableBuilder(
    column: $table.releaseReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get appealable => $composableBuilder(
    column: $table.appealable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localCheckInAt => $composableBuilder(
    column: $table.localCheckInAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localCheckOutAt => $composableBuilder(
    column: $table.localCheckOutAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReleasedStopsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReleasedStopsTable> {
  $$ReleasedStopsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get routeStopId => $composableBuilder(
    column: $table.routeStopId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get releaseReason => $composableBuilder(
    column: $table.releaseReason,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get appealable => $composableBuilder(
    column: $table.appealable,
    builder: (column) => column,
  );

  GeneratedColumn<int> get localCheckInAt => $composableBuilder(
    column: $table.localCheckInAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get localCheckOutAt => $composableBuilder(
    column: $table.localCheckOutAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ReleasedStopsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReleasedStopsTable,
          ReleasedStop,
          $$ReleasedStopsTableFilterComposer,
          $$ReleasedStopsTableOrderingComposer,
          $$ReleasedStopsTableAnnotationComposer,
          $$ReleasedStopsTableCreateCompanionBuilder,
          $$ReleasedStopsTableUpdateCompanionBuilder,
          (
            ReleasedStop,
            BaseReferences<_$AppDatabase, $ReleasedStopsTable, ReleasedStop>,
          ),
          ReleasedStop,
          PrefetchHooks Function()
        > {
  $$ReleasedStopsTableTableManager(_$AppDatabase db, $ReleasedStopsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReleasedStopsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReleasedStopsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReleasedStopsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> routeStopId = const Value.absent(),
                Value<String> releaseReason = const Value.absent(),
                Value<bool> appealable = const Value.absent(),
                Value<int?> localCheckInAt = const Value.absent(),
                Value<int?> localCheckOutAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReleasedStopsCompanion(
                routeStopId: routeStopId,
                releaseReason: releaseReason,
                appealable: appealable,
                localCheckInAt: localCheckInAt,
                localCheckOutAt: localCheckOutAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String routeStopId,
                required String releaseReason,
                required bool appealable,
                Value<int?> localCheckInAt = const Value.absent(),
                Value<int?> localCheckOutAt = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ReleasedStopsCompanion.insert(
                routeStopId: routeStopId,
                releaseReason: releaseReason,
                appealable: appealable,
                localCheckInAt: localCheckInAt,
                localCheckOutAt: localCheckOutAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReleasedStopsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReleasedStopsTable,
      ReleasedStop,
      $$ReleasedStopsTableFilterComposer,
      $$ReleasedStopsTableOrderingComposer,
      $$ReleasedStopsTableAnnotationComposer,
      $$ReleasedStopsTableCreateCompanionBuilder,
      $$ReleasedStopsTableUpdateCompanionBuilder,
      (
        ReleasedStop,
        BaseReferences<_$AppDatabase, $ReleasedStopsTable, ReleasedStop>,
      ),
      ReleasedStop,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PendingOperationsTableTableManager get pendingOperations =>
      $$PendingOperationsTableTableManager(_db, _db.pendingOperations);
  $$StopProgressTableTableManager get stopProgress =>
      $$StopProgressTableTableManager(_db, _db.stopProgress);
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db, _db.syncMeta);
  $$FormDraftItemsTableTableManager get formDraftItems =>
      $$FormDraftItemsTableTableManager(_db, _db.formDraftItems);
  $$ReleasedStopsTableTableManager get releasedStops =>
      $$ReleasedStopsTableTableManager(_db, _db.releasedStops);
}
