// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $StoredSessionsTable extends StoredSessions
    with TableInfo<$StoredSessionsTable, StoredSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _manifestJsonMeta = const VerificationMeta(
    'manifestJson',
  );
  @override
  late final GeneratedColumn<String> manifestJson = GeneratedColumn<String>(
    'manifest_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _decisionsJsonMeta = const VerificationMeta(
    'decisionsJson',
  );
  @override
  late final GeneratedColumn<String> decisionsJson = GeneratedColumn<String>(
    'decisions_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _framesJsonMeta = const VerificationMeta(
    'framesJson',
  );
  @override
  late final GeneratedColumn<String> framesJson = GeneratedColumn<String>(
    'frames_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checksumMeta = const VerificationMeta(
    'checksum',
  );
  @override
  late final GeneratedColumn<String> checksum = GeneratedColumn<String>(
    'checksum',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawPathMeta = const VerificationMeta(
    'rawPath',
  );
  @override
  late final GeneratedColumn<String> rawPath = GeneratedColumn<String>(
    'raw_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    origin,
    mode,
    manifestJson,
    decisionsJson,
    framesJson,
    status,
    checksum,
    rawPath,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    } else if (isInserting) {
      context.missing(_originMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('manifest_json')) {
      context.handle(
        _manifestJsonMeta,
        manifestJson.isAcceptableOrUnknown(
          data['manifest_json']!,
          _manifestJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_manifestJsonMeta);
    }
    if (data.containsKey('decisions_json')) {
      context.handle(
        _decisionsJsonMeta,
        decisionsJson.isAcceptableOrUnknown(
          data['decisions_json']!,
          _decisionsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_decisionsJsonMeta);
    }
    if (data.containsKey('frames_json')) {
      context.handle(
        _framesJsonMeta,
        framesJson.isAcceptableOrUnknown(data['frames_json']!, _framesJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_framesJsonMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('checksum')) {
      context.handle(
        _checksumMeta,
        checksum.isAcceptableOrUnknown(data['checksum']!, _checksumMeta),
      );
    } else if (isInserting) {
      context.missing(_checksumMeta);
    }
    if (data.containsKey('raw_path')) {
      context.handle(
        _rawPathMeta,
        rawPath.isAcceptableOrUnknown(data['raw_path']!, _rawPathMeta),
      );
    } else if (isInserting) {
      context.missing(_rawPathMeta);
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StoredSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      manifestJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manifest_json'],
      )!,
      decisionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}decisions_json'],
      )!,
      framesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}frames_json'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      checksum: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checksum'],
      )!,
      rawPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_path'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $StoredSessionsTable createAlias(String alias) {
    return $StoredSessionsTable(attachedDatabase, alias);
  }
}

