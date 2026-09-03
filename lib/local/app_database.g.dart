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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    routeId,
    payloadJson,
    createdAt,
    state,
    lastError,
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
  const PendingOperation({
    required this.id,
    required this.kind,
    required this.routeId,
    required this.payloadJson,
    required this.createdAt,
    required this.state,
    this.lastError,
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
  }) => PendingOperation(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    routeId: routeId ?? this.routeId,
    payloadJson: payloadJson ?? this.payloadJson,
    createdAt: createdAt ?? this.createdAt,
    state: state ?? this.state,
    lastError: lastError.present ? lastError.value : this.lastError,
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
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, kind, routeId, payloadJson, createdAt, state, lastError);
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
          other.lastError == this.lastError);
}

class PendingOperationsCompanion extends UpdateCompanion<PendingOperation> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String> routeId;
  final Value<String> payloadJson;
  final Value<int> createdAt;
  final Value<String> state;
  final Value<String?> lastError;
  final Value<int> rowid;
  const PendingOperationsCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.routeId = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.state = const Value.absent(),
    this.lastError = const Value.absent(),
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
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OpenExecutionsTable extends OpenExecutions
    with TableInfo<$OpenExecutionsTable, OpenExecution> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OpenExecutionsTable(this.attachedDatabase, [this._alias]);
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
  @override
  List<GeneratedColumn> get $columns => [routeStopId, executionId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'open_executions';
  @override
  VerificationContext validateIntegrity(
    Insertable<OpenExecution> instance, {
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {routeStopId};
  @override
  OpenExecution map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OpenExecution(
      routeStopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route_stop_id'],
      )!,
      executionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}execution_id'],
      )!,
    );
  }

  @override
  $OpenExecutionsTable createAlias(String alias) {
    return $OpenExecutionsTable(attachedDatabase, alias);
  }
}