class StoredSession extends DataClass implements Insertable<StoredSession> {
  final String id;
  final String origin;
  final String mode;
  final String manifestJson;
  final String decisionsJson;
  final String framesJson;
  final String status;
  final String checksum;
  final String rawPath;
  final DateTime createdAt;
  const StoredSession({
    required this.id,
    required this.origin,
    required this.mode,
    required this.manifestJson,
    required this.decisionsJson,
    required this.framesJson,
    required this.status,
    required this.checksum,
    required this.rawPath,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['origin'] = Variable<String>(origin);
    map['mode'] = Variable<String>(mode);
    map['manifest_json'] = Variable<String>(manifestJson);
    map['decisions_json'] = Variable<String>(decisionsJson);
    map['frames_json'] = Variable<String>(framesJson);
    map['status'] = Variable<String>(status);
    map['checksum'] = Variable<String>(checksum);
    map['raw_path'] = Variable<String>(rawPath);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  StoredSessionsCompanion toCompanion(bool nullToAbsent) {
    return StoredSessionsCompanion(
      id: Value(id),
      origin: Value(origin),
      mode: Value(mode),
      manifestJson: Value(manifestJson),
      decisionsJson: Value(decisionsJson),
      framesJson: Value(framesJson),
      status: Value(status),
      checksum: Value(checksum),
      rawPath: Value(rawPath),
      createdAt: Value(createdAt),
    );
  }

  factory StoredSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredSession(
      id: serializer.fromJson<String>(json['id']),
      origin: serializer.fromJson<String>(json['origin']),
      mode: serializer.fromJson<String>(json['mode']),
      manifestJson: serializer.fromJson<String>(json['manifestJson']),
      decisionsJson: serializer.fromJson<String>(json['decisionsJson']),
      framesJson: serializer.fromJson<String>(json['framesJson']),
      status: serializer.fromJson<String>(json['status']),
      checksum: serializer.fromJson<String>(json['checksum']),
      rawPath: serializer.fromJson<String>(json['rawPath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'origin': serializer.toJson<String>(origin),
      'mode': serializer.toJson<String>(mode),
      'manifestJson': serializer.toJson<String>(manifestJson),
      'decisionsJson': serializer.toJson<String>(decisionsJson),
      'framesJson': serializer.toJson<String>(framesJson),
      'status': serializer.toJson<String>(status),
      'checksum': serializer.toJson<String>(checksum),
      'rawPath': serializer.toJson<String>(rawPath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  StoredSession copyWith({
    String? id,
    String? origin,
    String? mode,
    String? manifestJson,
    String? decisionsJson,
    String? framesJson,
    String? status,
    String? checksum,
    String? rawPath,
    DateTime? createdAt,
  }) => StoredSession(
    id: id ?? this.id,
    origin: origin ?? this.origin,
    mode: mode ?? this.mode,
    manifestJson: manifestJson ?? this.manifestJson,
    decisionsJson: decisionsJson ?? this.decisionsJson,
    framesJson: framesJson ?? this.framesJson,
    status: status ?? this.status,
    checksum: checksum ?? this.checksum,
    rawPath: rawPath ?? this.rawPath,
    createdAt: createdAt ?? this.createdAt,
  );
  StoredSession copyWithCompanion(StoredSessionsCompanion data) {
    return StoredSession(
      id: data.id.present ? data.id.value : this.id,
      origin: data.origin.present ? data.origin.value : this.origin,
      mode: data.mode.present ? data.mode.value : this.mode,
      manifestJson: data.manifestJson.present
          ? data.manifestJson.value
          : this.manifestJson,
      decisionsJson: data.decisionsJson.present
          ? data.decisionsJson.value
          : this.decisionsJson,
      framesJson: data.framesJson.present
          ? data.framesJson.value
          : this.framesJson,
      status: data.status.present ? data.status.value : this.status,
      checksum: data.checksum.present ? data.checksum.value : this.checksum,
      rawPath: data.rawPath.present ? data.rawPath.value : this.rawPath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredSession(')
          ..write('id: $id, ')
          ..write('origin: $origin, ')
          ..write('mode: $mode, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('decisionsJson: $decisionsJson, ')
          ..write('framesJson: $framesJson, ')
          ..write('status: $status, ')
          ..write('checksum: $checksum, ')
          ..write('rawPath: $rawPath, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    origin,
    mode,
    manifestJson,
    decisionsJson,
    framesJson,
    status,
    checksum,
    rawPath,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredSession &&
          other.id == this.id &&
          other.origin == this.origin &&
          other.mode == this.mode &&
          other.manifestJson == this.manifestJson &&
          other.decisionsJson == this.decisionsJson &&
          other.framesJson == this.framesJson &&
          other.status == this.status &&
          other.checksum == this.checksum &&
          other.rawPath == this.rawPath &&
          other.createdAt == this.createdAt);
}

class StoredSessionsCompanion extends UpdateCompanion<StoredSession> {
  final Value<String> id;
  final Value<String> origin;
  final Value<String> mode;
  final Value<String> manifestJson;
  final Value<String> decisionsJson;
  final Value<String> framesJson;
  final Value<String> status;
  final Value<String> checksum;
  final Value<String> rawPath;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const StoredSessionsCompanion({
    this.id = const Value.absent(),
    this.origin = const Value.absent(),
    this.mode = const Value.absent(),
    this.manifestJson = const Value.absent(),
    this.decisionsJson = const Value.absent(),
    this.framesJson = const Value.absent(),
    this.status = const Value.absent(),
    this.checksum = const Value.absent(),
    this.rawPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredSessionsCompanion.insert({
    required String id,
    required String origin,
    required String mode,
    required String manifestJson,
    required String decisionsJson,
    required String framesJson,
    required String status,
    required String checksum,
    required String rawPath,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       origin = Value(origin),
       mode = Value(mode),
       manifestJson = Value(manifestJson),
       decisionsJson = Value(decisionsJson),
       framesJson = Value(framesJson),
       status = Value(status),
       checksum = Value(checksum),
       rawPath = Value(rawPath),
       createdAt = Value(createdAt);
  static Insertable<StoredSession> custom({
    Expression<String>? id,
    Expression<String>? origin,
    Expression<String>? mode,
    Expression<String>? manifestJson,
    Expression<String>? decisionsJson,
    Expression<String>? framesJson,
    Expression<String>? status,
    Expression<String>? checksum,
    Expression<String>? rawPath,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (origin != null) 'origin': origin,
      if (mode != null) 'mode': mode,
      if (manifestJson != null) 'manifest_json': manifestJson,
      if (decisionsJson != null) 'decisions_json': decisionsJson,
      if (framesJson != null) 'frames_json': framesJson,
      if (status != null) 'status': status,
      if (checksum != null) 'checksum': checksum,
      if (rawPath != null) 'raw_path': rawPath,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredSessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? origin,
    Value<String>? mode,
    Value<String>? manifestJson,
    Value<String>? decisionsJson,
    Value<String>? framesJson,
    Value<String>? status,
    Value<String>? checksum,
    Value<String>? rawPath,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return StoredSessionsCompanion(
      id: id ?? this.id,
      origin: origin ?? this.origin,
      mode: mode ?? this.mode,
      manifestJson: manifestJson ?? this.manifestJson,
      decisionsJson: decisionsJson ?? this.decisionsJson,
      framesJson: framesJson ?? this.framesJson,
      status: status ?? this.status,
      checksum: checksum ?? this.checksum,
      rawPath: rawPath ?? this.rawPath,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (manifestJson.present) {
      map['manifest_json'] = Variable<String>(manifestJson.value);
    }
    if (decisionsJson.present) {
      map['decisions_json'] = Variable<String>(decisionsJson.value);
    }
    if (framesJson.present) {
      map['frames_json'] = Variable<String>(framesJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (checksum.present) {
      map['checksum'] = Variable<String>(checksum.value);
    }
    if (rawPath.present) {
      map['raw_path'] = Variable<String>(rawPath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredSessionsCompanion(')
          ..write('id: $id, ')
          ..write('origin: $origin, ')
          ..write('mode: $mode, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('decisionsJson: $decisionsJson, ')
          ..write('framesJson: $framesJson, ')
          ..write('status: $status, ')
          ..write('checksum: $checksum, ')
          ..write('rawPath: $rawPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UploadJobsTable extends UploadJobs
    with TableInfo<$UploadJobsTable, UploadJob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UploadJobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checksumMeta = const VerificationMeta(
    'checksum',
  );
  @override
  late final GeneratedColumn<String> checksum = GeneratedColumn<String>(
    'checksum',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadPathMeta = const VerificationMeta(
    'payloadPath',
  );
  @override
  late final GeneratedColumn<String> payloadPath = GeneratedColumn<String>(
    'payload_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    sessionId,
    checksum,
    payloadPath,
    state,
    attempts,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'upload_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<UploadJob> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('checksum')) {
      context.handle(
        _checksumMeta,
        checksum.isAcceptableOrUnknown(data['checksum']!, _checksumMeta),
      );
    } else if (isInserting) {
      context.missing(_checksumMeta);
    }
    if (data.containsKey('payload_path')) {
      context.handle(
        _payloadPathMeta,
        payloadPath.isAcceptableOrUnknown(
          data['payload_path']!,
          _payloadPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadPathMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
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
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  UploadJob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UploadJob(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      checksum: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checksum'],
      )!,
      payloadPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_path'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $UploadJobsTable createAlias(String alias) {
    return $UploadJobsTable(attachedDatabase, alias);
  }
}

class UploadJob extends DataClass implements Insertable<UploadJob> {
  final String sessionId;
  final String checksum;
  final String payloadPath;
  final String state;
  final int attempts;
  final String? lastError;
  const UploadJob({
    required this.sessionId,
    required this.checksum,
    required this.payloadPath,
    required this.state,
    required this.attempts,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['checksum'] = Variable<String>(checksum);
    map['payload_path'] = Variable<String>(payloadPath);
    map['state'] = Variable<String>(state);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  UploadJobsCompanion toCompanion(bool nullToAbsent) {
    return UploadJobsCompanion(
      sessionId: Value(sessionId),
      checksum: Value(checksum),
      payloadPath: Value(payloadPath),
      state: Value(state),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory UploadJob.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UploadJob(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      checksum: serializer.fromJson<String>(json['checksum']),
      payloadPath: serializer.fromJson<String>(json['payloadPath']),
      state: serializer.fromJson<String>(json['state']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'checksum': serializer.toJson<String>(checksum),
      'payloadPath': serializer.toJson<String>(payloadPath),
      'state': serializer.toJson<String>(state),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  UploadJob copyWith({
    String? sessionId,
    String? checksum,
    String? payloadPath,
    String? state,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
  }) => UploadJob(
    sessionId: sessionId ?? this.sessionId,
    checksum: checksum ?? this.checksum,
    payloadPath: payloadPath ?? this.payloadPath,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  UploadJob copyWithCompanion(UploadJobsCompanion data) {
    return UploadJob(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      checksum: data.checksum.present ? data.checksum.value : this.checksum,
      payloadPath: data.payloadPath.present
          ? data.payloadPath.value
          : this.payloadPath,
      state: data.state.present ? data.state.value : this.state,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UploadJob(')
          ..write('sessionId: $sessionId, ')
          ..write('checksum: $checksum, ')
          ..write('payloadPath: $payloadPath, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sessionId, checksum, payloadPath, state, attempts, lastError);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UploadJob &&
          other.sessionId == this.sessionId &&
          other.checksum == this.checksum &&
          other.payloadPath == this.payloadPath &&
          other.state == this.state &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError);
}

class UploadJobsCompanion extends UpdateCompanion<UploadJob> {
  final Value<String> sessionId;
  final Value<String> checksum;
  final Value<String> payloadPath;
  final Value<String> state;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<int> rowid;
  const UploadJobsCompanion({
    this.sessionId = const Value.absent(),
    this.checksum = const Value.absent(),
    this.payloadPath = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UploadJobsCompanion.insert({
    required String sessionId,
    required String checksum,
    required String payloadPath,
    required String state,
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       checksum = Value(checksum),
       payloadPath = Value(payloadPath),
       state = Value(state);
  static Insertable<UploadJob> custom({
    Expression<String>? sessionId,
    Expression<String>? checksum,
    Expression<String>? payloadPath,
    Expression<String>? state,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (checksum != null) 'checksum': checksum,
      if (payloadPath != null) 'payload_path': payloadPath,
      if (state != null) 'state': state,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UploadJobsCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? checksum,
    Value<String>? payloadPath,
    Value<String>? state,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return UploadJobsCompanion(
      sessionId: sessionId ?? this.sessionId,
      checksum: checksum ?? this.checksum,
      payloadPath: payloadPath ?? this.payloadPath,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (checksum.present) {
      map['checksum'] = Variable<String>(checksum.value);
    }
    if (payloadPath.present) {
      map['payload_path'] = Variable<String>(payloadPath.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
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
    return (StringBuffer('UploadJobsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('checksum: $checksum, ')
          ..write('payloadPath: $payloadPath, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KvStoreTable extends KvStore with TableInfo<$KvStoreTable, KvStoreData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KvStoreTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'kv_store';
  @override
  VerificationContext validateIntegrity(
    Insertable<KvStoreData> instance, {
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
  KvStoreData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KvStoreData(
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
  $KvStoreTable createAlias(String alias) {
    return $KvStoreTable(attachedDatabase, alias);
  }
}

class KvStoreData extends DataClass implements Insertable<KvStoreData> {
  final String key;
  final String value;
  const KvStoreData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  KvStoreCompanion toCompanion(bool nullToAbsent) {
    return KvStoreCompanion(key: Value(key), value: Value(value));
  }

  factory KvStoreData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KvStoreData(
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

  KvStoreData copyWith({String? key, String? value}) =>
      KvStoreData(key: key ?? this.key, value: value ?? this.value);
  KvStoreData copyWithCompanion(KvStoreCompanion data) {
    return KvStoreData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KvStoreData(')
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
      (other is KvStoreData &&
          other.key == this.key &&
          other.value == this.value);
}

class KvStoreCompanion extends UpdateCompanion<KvStoreData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const KvStoreCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KvStoreCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<KvStoreData> custom({
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

  KvStoreCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return KvStoreCompanion(
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
    return (StringBuffer('KvStoreCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $StoredSessionsTable storedSessions = $StoredSessionsTable(this);
  late final $UploadJobsTable uploadJobs = $UploadJobsTable(this);
  late final $KvStoreTable kvStore = $KvStoreTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    storedSessions,
    uploadJobs,
    kvStore,
  ];
}

typedef $$StoredSessionsTableCreateCompanionBuilder =
    StoredSessionsCompanion Function({
      required String id,
      required String origin,
      required String mode,
      required String manifestJson,
      required String decisionsJson,
      required String framesJson,
      required String status,
      required String checksum,
      required String rawPath,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$StoredSessionsTableUpdateCompanionBuilder =
    StoredSessionsCompanion Function({
      Value<String> id,
      Value<String> origin,
      Value<String> mode,
      Value<String> manifestJson,
      Value<String> decisionsJson,
      Value<String> framesJson,
      Value<String> status,
      Value<String> checksum,
      Value<String> rawPath,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$StoredSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $StoredSessionsTable> {
  $$StoredSessionsTableFilterComposer({
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

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get decisionsJson => $composableBuilder(
    column: $table.decisionsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get framesJson => $composableBuilder(
    column: $table.framesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checksum => $composableBuilder(
    column: $table.checksum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawPath => $composableBuilder(
    column: $table.rawPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoredSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $StoredSessionsTable> {
  $$StoredSessionsTableOrderingComposer({
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

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get decisionsJson => $composableBuilder(
    column: $table.decisionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get framesJson => $composableBuilder(
    column: $table.framesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checksum => $composableBuilder(
    column: $table.checksum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawPath => $composableBuilder(
    column: $table.rawPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StoredSessionsTable> {
  $$StoredSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get decisionsJson => $composableBuilder(
    column: $table.decisionsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get framesJson => $composableBuilder(
    column: $table.framesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get checksum =>
      $composableBuilder(column: $table.checksum, builder: (column) => column);

  GeneratedColumn<String> get rawPath =>
      $composableBuilder(column: $table.rawPath, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$StoredSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StoredSessionsTable,
          StoredSession,
          $$StoredSessionsTableFilterComposer,
          $$StoredSessionsTableOrderingComposer,
          $$StoredSessionsTableAnnotationComposer,
          $$StoredSessionsTableCreateCompanionBuilder,
          $$StoredSessionsTableUpdateCompanionBuilder,
          (
            StoredSession,
            BaseReferences<_$AppDatabase, $StoredSessionsTable, StoredSession>,
          ),
          StoredSession,
          PrefetchHooks Function()
        > {
  $$StoredSessionsTableTableManager(
    _$AppDatabase db,
    $StoredSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String> manifestJson = const Value.absent(),
                Value<String> decisionsJson = const Value.absent(),
                Value<String> framesJson = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> checksum = const Value.absent(),
                Value<String> rawPath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredSessionsCompanion(
                id: id,
                origin: origin,
                mode: mode,
                manifestJson: manifestJson,
                decisionsJson: decisionsJson,
                framesJson: framesJson,
                status: status,
                checksum: checksum,
                rawPath: rawPath,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String origin,
                required String mode,
                required String manifestJson,
                required String decisionsJson,
                required String framesJson,
                required String status,
                required String checksum,
                required String rawPath,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => StoredSessionsCompanion.insert(
                id: id,
                origin: origin,
                mode: mode,
                manifestJson: manifestJson,
                decisionsJson: decisionsJson,
                framesJson: framesJson,
                status: status,
                checksum: checksum,
                rawPath: rawPath,
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

typedef $$StoredSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StoredSessionsTable,
      StoredSession,
      $$StoredSessionsTableFilterComposer,
      $$StoredSessionsTableOrderingComposer,
      $$StoredSessionsTableAnnotationComposer,
      $$StoredSessionsTableCreateCompanionBuilder,
      $$StoredSessionsTableUpdateCompanionBuilder,
      (
        StoredSession,
        BaseReferences<_$AppDatabase, $StoredSessionsTable, StoredSession>,
      ),
      StoredSession,
      PrefetchHooks Function()
    >;
typedef $$UploadJobsTableCreateCompanionBuilder =
    UploadJobsCompanion Function({
      required String sessionId,
      required String checksum,
      required String payloadPath,
      required String state,
      Value<int> attempts,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $$UploadJobsTableUpdateCompanionBuilder =
    UploadJobsCompanion Function({
      Value<String> sessionId,
      Value<String> checksum,
      Value<String> payloadPath,
      Value<String> state,
      Value<int> attempts,
      Value<String?> lastError,
      Value<int> rowid,
    });

class $$UploadJobsTableFilterComposer
    extends Composer<_$AppDatabase, $UploadJobsTable> {
  $$UploadJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checksum => $composableBuilder(
    column: $table.checksum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadPath => $composableBuilder(
    column: $table.payloadPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UploadJobsTableOrderingComposer
    extends Composer<_$AppDatabase, $UploadJobsTable> {
  $$UploadJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checksum => $composableBuilder(
    column: $table.checksum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadPath => $composableBuilder(
    column: $table.payloadPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UploadJobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UploadJobsTable> {
  $$UploadJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get checksum =>
      $composableBuilder(column: $table.checksum, builder: (column) => column);

  GeneratedColumn<String> get payloadPath => $composableBuilder(
    column: $table.payloadPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$UploadJobsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UploadJobsTable,
          UploadJob,
          $$UploadJobsTableFilterComposer,
          $$UploadJobsTableOrderingComposer,
          $$UploadJobsTableAnnotationComposer,
          $$UploadJobsTableCreateCompanionBuilder,
          $$UploadJobsTableUpdateCompanionBuilder,
          (
            UploadJob,
            BaseReferences<_$AppDatabase, $UploadJobsTable, UploadJob>,
          ),
          UploadJob,
          PrefetchHooks Function()
        > {
  $$UploadJobsTableTableManager(_$AppDatabase db, $UploadJobsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UploadJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UploadJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UploadJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> checksum = const Value.absent(),
                Value<String> payloadPath = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadJobsCompanion(
                sessionId: sessionId,
                checksum: checksum,
                payloadPath: payloadPath,
                state: state,
                attempts: attempts,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required String checksum,
                required String payloadPath,
                required String state,
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadJobsCompanion.insert(
                sessionId: sessionId,
                checksum: checksum,
                payloadPath: payloadPath,
                state: state,
                attempts: attempts,
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

typedef $$UploadJobsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UploadJobsTable,
      UploadJob,
      $$UploadJobsTableFilterComposer,
      $$UploadJobsTableOrderingComposer,
      $$UploadJobsTableAnnotationComposer,
      $$UploadJobsTableCreateCompanionBuilder,
      $$UploadJobsTableUpdateCompanionBuilder,
      (UploadJob, BaseReferences<_$AppDatabase, $UploadJobsTable, UploadJob>),
      UploadJob,
      PrefetchHooks Function()
    >;
typedef $$KvStoreTableCreateCompanionBuilder =
    KvStoreCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$KvStoreTableUpdateCompanionBuilder =
    KvStoreCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$KvStoreTableFilterComposer
    extends Composer<_$AppDatabase, $KvStoreTable> {
  $$KvStoreTableFilterComposer({
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

class $$KvStoreTableOrderingComposer
    extends Composer<_$AppDatabase, $KvStoreTable> {
  $$KvStoreTableOrderingComposer({
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

class $$KvStoreTableAnnotationComposer
    extends Composer<_$AppDatabase, $KvStoreTable> {
  $$KvStoreTableAnnotationComposer({
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

class $$KvStoreTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KvStoreTable,
          KvStoreData,
          $$KvStoreTableFilterComposer,
          $$KvStoreTableOrderingComposer,
          $$KvStoreTableAnnotationComposer,
          $$KvStoreTableCreateCompanionBuilder,
          $$KvStoreTableUpdateCompanionBuilder,
          (
            KvStoreData,
            BaseReferences<_$AppDatabase, $KvStoreTable, KvStoreData>,
          ),
          KvStoreData,
          PrefetchHooks Function()
        > {
  $$KvStoreTableTableManager(_$AppDatabase db, $KvStoreTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KvStoreTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KvStoreTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KvStoreTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KvStoreCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) =>
                  KvStoreCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KvStoreTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KvStoreTable,
      KvStoreData,
      $$KvStoreTableFilterComposer,
      $$KvStoreTableOrderingComposer,
      $$KvStoreTableAnnotationComposer,
      $$KvStoreTableCreateCompanionBuilder,
      $$KvStoreTableUpdateCompanionBuilder,
      (KvStoreData, BaseReferences<_$AppDatabase, $KvStoreTable, KvStoreData>),
      KvStoreData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$StoredSessionsTableTableManager get storedSessions =>
      $$StoredSessionsTableTableManager(_db, _db.storedSessions);
  $$UploadJobsTableTableManager get uploadJobs =>
      $$UploadJobsTableTableManager(_db, _db.uploadJobs);
  $$KvStoreTableTableManager get kvStore =>
      $$KvStoreTableTableManager(_db, _db.kvStore);
}