class OpenExecution extends DataClass implements Insertable<OpenExecution> {
  final String routeStopId;
  final String executionId;
  const OpenExecution({required this.routeStopId, required this.executionId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['route_stop_id'] = Variable<String>(routeStopId);
    map['execution_id'] = Variable<String>(executionId);
    return map;
  }

  OpenExecutionsCompanion toCompanion(bool nullToAbsent) {
    return OpenExecutionsCompanion(
      routeStopId: Value(routeStopId),
      executionId: Value(executionId),
    );
  }

  factory OpenExecution.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OpenExecution(
      routeStopId: serializer.fromJson<String>(json['routeStopId']),
      executionId: serializer.fromJson<String>(json['executionId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'routeStopId': serializer.toJson<String>(routeStopId),
      'executionId': serializer.toJson<String>(executionId),
    };
  }

  OpenExecution copyWith({String? routeStopId, String? executionId}) =>
      OpenExecution(
        routeStopId: routeStopId ?? this.routeStopId,
        executionId: executionId ?? this.executionId,
      );
  OpenExecution copyWithCompanion(OpenExecutionsCompanion data) {
    return OpenExecution(
      routeStopId: data.routeStopId.present
          ? data.routeStopId.value
          : this.routeStopId,
      executionId: data.executionId.present
          ? data.executionId.value
          : this.executionId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OpenExecution(')
          ..write('routeStopId: $routeStopId, ')
          ..write('executionId: $executionId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(routeStopId, executionId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OpenExecution &&
          other.routeStopId == this.routeStopId &&
          other.executionId == this.executionId);
}

class OpenExecutionsCompanion extends UpdateCompanion<OpenExecution> {
  final Value<String> routeStopId;
  final Value<String> executionId;
  final Value<int> rowid;
  const OpenExecutionsCompanion({
    this.routeStopId = const Value.absent(),
    this.executionId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OpenExecutionsCompanion.insert({
    required String routeStopId,
    required String executionId,
    this.rowid = const Value.absent(),
  }) : routeStopId = Value(routeStopId),
       executionId = Value(executionId);
  static Insertable<OpenExecution> custom({
    Expression<String>? routeStopId,
    Expression<String>? executionId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (routeStopId != null) 'route_stop_id': routeStopId,
      if (executionId != null) 'execution_id': executionId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OpenExecutionsCompanion copyWith({
    Value<String>? routeStopId,
    Value<String>? executionId,
    Value<int>? rowid,
  }) {
    return OpenExecutionsCompanion(
      routeStopId: routeStopId ?? this.routeStopId,
      executionId: executionId ?? this.executionId,
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
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OpenExecutionsCompanion(')
          ..write('routeStopId: $routeStopId, ')
          ..write('executionId: $executionId, ')
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
  late final $OpenExecutionsTable openExecutions = $OpenExecutionsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    pendingOperations,
    openExecutions,
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
                Value<int> rowid = const Value.absent(),
              }) => PendingOperationsCompanion(
                id: id,
                kind: kind,
                routeId: routeId,
                payloadJson: payloadJson,
                createdAt: createdAt,
                state: state,
                lastError: lastError,
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
                Value<int> rowid = const Value.absent(),
              }) => PendingOperationsCompanion.insert(
                id: id,
                kind: kind,
                routeId: routeId,
                payloadJson: payloadJson,
                createdAt: createdAt,
                state: state,
                lastError: lastError,
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
typedef $$OpenExecutionsTableCreateCompanionBuilder =
    OpenExecutionsCompanion Function({
      required String routeStopId,
      required String executionId,
      Value<int> rowid,
    });
typedef $$OpenExecutionsTableUpdateCompanionBuilder =
    OpenExecutionsCompanion Function({
      Value<String> routeStopId,
      Value<String> executionId,
      Value<int> rowid,
    });

class $$OpenExecutionsTableFilterComposer
    extends Composer<_$AppDatabase, $OpenExecutionsTable> {
  $$OpenExecutionsTableFilterComposer({
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
}

class $$OpenExecutionsTableOrderingComposer
    extends Composer<_$AppDatabase, $OpenExecutionsTable> {
  $$OpenExecutionsTableOrderingComposer({
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
}

class $$OpenExecutionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OpenExecutionsTable> {
  $$OpenExecutionsTableAnnotationComposer({
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
}

class $$OpenExecutionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OpenExecutionsTable,
          OpenExecution,
          $$OpenExecutionsTableFilterComposer,
          $$OpenExecutionsTableOrderingComposer,
          $$OpenExecutionsTableAnnotationComposer,
          $$OpenExecutionsTableCreateCompanionBuilder,
          $$OpenExecutionsTableUpdateCompanionBuilder,
          (
            OpenExecution,
            BaseReferences<_$AppDatabase, $OpenExecutionsTable, OpenExecution>,
          ),
          OpenExecution,
          PrefetchHooks Function()
        > {
  $$OpenExecutionsTableTableManager(
    _$AppDatabase db,
    $OpenExecutionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OpenExecutionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OpenExecutionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OpenExecutionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> routeStopId = const Value.absent(),
                Value<String> executionId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OpenExecutionsCompanion(
                routeStopId: routeStopId,
                executionId: executionId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String routeStopId,
                required String executionId,
                Value<int> rowid = const Value.absent(),
              }) => OpenExecutionsCompanion.insert(
                routeStopId: routeStopId,
                executionId: executionId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OpenExecutionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OpenExecutionsTable,
      OpenExecution,
      $$OpenExecutionsTableFilterComposer,
      $$OpenExecutionsTableOrderingComposer,
      $$OpenExecutionsTableAnnotationComposer,
      $$OpenExecutionsTableCreateCompanionBuilder,
      $$OpenExecutionsTableUpdateCompanionBuilder,
      (
        OpenExecution,
        BaseReferences<_$AppDatabase, $OpenExecutionsTable, OpenExecution>,
      ),
      OpenExecution,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PendingOperationsTableTableManager get pendingOperations =>
      $$PendingOperationsTableTableManager(_db, _db.pendingOperations);
  $$OpenExecutionsTableTableManager get openExecutions =>
      $$OpenExecutionsTableTableManager(_db, _db.openExecutions);
}
