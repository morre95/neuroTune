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
  static const VerificationMeta _ownerEmailMeta = const VerificationMeta(
    'ownerEmail',
  );
  @override
  late final GeneratedColumn<String> ownerEmail = GeneratedColumn<String>(
    'owner_email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    ownerEmail,
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
    if (data.containsKey('owner_email')) {
      context.handle(
        _ownerEmailMeta,
        ownerEmail.isAcceptableOrUnknown(data['owner_email']!, _ownerEmailMeta),
      );
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
      ownerEmail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_email'],
      ),
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
  final String? ownerEmail;
  final String checksum;
  final String payloadPath;
  final String state;
  final int attempts;
  final String? lastError;
  const UploadJob({
    required this.sessionId,
    this.ownerEmail,
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
    if (!nullToAbsent || ownerEmail != null) {
      map['owner_email'] = Variable<String>(ownerEmail);
    }
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
      ownerEmail: ownerEmail == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerEmail),
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
      ownerEmail: serializer.fromJson<String?>(json['ownerEmail']),
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
      'ownerEmail': serializer.toJson<String?>(ownerEmail),
      'checksum': serializer.toJson<String>(checksum),
      'payloadPath': serializer.toJson<String>(payloadPath),
      'state': serializer.toJson<String>(state),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  UploadJob copyWith({
    String? sessionId,
    Value<String?> ownerEmail = const Value.absent(),
    String? checksum,
    String? payloadPath,
    String? state,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
  }) => UploadJob(
    sessionId: sessionId ?? this.sessionId,
    ownerEmail: ownerEmail.present ? ownerEmail.value : this.ownerEmail,
    checksum: checksum ?? this.checksum,
    payloadPath: payloadPath ?? this.payloadPath,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  UploadJob copyWithCompanion(UploadJobsCompanion data) {
    return UploadJob(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      ownerEmail: data.ownerEmail.present
          ? data.ownerEmail.value
          : this.ownerEmail,
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
          ..write('ownerEmail: $ownerEmail, ')
          ..write('checksum: $checksum, ')
          ..write('payloadPath: $payloadPath, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    ownerEmail,
    checksum,
    payloadPath,
    state,
    attempts,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UploadJob &&
          other.sessionId == this.sessionId &&
          other.ownerEmail == this.ownerEmail &&
          other.checksum == this.checksum &&
          other.payloadPath == this.payloadPath &&
          other.state == this.state &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError);
}

class UploadJobsCompanion extends UpdateCompanion<UploadJob> {
  final Value<String> sessionId;
  final Value<String?> ownerEmail;
  final Value<String> checksum;
  final Value<String> payloadPath;
  final Value<String> state;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<int> rowid;
  const UploadJobsCompanion({
    this.sessionId = const Value.absent(),
    this.ownerEmail = const Value.absent(),
    this.checksum = const Value.absent(),
    this.payloadPath = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UploadJobsCompanion.insert({
    required String sessionId,
    this.ownerEmail = const Value.absent(),
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
    Expression<String>? ownerEmail,
    Expression<String>? checksum,
    Expression<String>? payloadPath,
    Expression<String>? state,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (ownerEmail != null) 'owner_email': ownerEmail,
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
    Value<String?>? ownerEmail,
    Value<String>? checksum,
    Value<String>? payloadPath,
    Value<String>? state,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return UploadJobsCompanion(
      sessionId: sessionId ?? this.sessionId,
      ownerEmail: ownerEmail ?? this.ownerEmail,
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
    if (ownerEmail.present) {
      map['owner_email'] = Variable<String>(ownerEmail.value);
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
          ..write('ownerEmail: $ownerEmail, ')
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

class $CachedAudioProfilesTable extends CachedAudioProfiles
    with TableInfo<$CachedAudioProfilesTable, CachedAudioProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedAudioProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerAccountIdMeta = const VerificationMeta(
    'ownerAccountId',
  );
  @override
  late final GeneratedColumn<String> ownerAccountId = GeneratedColumn<String>(
    'owner_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionIdMeta = const VerificationMeta(
    'versionId',
  );
  @override
  late final GeneratedColumn<String> versionId = GeneratedColumn<String>(
    'version_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readyPathMeta = const VerificationMeta(
    'readyPath',
  );
  @override
  late final GeneratedColumn<String> readyPath = GeneratedColumn<String>(
    'ready_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerAccountId,
    versionId,
    metadataJson,
    readyPath,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_audio_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedAudioProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_account_id')) {
      context.handle(
        _ownerAccountIdMeta,
        ownerAccountId.isAcceptableOrUnknown(
          data['owner_account_id']!,
          _ownerAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerAccountIdMeta);
    }
    if (data.containsKey('version_id')) {
      context.handle(
        _versionIdMeta,
        versionId.isAcceptableOrUnknown(data['version_id']!, _versionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_versionIdMeta);
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_metadataJsonMeta);
    }
    if (data.containsKey('ready_path')) {
      context.handle(
        _readyPathMeta,
        readyPath.isAcceptableOrUnknown(data['ready_path']!, _readyPathMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerAccountId, versionId};
  @override
  CachedAudioProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedAudioProfile(
      ownerAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_account_id'],
      )!,
      versionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_id'],
      )!,
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      )!,
      readyPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ready_path'],
      ),
    );
  }

  @override
  $CachedAudioProfilesTable createAlias(String alias) {
    return $CachedAudioProfilesTable(attachedDatabase, alias);
  }
}

class CachedAudioProfile extends DataClass
    implements Insertable<CachedAudioProfile> {
  final String ownerAccountId;
  final String versionId;
  final String metadataJson;
  final String? readyPath;
  const CachedAudioProfile({
    required this.ownerAccountId,
    required this.versionId,
    required this.metadataJson,
    this.readyPath,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_account_id'] = Variable<String>(ownerAccountId);
    map['version_id'] = Variable<String>(versionId);
    map['metadata_json'] = Variable<String>(metadataJson);
    if (!nullToAbsent || readyPath != null) {
      map['ready_path'] = Variable<String>(readyPath);
    }
    return map;
  }

  CachedAudioProfilesCompanion toCompanion(bool nullToAbsent) {
    return CachedAudioProfilesCompanion(
      ownerAccountId: Value(ownerAccountId),
      versionId: Value(versionId),
      metadataJson: Value(metadataJson),
      readyPath: readyPath == null && nullToAbsent
          ? const Value.absent()
          : Value(readyPath),
    );
  }

  factory CachedAudioProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedAudioProfile(
      ownerAccountId: serializer.fromJson<String>(json['ownerAccountId']),
      versionId: serializer.fromJson<String>(json['versionId']),
      metadataJson: serializer.fromJson<String>(json['metadataJson']),
      readyPath: serializer.fromJson<String?>(json['readyPath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerAccountId': serializer.toJson<String>(ownerAccountId),
      'versionId': serializer.toJson<String>(versionId),
      'metadataJson': serializer.toJson<String>(metadataJson),
      'readyPath': serializer.toJson<String?>(readyPath),
    };
  }

  CachedAudioProfile copyWith({
    String? ownerAccountId,
    String? versionId,
    String? metadataJson,
    Value<String?> readyPath = const Value.absent(),
  }) => CachedAudioProfile(
    ownerAccountId: ownerAccountId ?? this.ownerAccountId,
    versionId: versionId ?? this.versionId,
    metadataJson: metadataJson ?? this.metadataJson,
    readyPath: readyPath.present ? readyPath.value : this.readyPath,
  );
  CachedAudioProfile copyWithCompanion(CachedAudioProfilesCompanion data) {
    return CachedAudioProfile(
      ownerAccountId: data.ownerAccountId.present
          ? data.ownerAccountId.value
          : this.ownerAccountId,
      versionId: data.versionId.present ? data.versionId.value : this.versionId,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
      readyPath: data.readyPath.present ? data.readyPath.value : this.readyPath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedAudioProfile(')
          ..write('ownerAccountId: $ownerAccountId, ')
          ..write('versionId: $versionId, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('readyPath: $readyPath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(ownerAccountId, versionId, metadataJson, readyPath);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedAudioProfile &&
          other.ownerAccountId == this.ownerAccountId &&
          other.versionId == this.versionId &&
          other.metadataJson == this.metadataJson &&
          other.readyPath == this.readyPath);
}

class CachedAudioProfilesCompanion extends UpdateCompanion<CachedAudioProfile> {
  final Value<String> ownerAccountId;
  final Value<String> versionId;
  final Value<String> metadataJson;
  final Value<String?> readyPath;
  final Value<int> rowid;
  const CachedAudioProfilesCompanion({
    this.ownerAccountId = const Value.absent(),
    this.versionId = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.readyPath = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedAudioProfilesCompanion.insert({
    required String ownerAccountId,
    required String versionId,
    required String metadataJson,
    this.readyPath = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ownerAccountId = Value(ownerAccountId),
       versionId = Value(versionId),
       metadataJson = Value(metadataJson);
  static Insertable<CachedAudioProfile> custom({
    Expression<String>? ownerAccountId,
    Expression<String>? versionId,
    Expression<String>? metadataJson,
    Expression<String>? readyPath,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerAccountId != null) 'owner_account_id': ownerAccountId,
      if (versionId != null) 'version_id': versionId,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (readyPath != null) 'ready_path': readyPath,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedAudioProfilesCompanion copyWith({
    Value<String>? ownerAccountId,
    Value<String>? versionId,
    Value<String>? metadataJson,
    Value<String?>? readyPath,
    Value<int>? rowid,
  }) {
    return CachedAudioProfilesCompanion(
      ownerAccountId: ownerAccountId ?? this.ownerAccountId,
      versionId: versionId ?? this.versionId,
      metadataJson: metadataJson ?? this.metadataJson,
      readyPath: readyPath ?? this.readyPath,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerAccountId.present) {
      map['owner_account_id'] = Variable<String>(ownerAccountId.value);
    }
    if (versionId.present) {
      map['version_id'] = Variable<String>(versionId.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (readyPath.present) {
      map['ready_path'] = Variable<String>(readyPath.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedAudioProfilesCompanion(')
          ..write('ownerAccountId: $ownerAccountId, ')
          ..write('versionId: $versionId, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('readyPath: $readyPath, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CalibrationPlansTable extends CalibrationPlans
    with TableInfo<$CalibrationPlansTable, StoredCalibrationPlan> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CalibrationPlansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerAccountIdMeta = const VerificationMeta(
    'ownerAccountId',
  );
  @override
  late final GeneratedColumn<String> ownerAccountId = GeneratedColumn<String>(
    'owner_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyJsonMeta = const VerificationMeta(
    'bodyJson',
  );
  @override
  late final GeneratedColumn<String> bodyJson = GeneratedColumn<String>(
    'body_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
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
    ownerAccountId,
    id,
    bodyJson,
    syncState,
    attempts,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'calibration_plans';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredCalibrationPlan> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_account_id')) {
      context.handle(
        _ownerAccountIdMeta,
        ownerAccountId.isAcceptableOrUnknown(
          data['owner_account_id']!,
          _ownerAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerAccountIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('body_json')) {
      context.handle(
        _bodyJsonMeta,
        bodyJson.isAcceptableOrUnknown(data['body_json']!, _bodyJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyJsonMeta);
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
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
  Set<GeneratedColumn> get $primaryKey => {ownerAccountId, id};
  @override
  StoredCalibrationPlan map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredCalibrationPlan(
      ownerAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_account_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bodyJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_json'],
      )!,
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
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
  $CalibrationPlansTable createAlias(String alias) {
    return $CalibrationPlansTable(attachedDatabase, alias);
  }
}

class StoredCalibrationPlan extends DataClass
    implements Insertable<StoredCalibrationPlan> {
  final String ownerAccountId;
  final String id;
  final String bodyJson;
  final String syncState;
  final int attempts;
  final String? lastError;
  const StoredCalibrationPlan({
    required this.ownerAccountId,
    required this.id,
    required this.bodyJson,
    required this.syncState,
    required this.attempts,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_account_id'] = Variable<String>(ownerAccountId);
    map['id'] = Variable<String>(id);
    map['body_json'] = Variable<String>(bodyJson);
    map['sync_state'] = Variable<String>(syncState);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  CalibrationPlansCompanion toCompanion(bool nullToAbsent) {
    return CalibrationPlansCompanion(
      ownerAccountId: Value(ownerAccountId),
      id: Value(id),
      bodyJson: Value(bodyJson),
      syncState: Value(syncState),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory StoredCalibrationPlan.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredCalibrationPlan(
      ownerAccountId: serializer.fromJson<String>(json['ownerAccountId']),
      id: serializer.fromJson<String>(json['id']),
      bodyJson: serializer.fromJson<String>(json['bodyJson']),
      syncState: serializer.fromJson<String>(json['syncState']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerAccountId': serializer.toJson<String>(ownerAccountId),
      'id': serializer.toJson<String>(id),
      'bodyJson': serializer.toJson<String>(bodyJson),
      'syncState': serializer.toJson<String>(syncState),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  StoredCalibrationPlan copyWith({
    String? ownerAccountId,
    String? id,
    String? bodyJson,
    String? syncState,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
  }) => StoredCalibrationPlan(
    ownerAccountId: ownerAccountId ?? this.ownerAccountId,
    id: id ?? this.id,
    bodyJson: bodyJson ?? this.bodyJson,
    syncState: syncState ?? this.syncState,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  StoredCalibrationPlan copyWithCompanion(CalibrationPlansCompanion data) {
    return StoredCalibrationPlan(
      ownerAccountId: data.ownerAccountId.present
          ? data.ownerAccountId.value
          : this.ownerAccountId,
      id: data.id.present ? data.id.value : this.id,
      bodyJson: data.bodyJson.present ? data.bodyJson.value : this.bodyJson,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredCalibrationPlan(')
          ..write('ownerAccountId: $ownerAccountId, ')
          ..write('id: $id, ')
          ..write('bodyJson: $bodyJson, ')
          ..write('syncState: $syncState, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(ownerAccountId, id, bodyJson, syncState, attempts, lastError);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredCalibrationPlan &&
          other.ownerAccountId == this.ownerAccountId &&
          other.id == this.id &&
          other.bodyJson == this.bodyJson &&
          other.syncState == this.syncState &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError);
}

class CalibrationPlansCompanion extends UpdateCompanion<StoredCalibrationPlan> {
  final Value<String> ownerAccountId;
  final Value<String> id;
  final Value<String> bodyJson;
  final Value<String> syncState;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<int> rowid;
  const CalibrationPlansCompanion({
    this.ownerAccountId = const Value.absent(),
    this.id = const Value.absent(),
    this.bodyJson = const Value.absent(),
    this.syncState = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CalibrationPlansCompanion.insert({
    required String ownerAccountId,
    required String id,
    required String bodyJson,
    this.syncState = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ownerAccountId = Value(ownerAccountId),
       id = Value(id),
       bodyJson = Value(bodyJson);
  static Insertable<StoredCalibrationPlan> custom({
    Expression<String>? ownerAccountId,
    Expression<String>? id,
    Expression<String>? bodyJson,
    Expression<String>? syncState,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerAccountId != null) 'owner_account_id': ownerAccountId,
      if (id != null) 'id': id,
      if (bodyJson != null) 'body_json': bodyJson,
      if (syncState != null) 'sync_state': syncState,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CalibrationPlansCompanion copyWith({
    Value<String>? ownerAccountId,
    Value<String>? id,
    Value<String>? bodyJson,
    Value<String>? syncState,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return CalibrationPlansCompanion(
      ownerAccountId: ownerAccountId ?? this.ownerAccountId,
      id: id ?? this.id,
      bodyJson: bodyJson ?? this.bodyJson,
      syncState: syncState ?? this.syncState,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerAccountId.present) {
      map['owner_account_id'] = Variable<String>(ownerAccountId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bodyJson.present) {
      map['body_json'] = Variable<String>(bodyJson.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
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
    return (StringBuffer('CalibrationPlansCompanion(')
          ..write('ownerAccountId: $ownerAccountId, ')
          ..write('id: $id, ')
          ..write('bodyJson: $bodyJson, ')
          ..write('syncState: $syncState, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CalibrationAttemptsTable extends CalibrationAttempts
    with TableInfo<$CalibrationAttemptsTable, CalibrationAttempt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CalibrationAttemptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerAccountIdMeta = const VerificationMeta(
    'ownerAccountId',
  );
  @override
  late final GeneratedColumn<String> ownerAccountId = GeneratedColumn<String>(
    'owner_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
  static const VerificationMeta _planIdMeta = const VerificationMeta('planId');
  @override
  late final GeneratedColumn<String> planId = GeneratedColumn<String>(
    'plan_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _slotMeta = const VerificationMeta('slot');
  @override
  late final GeneratedColumn<int> slot = GeneratedColumn<int>(
    'slot',
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
    defaultValue: const Constant('reserved'),
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
    ownerAccountId,
    sessionId,
    planId,
    slot,
    state,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'calibration_attempts';
  @override
  VerificationContext validateIntegrity(
    Insertable<CalibrationAttempt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_account_id')) {
      context.handle(
        _ownerAccountIdMeta,
        ownerAccountId.isAcceptableOrUnknown(
          data['owner_account_id']!,
          _ownerAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerAccountIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('plan_id')) {
      context.handle(
        _planIdMeta,
        planId.isAcceptableOrUnknown(data['plan_id']!, _planIdMeta),
      );
    } else if (isInserting) {
      context.missing(_planIdMeta);
    }
    if (data.containsKey('slot')) {
      context.handle(
        _slotMeta,
        slot.isAcceptableOrUnknown(data['slot']!, _slotMeta),
      );
    } else if (isInserting) {
      context.missing(_slotMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
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
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  CalibrationAttempt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CalibrationAttempt(
      ownerAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_account_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      planId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_id'],
      )!,
      slot: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}slot'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CalibrationAttemptsTable createAlias(String alias) {
    return $CalibrationAttemptsTable(attachedDatabase, alias);
  }
}

class CalibrationAttempt extends DataClass
    implements Insertable<CalibrationAttempt> {
  final String ownerAccountId;
  final String sessionId;
  final String planId;
  final int slot;
  final String state;
  final DateTime createdAt;
  const CalibrationAttempt({
    required this.ownerAccountId,
    required this.sessionId,
    required this.planId,
    required this.slot,
    required this.state,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_account_id'] = Variable<String>(ownerAccountId);
    map['session_id'] = Variable<String>(sessionId);
    map['plan_id'] = Variable<String>(planId);
    map['slot'] = Variable<int>(slot);
    map['state'] = Variable<String>(state);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CalibrationAttemptsCompanion toCompanion(bool nullToAbsent) {
    return CalibrationAttemptsCompanion(
      ownerAccountId: Value(ownerAccountId),
      sessionId: Value(sessionId),
      planId: Value(planId),
      slot: Value(slot),
      state: Value(state),
      createdAt: Value(createdAt),
    );
  }

  factory CalibrationAttempt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CalibrationAttempt(
      ownerAccountId: serializer.fromJson<String>(json['ownerAccountId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      planId: serializer.fromJson<String>(json['planId']),
      slot: serializer.fromJson<int>(json['slot']),
      state: serializer.fromJson<String>(json['state']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerAccountId': serializer.toJson<String>(ownerAccountId),
      'sessionId': serializer.toJson<String>(sessionId),
      'planId': serializer.toJson<String>(planId),
      'slot': serializer.toJson<int>(slot),
      'state': serializer.toJson<String>(state),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  CalibrationAttempt copyWith({
    String? ownerAccountId,
    String? sessionId,
    String? planId,
    int? slot,
    String? state,
    DateTime? createdAt,
  }) => CalibrationAttempt(
    ownerAccountId: ownerAccountId ?? this.ownerAccountId,
    sessionId: sessionId ?? this.sessionId,
    planId: planId ?? this.planId,
    slot: slot ?? this.slot,
    state: state ?? this.state,
    createdAt: createdAt ?? this.createdAt,
  );
  CalibrationAttempt copyWithCompanion(CalibrationAttemptsCompanion data) {
    return CalibrationAttempt(
      ownerAccountId: data.ownerAccountId.present
          ? data.ownerAccountId.value
          : this.ownerAccountId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      planId: data.planId.present ? data.planId.value : this.planId,
      slot: data.slot.present ? data.slot.value : this.slot,
      state: data.state.present ? data.state.value : this.state,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CalibrationAttempt(')
          ..write('ownerAccountId: $ownerAccountId, ')
          ..write('sessionId: $sessionId, ')
          ..write('planId: $planId, ')
          ..write('slot: $slot, ')
          ..write('state: $state, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(ownerAccountId, sessionId, planId, slot, state, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CalibrationAttempt &&
          other.ownerAccountId == this.ownerAccountId &&
          other.sessionId == this.sessionId &&
          other.planId == this.planId &&
          other.slot == this.slot &&
          other.state == this.state &&
          other.createdAt == this.createdAt);
}

class CalibrationAttemptsCompanion extends UpdateCompanion<CalibrationAttempt> {
  final Value<String> ownerAccountId;
  final Value<String> sessionId;
  final Value<String> planId;
  final Value<int> slot;
  final Value<String> state;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const CalibrationAttemptsCompanion({
    this.ownerAccountId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.planId = const Value.absent(),
    this.slot = const Value.absent(),
    this.state = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CalibrationAttemptsCompanion.insert({
    required String ownerAccountId,
    required String sessionId,
    required String planId,
    required int slot,
    this.state = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : ownerAccountId = Value(ownerAccountId),
       sessionId = Value(sessionId),
       planId = Value(planId),
       slot = Value(slot),
       createdAt = Value(createdAt);
  static Insertable<CalibrationAttempt> custom({
    Expression<String>? ownerAccountId,
    Expression<String>? sessionId,
    Expression<String>? planId,
    Expression<int>? slot,
    Expression<String>? state,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerAccountId != null) 'owner_account_id': ownerAccountId,
      if (sessionId != null) 'session_id': sessionId,
      if (planId != null) 'plan_id': planId,
      if (slot != null) 'slot': slot,
      if (state != null) 'state': state,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CalibrationAttemptsCompanion copyWith({
    Value<String>? ownerAccountId,
    Value<String>? sessionId,
    Value<String>? planId,
    Value<int>? slot,
    Value<String>? state,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return CalibrationAttemptsCompanion(
      ownerAccountId: ownerAccountId ?? this.ownerAccountId,
      sessionId: sessionId ?? this.sessionId,
      planId: planId ?? this.planId,
      slot: slot ?? this.slot,
      state: state ?? this.state,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerAccountId.present) {
      map['owner_account_id'] = Variable<String>(ownerAccountId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (planId.present) {
      map['plan_id'] = Variable<String>(planId.value);
    }
    if (slot.present) {
      map['slot'] = Variable<int>(slot.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
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
    return (StringBuffer('CalibrationAttemptsCompanion(')
          ..write('ownerAccountId: $ownerAccountId, ')
          ..write('sessionId: $sessionId, ')
          ..write('planId: $planId, ')
          ..write('slot: $slot, ')
          ..write('state: $state, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MeditationFeedbackRowsTable extends MeditationFeedbackRows
    with TableInfo<$MeditationFeedbackRowsTable, MeditationFeedbackRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MeditationFeedbackRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerAccountIdMeta = const VerificationMeta(
    'ownerAccountId',
  );
  @override
  late final GeneratedColumn<String> ownerAccountId = GeneratedColumn<String>(
    'owner_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
  static const VerificationMeta _mentalBusynessMeta = const VerificationMeta(
    'mentalBusyness',
  );
  @override
  late final GeneratedColumn<int> mentalBusyness = GeneratedColumn<int>(
    'mental_busyness',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _relaxationMeta = const VerificationMeta(
    'relaxation',
  );
  @override
  late final GeneratedColumn<int> relaxation = GeneratedColumn<int>(
    'relaxation',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
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
    ownerAccountId,
    sessionId,
    mentalBusyness,
    relaxation,
    revision,
    syncState,
    attempts,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meditation_feedback_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<MeditationFeedbackRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_account_id')) {
      context.handle(
        _ownerAccountIdMeta,
        ownerAccountId.isAcceptableOrUnknown(
          data['owner_account_id']!,
          _ownerAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerAccountIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('mental_busyness')) {
      context.handle(
        _mentalBusynessMeta,
        mentalBusyness.isAcceptableOrUnknown(
          data['mental_busyness']!,
          _mentalBusynessMeta,
        ),
      );
    }
    if (data.containsKey('relaxation')) {
      context.handle(
        _relaxationMeta,
        relaxation.isAcceptableOrUnknown(data['relaxation']!, _relaxationMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
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
  Set<GeneratedColumn> get $primaryKey => {ownerAccountId, sessionId};
  @override
  MeditationFeedbackRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MeditationFeedbackRow(
      ownerAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_account_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      mentalBusyness: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mental_busyness'],
      ),
      relaxation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}relaxation'],
      ),
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
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
  $MeditationFeedbackRowsTable createAlias(String alias) {
    return $MeditationFeedbackRowsTable(attachedDatabase, alias);
  }
}

class MeditationFeedbackRow extends DataClass
    implements Insertable<MeditationFeedbackRow> {
  final String ownerAccountId;
  final String sessionId;
  final int? mentalBusyness;
  final int? relaxation;
  final int revision;
  final String syncState;
  final int attempts;
  final String? lastError;
  const MeditationFeedbackRow({
    required this.ownerAccountId,
    required this.sessionId,
    this.mentalBusyness,
    this.relaxation,
    required this.revision,
    required this.syncState,
    required this.attempts,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_account_id'] = Variable<String>(ownerAccountId);
    map['session_id'] = Variable<String>(sessionId);
    if (!nullToAbsent || mentalBusyness != null) {
      map['mental_busyness'] = Variable<int>(mentalBusyness);
    }
    if (!nullToAbsent || relaxation != null) {
      map['relaxation'] = Variable<int>(relaxation);
    }
    map['revision'] = Variable<int>(revision);
    map['sync_state'] = Variable<String>(syncState);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  MeditationFeedbackRowsCompanion toCompanion(bool nullToAbsent) {
    return MeditationFeedbackRowsCompanion(
      ownerAccountId: Value(ownerAccountId),
      sessionId: Value(sessionId),
      mentalBusyness: mentalBusyness == null && nullToAbsent
          ? const Value.absent()
          : Value(mentalBusyness),
      relaxation: relaxation == null && nullToAbsent
          ? const Value.absent()
          : Value(relaxation),
      revision: Value(revision),
      syncState: Value(syncState),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory MeditationFeedbackRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MeditationFeedbackRow(
      ownerAccountId: serializer.fromJson<String>(json['ownerAccountId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      mentalBusyness: serializer.fromJson<int?>(json['mentalBusyness']),
      relaxation: serializer.fromJson<int?>(json['relaxation']),
      revision: serializer.fromJson<int>(json['revision']),
      syncState: serializer.fromJson<String>(json['syncState']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerAccountId': serializer.toJson<String>(ownerAccountId),
      'sessionId': serializer.toJson<String>(sessionId),
      'mentalBusyness': serializer.toJson<int?>(mentalBusyness),
      'relaxation': serializer.toJson<int?>(relaxation),
      'revision': serializer.toJson<int>(revision),
      'syncState': serializer.toJson<String>(syncState),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  MeditationFeedbackRow copyWith({
    String? ownerAccountId,
    String? sessionId,
    Value<int?> mentalBusyness = const Value.absent(),
    Value<int?> relaxation = const Value.absent(),
    int? revision,
    String? syncState,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
  }) => MeditationFeedbackRow(
    ownerAccountId: ownerAccountId ?? this.ownerAccountId,
    sessionId: sessionId ?? this.sessionId,
    mentalBusyness: mentalBusyness.present
        ? mentalBusyness.value
        : this.mentalBusyness,
    relaxation: relaxation.present ? relaxation.value : this.relaxation,
    revision: revision ?? this.revision,
    syncState: syncState ?? this.syncState,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  MeditationFeedbackRow copyWithCompanion(
    MeditationFeedbackRowsCompanion data,
  ) {
    return MeditationFeedbackRow(
      ownerAccountId: data.ownerAccountId.present
          ? data.ownerAccountId.value
          : this.ownerAccountId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      mentalBusyness: data.mentalBusyness.present
          ? data.mentalBusyness.value
          : this.mentalBusyness,
      relaxation: data.relaxation.present
          ? data.relaxation.value
          : this.relaxation,
      revision: data.revision.present ? data.revision.value : this.revision,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MeditationFeedbackRow(')
          ..write('ownerAccountId: $ownerAccountId, ')
          ..write('sessionId: $sessionId, ')
          ..write('mentalBusyness: $mentalBusyness, ')
          ..write('relaxation: $relaxation, ')
          ..write('revision: $revision, ')
          ..write('syncState: $syncState, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerAccountId,
    sessionId,
    mentalBusyness,
    relaxation,
    revision,
    syncState,
    attempts,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MeditationFeedbackRow &&
          other.ownerAccountId == this.ownerAccountId &&
          other.sessionId == this.sessionId &&
          other.mentalBusyness == this.mentalBusyness &&
          other.relaxation == this.relaxation &&
          other.revision == this.revision &&
          other.syncState == this.syncState &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError);
}

class MeditationFeedbackRowsCompanion
    extends UpdateCompanion<MeditationFeedbackRow> {
  final Value<String> ownerAccountId;
  final Value<String> sessionId;
  final Value<int?> mentalBusyness;
  final Value<int?> relaxation;
  final Value<int> revision;
  final Value<String> syncState;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<int> rowid;
  const MeditationFeedbackRowsCompanion({
    this.ownerAccountId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.mentalBusyness = const Value.absent(),
    this.relaxation = const Value.absent(),
    this.revision = const Value.absent(),
    this.syncState = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MeditationFeedbackRowsCompanion.insert({
    required String ownerAccountId,
    required String sessionId,
    this.mentalBusyness = const Value.absent(),
    this.relaxation = const Value.absent(),
    required int revision,
    this.syncState = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ownerAccountId = Value(ownerAccountId),
       sessionId = Value(sessionId),
       revision = Value(revision);
  static Insertable<MeditationFeedbackRow> custom({
    Expression<String>? ownerAccountId,
    Expression<String>? sessionId,
    Expression<int>? mentalBusyness,
    Expression<int>? relaxation,
    Expression<int>? revision,
    Expression<String>? syncState,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerAccountId != null) 'owner_account_id': ownerAccountId,
      if (sessionId != null) 'session_id': sessionId,
      if (mentalBusyness != null) 'mental_busyness': mentalBusyness,
      if (relaxation != null) 'relaxation': relaxation,
      if (revision != null) 'revision': revision,
      if (syncState != null) 'sync_state': syncState,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MeditationFeedbackRowsCompanion copyWith({
    Value<String>? ownerAccountId,
    Value<String>? sessionId,
    Value<int?>? mentalBusyness,
    Value<int?>? relaxation,
    Value<int>? revision,
    Value<String>? syncState,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return MeditationFeedbackRowsCompanion(
      ownerAccountId: ownerAccountId ?? this.ownerAccountId,
      sessionId: sessionId ?? this.sessionId,
      mentalBusyness: mentalBusyness ?? this.mentalBusyness,
      relaxation: relaxation ?? this.relaxation,
      revision: revision ?? this.revision,
      syncState: syncState ?? this.syncState,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerAccountId.present) {
      map['owner_account_id'] = Variable<String>(ownerAccountId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (mentalBusyness.present) {
      map['mental_busyness'] = Variable<int>(mentalBusyness.value);
    }
    if (relaxation.present) {
      map['relaxation'] = Variable<int>(relaxation.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
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
    return (StringBuffer('MeditationFeedbackRowsCompanion(')
          ..write('ownerAccountId: $ownerAccountId, ')
          ..write('sessionId: $sessionId, ')
          ..write('mentalBusyness: $mentalBusyness, ')
          ..write('relaxation: $relaxation, ')
          ..write('revision: $revision, ')
          ..write('syncState: $syncState, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MeditationTrainingOutboxTable extends MeditationTrainingOutbox
    with
        TableInfo<
          $MeditationTrainingOutboxTable,
          MeditationTrainingOutboxData
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MeditationTrainingOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerAccountIdMeta = const VerificationMeta(
    'ownerAccountId',
  );
  @override
  late final GeneratedColumn<String> ownerAccountId = GeneratedColumn<String>(
    'owner_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
  static const VerificationMeta _feedbackRevisionMeta = const VerificationMeta(
    'feedbackRevision',
  );
  @override
  late final GeneratedColumn<int> feedbackRevision = GeneratedColumn<int>(
    'feedback_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<String> requestId = GeneratedColumn<String>(
    'request_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyJsonMeta = const VerificationMeta(
    'bodyJson',
  );
  @override
  late final GeneratedColumn<String> bodyJson = GeneratedColumn<String>(
    'body_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
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
    ownerAccountId,
    sessionId,
    feedbackRevision,
    requestId,
    bodyJson,
    syncState,
    attempts,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meditation_training_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<MeditationTrainingOutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_account_id')) {
      context.handle(
        _ownerAccountIdMeta,
        ownerAccountId.isAcceptableOrUnknown(
          data['owner_account_id']!,
          _ownerAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerAccountIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('feedback_revision')) {
      context.handle(
        _feedbackRevisionMeta,
        feedbackRevision.isAcceptableOrUnknown(
          data['feedback_revision']!,
          _feedbackRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_feedbackRevisionMeta);
    }
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    } else if (isInserting) {
      context.missing(_requestIdMeta);
    }
    if (data.containsKey('body_json')) {
      context.handle(
        _bodyJsonMeta,
        bodyJson.isAcceptableOrUnknown(data['body_json']!, _bodyJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyJsonMeta);
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
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
  Set<GeneratedColumn> get $primaryKey => {
    ownerAccountId,
    sessionId,
    feedbackRevision,
  };
  @override
  MeditationTrainingOutboxData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MeditationTrainingOutboxData(
      ownerAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_account_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      feedbackRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}feedback_revision'],
      )!,
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_id'],
      )!,
      bodyJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_json'],
      )!,
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
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
  $MeditationTrainingOutboxTable createAlias(String alias) {
    return $MeditationTrainingOutboxTable(attachedDatabase, alias);
  }
}

class MeditationTrainingOutboxData extends DataClass
    implements Insertable<MeditationTrainingOutboxData> {
  final String ownerAccountId;
  final String sessionId;
  final int feedbackRevision;
  final String requestId;
  final String bodyJson;
  final String syncState;
  final int attempts;
  final String? lastError;
  const MeditationTrainingOutboxData({
    required this.ownerAccountId,
    required this.sessionId,
    required this.feedbackRevision,
    required this.requestId,
    required this.bodyJson,
    required this.syncState,
    required this.attempts,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_account_id'] = Variable<String>(ownerAccountId);
    map['session_id'] = Variable<String>(sessionId);
    map['feedback_revision'] = Variable<int>(feedbackRevision);
    map['request_id'] = Variable<String>(requestId);
    map['body_json'] = Variable<String>(bodyJson);
    map['sync_state'] = Variable<String>(syncState);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  MeditationTrainingOutboxCompanion toCompanion(bool nullToAbsent) {
    return MeditationTrainingOutboxCompanion(
      ownerAccountId: Value(ownerAccountId),
      sessionId: Value(sessionId),
      feedbackRevision: Value(feedbackRevision),
      requestId: Value(requestId),
      bodyJson: Value(bodyJson),
      syncState: Value(syncState),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory MeditationTrainingOutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MeditationTrainingOutboxData(
      ownerAccountId: serializer.fromJson<String>(json['ownerAccountId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      feedbackRevision: serializer.fromJson<int>(json['feedbackRevision']),
      requestId: serializer.fromJson<String>(json['requestId']),
      bodyJson: serializer.fromJson<String>(json['bodyJson']),
      syncState: serializer.fromJson<String>(json['syncState']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerAccountId': serializer.toJson<String>(ownerAccountId),
      'sessionId': serializer.toJson<String>(sessionId),
      'feedbackRevision': serializer.toJson<int>(feedbackRevision),
      'requestId': serializer.toJson<String>(requestId),
      'bodyJson': serializer.toJson<String>(bodyJson),
      'syncState': serializer.toJson<String>(syncState),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  MeditationTrainingOutboxData copyWith({
    String? ownerAccountId,
    String? sessionId,
    int? feedbackRevision,
    String? requestId,
    String? bodyJson,
    String? syncState,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
  }) => MeditationTrainingOutboxData(
    ownerAccountId: ownerAccountId ?? this.ownerAccountId,
    sessionId: sessionId ?? this.sessionId,
    feedbackRevision: feedbackRevision ?? this.feedbackRevision,
    requestId: requestId ?? this.requestId,
    bodyJson: bodyJson ?? this.bodyJson,
    syncState: syncState ?? this.syncState,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  MeditationTrainingOutboxData copyWithCompanion(
    MeditationTrainingOutboxCompanion data,
  ) {
    return MeditationTrainingOutboxData(
      ownerAccountId: data.ownerAccountId.present
          ? data.ownerAccountId.value
          : this.ownerAccountId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      feedbackRevision: data.feedbackRevision.present
          ? data.feedbackRevision.value
          : this.feedbackRevision,
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      bodyJson: data.bodyJson.present ? data.bodyJson.value : this.bodyJson,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MeditationTrainingOutboxData(')
          ..write('ownerAccountId: $ownerAccountId, ')
          ..write('sessionId: $sessionId, ')
          ..write('feedbackRevision: $feedbackRevision, ')
          ..write('requestId: $requestId, ')
          ..write('bodyJson: $bodyJson, ')
          ..write('syncState: $syncState, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerAccountId,
    sessionId,
    feedbackRevision,
    requestId,
    bodyJson,
    syncState,
    attempts,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MeditationTrainingOutboxData &&
          other.ownerAccountId == this.ownerAccountId &&
          other.sessionId == this.sessionId &&
          other.feedbackRevision == this.feedbackRevision &&
          other.requestId == this.requestId &&
          other.bodyJson == this.bodyJson &&
          other.syncState == this.syncState &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError);
}

class MeditationTrainingOutboxCompanion
    extends UpdateCompanion<MeditationTrainingOutboxData> {
  final Value<String> ownerAccountId;
  final Value<String> sessionId;
  final Value<int> feedbackRevision;
  final Value<String> requestId;
  final Value<String> bodyJson;
  final Value<String> syncState;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<int> rowid;
  const MeditationTrainingOutboxCompanion({
    this.ownerAccountId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.feedbackRevision = const Value.absent(),
    this.requestId = const Value.absent(),
    this.bodyJson = const Value.absent(),
    this.syncState = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MeditationTrainingOutboxCompanion.insert({
    required String ownerAccountId,
    required String sessionId,
    required int feedbackRevision,
    required String requestId,
    required String bodyJson,
    this.syncState = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ownerAccountId = Value(ownerAccountId),
       sessionId = Value(sessionId),
       feedbackRevision = Value(feedbackRevision),
       requestId = Value(requestId),
       bodyJson = Value(bodyJson);
  static Insertable<MeditationTrainingOutboxData> custom({
    Expression<String>? ownerAccountId,
    Expression<String>? sessionId,
    Expression<int>? feedbackRevision,
    Expression<String>? requestId,
    Expression<String>? bodyJson,
    Expression<String>? syncState,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerAccountId != null) 'owner_account_id': ownerAccountId,
      if (sessionId != null) 'session_id': sessionId,
      if (feedbackRevision != null) 'feedback_revision': feedbackRevision,
      if (requestId != null) 'request_id': requestId,
      if (bodyJson != null) 'body_json': bodyJson,
      if (syncState != null) 'sync_state': syncState,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MeditationTrainingOutboxCompanion copyWith({
    Value<String>? ownerAccountId,
    Value<String>? sessionId,
    Value<int>? feedbackRevision,
    Value<String>? requestId,
    Value<String>? bodyJson,
    Value<String>? syncState,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return MeditationTrainingOutboxCompanion(
      ownerAccountId: ownerAccountId ?? this.ownerAccountId,
      sessionId: sessionId ?? this.sessionId,
      feedbackRevision: feedbackRevision ?? this.feedbackRevision,
      requestId: requestId ?? this.requestId,
      bodyJson: bodyJson ?? this.bodyJson,
      syncState: syncState ?? this.syncState,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerAccountId.present) {
      map['owner_account_id'] = Variable<String>(ownerAccountId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (feedbackRevision.present) {
      map['feedback_revision'] = Variable<int>(feedbackRevision.value);
    }
    if (requestId.present) {
      map['request_id'] = Variable<String>(requestId.value);
    }
    if (bodyJson.present) {
      map['body_json'] = Variable<String>(bodyJson.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
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
    return (StringBuffer('MeditationTrainingOutboxCompanion(')
          ..write('ownerAccountId: $ownerAccountId, ')
          ..write('sessionId: $sessionId, ')
          ..write('feedbackRevision: $feedbackRevision, ')
          ..write('requestId: $requestId, ')
          ..write('bodyJson: $bodyJson, ')
          ..write('syncState: $syncState, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionTombstonesTable extends SessionTombstones
    with TableInfo<$SessionTombstonesTable, SessionTombstone> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionTombstonesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _ownerEmailMeta = const VerificationMeta(
    'ownerEmail',
  );
  @override
  late final GeneratedColumn<String> ownerEmail = GeneratedColumn<String>(
    'owner_email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerAccountIdMeta = const VerificationMeta(
    'ownerAccountId',
  );
  @override
  late final GeneratedColumn<String> ownerAccountId = GeneratedColumn<String>(
    'owner_account_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    sessionId,
    ownerEmail,
    ownerAccountId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_tombstones';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionTombstone> instance, {
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
    if (data.containsKey('owner_email')) {
      context.handle(
        _ownerEmailMeta,
        ownerEmail.isAcceptableOrUnknown(data['owner_email']!, _ownerEmailMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerEmailMeta);
    }
    if (data.containsKey('owner_account_id')) {
      context.handle(
        _ownerAccountIdMeta,
        ownerAccountId.isAcceptableOrUnknown(
          data['owner_account_id']!,
          _ownerAccountIdMeta,
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
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  SessionTombstone map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionTombstone(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      ownerEmail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_email'],
      )!,
      ownerAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_account_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SessionTombstonesTable createAlias(String alias) {
    return $SessionTombstonesTable(attachedDatabase, alias);
  }
}

class SessionTombstone extends DataClass
    implements Insertable<SessionTombstone> {
  final String sessionId;
  final String ownerEmail;
  final String? ownerAccountId;
  final DateTime createdAt;
  const SessionTombstone({
    required this.sessionId,
    required this.ownerEmail,
    this.ownerAccountId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['owner_email'] = Variable<String>(ownerEmail);
    if (!nullToAbsent || ownerAccountId != null) {
      map['owner_account_id'] = Variable<String>(ownerAccountId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SessionTombstonesCompanion toCompanion(bool nullToAbsent) {
    return SessionTombstonesCompanion(
      sessionId: Value(sessionId),
      ownerEmail: Value(ownerEmail),
      ownerAccountId: ownerAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerAccountId),
      createdAt: Value(createdAt),
    );
  }

  factory SessionTombstone.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionTombstone(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      ownerEmail: serializer.fromJson<String>(json['ownerEmail']),
      ownerAccountId: serializer.fromJson<String?>(json['ownerAccountId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'ownerEmail': serializer.toJson<String>(ownerEmail),
      'ownerAccountId': serializer.toJson<String?>(ownerAccountId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SessionTombstone copyWith({
    String? sessionId,
    String? ownerEmail,
    Value<String?> ownerAccountId = const Value.absent(),
    DateTime? createdAt,
  }) => SessionTombstone(
    sessionId: sessionId ?? this.sessionId,
    ownerEmail: ownerEmail ?? this.ownerEmail,
    ownerAccountId: ownerAccountId.present
        ? ownerAccountId.value
        : this.ownerAccountId,
    createdAt: createdAt ?? this.createdAt,
  );
  SessionTombstone copyWithCompanion(SessionTombstonesCompanion data) {
    return SessionTombstone(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      ownerEmail: data.ownerEmail.present
          ? data.ownerEmail.value
          : this.ownerEmail,
      ownerAccountId: data.ownerAccountId.present
          ? data.ownerAccountId.value
          : this.ownerAccountId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionTombstone(')
          ..write('sessionId: $sessionId, ')
          ..write('ownerEmail: $ownerEmail, ')
          ..write('ownerAccountId: $ownerAccountId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sessionId, ownerEmail, ownerAccountId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionTombstone &&
          other.sessionId == this.sessionId &&
          other.ownerEmail == this.ownerEmail &&
          other.ownerAccountId == this.ownerAccountId &&
          other.createdAt == this.createdAt);
}

class SessionTombstonesCompanion extends UpdateCompanion<SessionTombstone> {
  final Value<String> sessionId;
  final Value<String> ownerEmail;
  final Value<String?> ownerAccountId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SessionTombstonesCompanion({
    this.sessionId = const Value.absent(),
    this.ownerEmail = const Value.absent(),
    this.ownerAccountId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionTombstonesCompanion.insert({
    required String sessionId,
    required String ownerEmail,
    this.ownerAccountId = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       ownerEmail = Value(ownerEmail),
       createdAt = Value(createdAt);
  static Insertable<SessionTombstone> custom({
    Expression<String>? sessionId,
    Expression<String>? ownerEmail,
    Expression<String>? ownerAccountId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (ownerEmail != null) 'owner_email': ownerEmail,
      if (ownerAccountId != null) 'owner_account_id': ownerAccountId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionTombstonesCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? ownerEmail,
    Value<String?>? ownerAccountId,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return SessionTombstonesCompanion(
      sessionId: sessionId ?? this.sessionId,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      ownerAccountId: ownerAccountId ?? this.ownerAccountId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (ownerEmail.present) {
      map['owner_email'] = Variable<String>(ownerEmail.value);
    }
    if (ownerAccountId.present) {
      map['owner_account_id'] = Variable<String>(ownerAccountId.value);
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
    return (StringBuffer('SessionTombstonesCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('ownerEmail: $ownerEmail, ')
          ..write('ownerAccountId: $ownerAccountId, ')
          ..write('createdAt: $createdAt, ')
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
  late final $CachedAudioProfilesTable cachedAudioProfiles =
      $CachedAudioProfilesTable(this);
  late final $CalibrationPlansTable calibrationPlans = $CalibrationPlansTable(
    this,
  );
  late final $CalibrationAttemptsTable calibrationAttempts =
      $CalibrationAttemptsTable(this);
  late final $MeditationFeedbackRowsTable meditationFeedbackRows =
      $MeditationFeedbackRowsTable(this);
  late final $MeditationTrainingOutboxTable meditationTrainingOutbox =
      $MeditationTrainingOutboxTable(this);
  late final $SessionTombstonesTable sessionTombstones =
      $SessionTombstonesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    storedSessions,
    uploadJobs,
    kvStore,
    cachedAudioProfiles,
    calibrationPlans,
    calibrationAttempts,
    meditationFeedbackRows,
    meditationTrainingOutbox,
    sessionTombstones,
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
      Value<String?> ownerEmail,
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
      Value<String?> ownerEmail,
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

  ColumnFilters<String> get ownerEmail => $composableBuilder(
    column: $table.ownerEmail,
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

  ColumnOrderings<String> get ownerEmail => $composableBuilder(
    column: $table.ownerEmail,
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

  GeneratedColumn<String> get ownerEmail => $composableBuilder(
    column: $table.ownerEmail,
    builder: (column) => column,
  );

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
                Value<String?> ownerEmail = const Value.absent(),
                Value<String> checksum = const Value.absent(),
                Value<String> payloadPath = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadJobsCompanion(
                sessionId: sessionId,
                ownerEmail: ownerEmail,
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
                Value<String?> ownerEmail = const Value.absent(),
                required String checksum,
                required String payloadPath,
                required String state,
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadJobsCompanion.insert(
                sessionId: sessionId,
                ownerEmail: ownerEmail,
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
typedef $$CachedAudioProfilesTableCreateCompanionBuilder =
    CachedAudioProfilesCompanion Function({
      required String ownerAccountId,
      required String versionId,
      required String metadataJson,
      Value<String?> readyPath,
      Value<int> rowid,
    });
typedef $$CachedAudioProfilesTableUpdateCompanionBuilder =
    CachedAudioProfilesCompanion Function({
      Value<String> ownerAccountId,
      Value<String> versionId,
      Value<String> metadataJson,
      Value<String?> readyPath,
      Value<int> rowid,
    });

class $$CachedAudioProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $CachedAudioProfilesTable> {
  $$CachedAudioProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerAccountId => $composableBuilder(
    column: $table.ownerAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get versionId => $composableBuilder(
    column: $table.versionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get readyPath => $composableBuilder(
    column: $table.readyPath,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedAudioProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedAudioProfilesTable> {
  $$CachedAudioProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerAccountId => $composableBuilder(
    column: $table.ownerAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get versionId => $composableBuilder(
    column: $table.versionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get readyPath => $composableBuilder(
    column: $table.readyPath,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedAudioProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedAudioProfilesTable> {
  $$CachedAudioProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerAccountId => $composableBuilder(
    column: $table.ownerAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get versionId =>
      $composableBuilder(column: $table.versionId, builder: (column) => column);

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get readyPath =>
      $composableBuilder(column: $table.readyPath, builder: (column) => column);
}

class $$CachedAudioProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedAudioProfilesTable,
          CachedAudioProfile,
          $$CachedAudioProfilesTableFilterComposer,
          $$CachedAudioProfilesTableOrderingComposer,
          $$CachedAudioProfilesTableAnnotationComposer,
          $$CachedAudioProfilesTableCreateCompanionBuilder,
          $$CachedAudioProfilesTableUpdateCompanionBuilder,
          (
            CachedAudioProfile,
            BaseReferences<
              _$AppDatabase,
              $CachedAudioProfilesTable,
              CachedAudioProfile
            >,
          ),
          CachedAudioProfile,
          PrefetchHooks Function()
        > {
  $$CachedAudioProfilesTableTableManager(
    _$AppDatabase db,
    $CachedAudioProfilesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedAudioProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedAudioProfilesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedAudioProfilesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerAccountId = const Value.absent(),
                Value<String> versionId = const Value.absent(),
                Value<String> metadataJson = const Value.absent(),
                Value<String?> readyPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedAudioProfilesCompanion(
                ownerAccountId: ownerAccountId,
                versionId: versionId,
                metadataJson: metadataJson,
                readyPath: readyPath,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerAccountId,
                required String versionId,
                required String metadataJson,
                Value<String?> readyPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedAudioProfilesCompanion.insert(
                ownerAccountId: ownerAccountId,
                versionId: versionId,
                metadataJson: metadataJson,
                readyPath: readyPath,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedAudioProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedAudioProfilesTable,
      CachedAudioProfile,
      $$CachedAudioProfilesTableFilterComposer,
      $$CachedAudioProfilesTableOrderingComposer,
      $$CachedAudioProfilesTableAnnotationComposer,
      $$CachedAudioProfilesTableCreateCompanionBuilder,
      $$CachedAudioProfilesTableUpdateCompanionBuilder,
      (
        CachedAudioProfile,
        BaseReferences<
          _$AppDatabase,
          $CachedAudioProfilesTable,
          CachedAudioProfile
        >,
      ),
      CachedAudioProfile,
      PrefetchHooks Function()
    >;
typedef $$CalibrationPlansTableCreateCompanionBuilder =
    CalibrationPlansCompanion Function({
      required String ownerAccountId,
      required String id,
      required String bodyJson,
      Value<String> syncState,
      Value<int> attempts,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $$CalibrationPlansTableUpdateCompanionBuilder =
    CalibrationPlansCompanion Function({
      Value<String> ownerAccountId,
      Value<String> id,
      Value<String> bodyJson,
      Value<String> syncState,
      Value<int> attempts,
      Value<String?> lastError,
      Value<int> rowid,
    });

class $$CalibrationPlansTableFilterComposer
    extends Composer<_$AppDatabase, $CalibrationPlansTable> {
  $$CalibrationPlansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerAccountId => $composableBuilder(
    column: $table.ownerAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyJson => $composableBuilder(
    column: $table.bodyJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
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

class $$CalibrationPlansTableOrderingComposer
    extends Composer<_$AppDatabase, $CalibrationPlansTable> {
  $$CalibrationPlansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerAccountId => $composableBuilder(
    column: $table.ownerAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyJson => $composableBuilder(
    column: $table.bodyJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
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

class $$CalibrationPlansTableAnnotationComposer
    extends Composer<_$AppDatabase, $CalibrationPlansTable> {
  $$CalibrationPlansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerAccountId => $composableBuilder(
    column: $table.ownerAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get bodyJson =>
      $composableBuilder(column: $table.bodyJson, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$CalibrationPlansTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CalibrationPlansTable,
          StoredCalibrationPlan,
          $$CalibrationPlansTableFilterComposer,
          $$CalibrationPlansTableOrderingComposer,
          $$CalibrationPlansTableAnnotationComposer,
          $$CalibrationPlansTableCreateCompanionBuilder,
          $$CalibrationPlansTableUpdateCompanionBuilder,
          (
            StoredCalibrationPlan,
            BaseReferences<
              _$AppDatabase,
              $CalibrationPlansTable,
              StoredCalibrationPlan
            >,
          ),
          StoredCalibrationPlan,
          PrefetchHooks Function()
        > {
  $$CalibrationPlansTableTableManager(
    _$AppDatabase db,
    $CalibrationPlansTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CalibrationPlansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CalibrationPlansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CalibrationPlansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerAccountId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> bodyJson = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CalibrationPlansCompanion(
                ownerAccountId: ownerAccountId,
                id: id,
                bodyJson: bodyJson,
                syncState: syncState,
                attempts: attempts,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerAccountId,
                required String id,
                required String bodyJson,
                Value<String> syncState = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CalibrationPlansCompanion.insert(
                ownerAccountId: ownerAccountId,
                id: id,
                bodyJson: bodyJson,
                syncState: syncState,
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

typedef $$CalibrationPlansTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CalibrationPlansTable,
      StoredCalibrationPlan,
      $$CalibrationPlansTableFilterComposer,
      $$CalibrationPlansTableOrderingComposer,
      $$CalibrationPlansTableAnnotationComposer,
      $$CalibrationPlansTableCreateCompanionBuilder,
      $$CalibrationPlansTableUpdateCompanionBuilder,
      (
        StoredCalibrationPlan,
        BaseReferences<
          _$AppDatabase,
          $CalibrationPlansTable,
          StoredCalibrationPlan
        >,
      ),
      StoredCalibrationPlan,
      PrefetchHooks Function()
    >;
typedef $$CalibrationAttemptsTableCreateCompanionBuilder =
    CalibrationAttemptsCompanion Function({
      required String ownerAccountId,
      required String sessionId,
      required String planId,
      required int slot,
      Value<String> state,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$CalibrationAttemptsTableUpdateCompanionBuilder =
    CalibrationAttemptsCompanion Function({
      Value<String> ownerAccountId,
      Value<String> sessionId,
      Value<String> planId,
      Value<int> slot,
      Value<String> state,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$CalibrationAttemptsTableFilterComposer
    extends Composer<_$AppDatabase, $CalibrationAttemptsTable> {
  $$CalibrationAttemptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerAccountId => $composableBuilder(
    column: $table.ownerAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get planId => $composableBuilder(
    column: $table.planId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CalibrationAttemptsTableOrderingComposer
    extends Composer<_$AppDatabase, $CalibrationAttemptsTable> {
  $$CalibrationAttemptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerAccountId => $composableBuilder(
    column: $table.ownerAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get planId => $composableBuilder(
    column: $table.planId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CalibrationAttemptsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CalibrationAttemptsTable> {
  $$CalibrationAttemptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerAccountId => $composableBuilder(
    column: $table.ownerAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get planId =>
      $composableBuilder(column: $table.planId, builder: (column) => column);

  GeneratedColumn<int> get slot =>
      $composableBuilder(column: $table.slot, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CalibrationAttemptsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CalibrationAttemptsTable,
          CalibrationAttempt,
          $$CalibrationAttemptsTableFilterComposer,
          $$CalibrationAttemptsTableOrderingComposer,
          $$CalibrationAttemptsTableAnnotationComposer,
          $$CalibrationAttemptsTableCreateCompanionBuilder,
          $$CalibrationAttemptsTableUpdateCompanionBuilder,
          (
            CalibrationAttempt,
            BaseReferences<
              _$AppDatabase,
              $CalibrationAttemptsTable,
              CalibrationAttempt
            >,
          ),
          CalibrationAttempt,
          PrefetchHooks Function()
        > {
  $$CalibrationAttemptsTableTableManager(
    _$AppDatabase db,
    $CalibrationAttemptsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CalibrationAttemptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CalibrationAttemptsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CalibrationAttemptsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerAccountId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> planId = const Value.absent(),
                Value<int> slot = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CalibrationAttemptsCompanion(
                ownerAccountId: ownerAccountId,
                sessionId: sessionId,
                planId: planId,
                slot: slot,
                state: state,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerAccountId,
                required String sessionId,
                required String planId,
                required int slot,
                Value<String> state = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => CalibrationAttemptsCompanion.insert(
                ownerAccountId: ownerAccountId,
                sessionId: sessionId,
                planId: planId,
                slot: slot,
                state: state,
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

typedef $$CalibrationAttemptsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CalibrationAttemptsTable,
      CalibrationAttempt,
      $$CalibrationAttemptsTableFilterComposer,
      $$CalibrationAttemptsTableOrderingComposer,
      $$CalibrationAttemptsTableAnnotationComposer,
      $$CalibrationAttemptsTableCreateCompanionBuilder,
      $$CalibrationAttemptsTableUpdateCompanionBuilder,
      (
        CalibrationAttempt,
        BaseReferences<
          _$AppDatabase,
          $CalibrationAttemptsTable,
          CalibrationAttempt
        >,
      ),
      CalibrationAttempt,
      PrefetchHooks Function()
    >;
typedef $$MeditationFeedbackRowsTableCreateCompanionBuilder =
    MeditationFeedbackRowsCompanion Function({
      required String ownerAccountId,
      required String sessionId,
      Value<int?> mentalBusyness,
      Value<int?> relaxation,
      required int revision,
      Value<String> syncState,
      Value<int> attempts,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $$MeditationFeedbackRowsTableUpdateCompanionBuilder =
    MeditationFeedbackRowsCompanion Function({
      Value<String> ownerAccountId,
      Value<String> sessionId,
      Value<int?> mentalBusyness,
      Value<int?> relaxation,
      Value<int> revision,
      Value<String> syncState,
      Value<int> attempts,
      Value<String?> lastError,
      Value<int> rowid,
    });

class $$MeditationFeedbackRowsTableFilterComposer
    extends Composer<_$AppDatabase, $MeditationFeedbackRowsTable> {
  $$MeditationFeedbackRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerAccountId => $composableBuilder(
    column: $table.ownerAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mentalBusyness => $composableBuilder(
    column: $table.mentalBusyness,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get relaxation => $composableBuilder(
    column: $table.relaxation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
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

class $$MeditationFeedbackRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $MeditationFeedbackRowsTable> {
  $$MeditationFeedbackRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerAccountId => $composableBuilder(
    column: $table.ownerAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mentalBusyness => $composableBuilder(
    column: $table.mentalBusyness,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get relaxation => $composableBuilder(
    column: $table.relaxation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
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

class $$MeditationFeedbackRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MeditationFeedbackRowsTable> {
  $$MeditationFeedbackRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerAccountId => $composableBuilder(
    column: $table.ownerAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get mentalBusyness => $composableBuilder(
    column: $table.mentalBusyness,
    builder: (column) => column,
  );

  GeneratedColumn<int> get relaxation => $composableBuilder(
    column: $table.relaxation,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$MeditationFeedbackRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MeditationFeedbackRowsTable,
          MeditationFeedbackRow,
          $$MeditationFeedbackRowsTableFilterComposer,
          $$MeditationFeedbackRowsTableOrderingComposer,
          $$MeditationFeedbackRowsTableAnnotationComposer,
          $$MeditationFeedbackRowsTableCreateCompanionBuilder,
          $$MeditationFeedbackRowsTableUpdateCompanionBuilder,
          (
            MeditationFeedbackRow,
            BaseReferences<
              _$AppDatabase,
              $MeditationFeedbackRowsTable,
              MeditationFeedbackRow
            >,
          ),
          MeditationFeedbackRow,
          PrefetchHooks Function()
        > {
  $$MeditationFeedbackRowsTableTableManager(
    _$AppDatabase db,
    $MeditationFeedbackRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MeditationFeedbackRowsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$MeditationFeedbackRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$MeditationFeedbackRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerAccountId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<int?> mentalBusyness = const Value.absent(),
                Value<int?> relaxation = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MeditationFeedbackRowsCompanion(
                ownerAccountId: ownerAccountId,
                sessionId: sessionId,
                mentalBusyness: mentalBusyness,
                relaxation: relaxation,
                revision: revision,
                syncState: syncState,
                attempts: attempts,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerAccountId,
                required String sessionId,
                Value<int?> mentalBusyness = const Value.absent(),
                Value<int?> relaxation = const Value.absent(),
                required int revision,
                Value<String> syncState = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MeditationFeedbackRowsCompanion.insert(
                ownerAccountId: ownerAccountId,
                sessionId: sessionId,
                mentalBusyness: mentalBusyness,
                relaxation: relaxation,
                revision: revision,
                syncState: syncState,
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

typedef $$MeditationFeedbackRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MeditationFeedbackRowsTable,
      MeditationFeedbackRow,
      $$MeditationFeedbackRowsTableFilterComposer,
      $$MeditationFeedbackRowsTableOrderingComposer,
      $$MeditationFeedbackRowsTableAnnotationComposer,
      $$MeditationFeedbackRowsTableCreateCompanionBuilder,
      $$MeditationFeedbackRowsTableUpdateCompanionBuilder,
      (
        MeditationFeedbackRow,
        BaseReferences<
          _$AppDatabase,
          $MeditationFeedbackRowsTable,
          MeditationFeedbackRow
        >,
      ),
      MeditationFeedbackRow,
      PrefetchHooks Function()
    >;
typedef $$MeditationTrainingOutboxTableCreateCompanionBuilder =
    MeditationTrainingOutboxCompanion Function({
      required String ownerAccountId,
      required String sessionId,
      required int feedbackRevision,
      required String requestId,
      required String bodyJson,
      Value<String> syncState,
      Value<int> attempts,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $$MeditationTrainingOutboxTableUpdateCompanionBuilder =
    MeditationTrainingOutboxCompanion Function({
      Value<String> ownerAccountId,
      Value<String> sessionId,
      Value<int> feedbackRevision,
      Value<String> requestId,
      Value<String> bodyJson,
      Value<String> syncState,
      Value<int> attempts,
      Value<String?> lastError,
      Value<int> rowid,
    });

class $$MeditationTrainingOutboxTableFilterComposer
    extends Composer<_$AppDatabase, $MeditationTrainingOutboxTable> {
  $$MeditationTrainingOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerAccountId => $composableBuilder(
    column: $table.ownerAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get feedbackRevision => $composableBuilder(
    column: $table.feedbackRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyJson => $composableBuilder(
    column: $table.bodyJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
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

class $$MeditationTrainingOutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $MeditationTrainingOutboxTable> {
  $$MeditationTrainingOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerAccountId => $composableBuilder(
    column: $table.ownerAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get feedbackRevision => $composableBuilder(
    column: $table.feedbackRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyJson => $composableBuilder(
    column: $table.bodyJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
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

class $$MeditationTrainingOutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $MeditationTrainingOutboxTable> {
  $$MeditationTrainingOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerAccountId => $composableBuilder(
    column: $table.ownerAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get feedbackRevision => $composableBuilder(
    column: $table.feedbackRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get requestId =>
      $composableBuilder(column: $table.requestId, builder: (column) => column);

  GeneratedColumn<String> get bodyJson =>
      $composableBuilder(column: $table.bodyJson, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$MeditationTrainingOutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MeditationTrainingOutboxTable,
          MeditationTrainingOutboxData,
          $$MeditationTrainingOutboxTableFilterComposer,
          $$MeditationTrainingOutboxTableOrderingComposer,
          $$MeditationTrainingOutboxTableAnnotationComposer,
          $$MeditationTrainingOutboxTableCreateCompanionBuilder,
          $$MeditationTrainingOutboxTableUpdateCompanionBuilder,
          (
            MeditationTrainingOutboxData,
            BaseReferences<
              _$AppDatabase,
              $MeditationTrainingOutboxTable,
              MeditationTrainingOutboxData
            >,
          ),
          MeditationTrainingOutboxData,
          PrefetchHooks Function()
        > {
  $$MeditationTrainingOutboxTableTableManager(
    _$AppDatabase db,
    $MeditationTrainingOutboxTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MeditationTrainingOutboxTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$MeditationTrainingOutboxTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$MeditationTrainingOutboxTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerAccountId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<int> feedbackRevision = const Value.absent(),
                Value<String> requestId = const Value.absent(),
                Value<String> bodyJson = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MeditationTrainingOutboxCompanion(
                ownerAccountId: ownerAccountId,
                sessionId: sessionId,
                feedbackRevision: feedbackRevision,
                requestId: requestId,
                bodyJson: bodyJson,
                syncState: syncState,
                attempts: attempts,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerAccountId,
                required String sessionId,
                required int feedbackRevision,
                required String requestId,
                required String bodyJson,
                Value<String> syncState = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MeditationTrainingOutboxCompanion.insert(
                ownerAccountId: ownerAccountId,
                sessionId: sessionId,
                feedbackRevision: feedbackRevision,
                requestId: requestId,
                bodyJson: bodyJson,
                syncState: syncState,
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

typedef $$MeditationTrainingOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MeditationTrainingOutboxTable,
      MeditationTrainingOutboxData,
      $$MeditationTrainingOutboxTableFilterComposer,
      $$MeditationTrainingOutboxTableOrderingComposer,
      $$MeditationTrainingOutboxTableAnnotationComposer,
      $$MeditationTrainingOutboxTableCreateCompanionBuilder,
      $$MeditationTrainingOutboxTableUpdateCompanionBuilder,
      (
        MeditationTrainingOutboxData,
        BaseReferences<
          _$AppDatabase,
          $MeditationTrainingOutboxTable,
          MeditationTrainingOutboxData
        >,
      ),
      MeditationTrainingOutboxData,
      PrefetchHooks Function()
    >;
typedef $$SessionTombstonesTableCreateCompanionBuilder =
    SessionTombstonesCompanion Function({
      required String sessionId,
      required String ownerEmail,
      Value<String?> ownerAccountId,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$SessionTombstonesTableUpdateCompanionBuilder =
    SessionTombstonesCompanion Function({
      Value<String> sessionId,
      Value<String> ownerEmail,
      Value<String?> ownerAccountId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$SessionTombstonesTableFilterComposer
    extends Composer<_$AppDatabase, $SessionTombstonesTable> {
  $$SessionTombstonesTableFilterComposer({
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

  ColumnFilters<String> get ownerEmail => $composableBuilder(
    column: $table.ownerEmail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerAccountId => $composableBuilder(
    column: $table.ownerAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SessionTombstonesTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionTombstonesTable> {
  $$SessionTombstonesTableOrderingComposer({
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

  ColumnOrderings<String> get ownerEmail => $composableBuilder(
    column: $table.ownerEmail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerAccountId => $composableBuilder(
    column: $table.ownerAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionTombstonesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionTombstonesTable> {
  $$SessionTombstonesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get ownerEmail => $composableBuilder(
    column: $table.ownerEmail,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerAccountId => $composableBuilder(
    column: $table.ownerAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SessionTombstonesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionTombstonesTable,
          SessionTombstone,
          $$SessionTombstonesTableFilterComposer,
          $$SessionTombstonesTableOrderingComposer,
          $$SessionTombstonesTableAnnotationComposer,
          $$SessionTombstonesTableCreateCompanionBuilder,
          $$SessionTombstonesTableUpdateCompanionBuilder,
          (
            SessionTombstone,
            BaseReferences<
              _$AppDatabase,
              $SessionTombstonesTable,
              SessionTombstone
            >,
          ),
          SessionTombstone,
          PrefetchHooks Function()
        > {
  $$SessionTombstonesTableTableManager(
    _$AppDatabase db,
    $SessionTombstonesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionTombstonesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionTombstonesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionTombstonesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> ownerEmail = const Value.absent(),
                Value<String?> ownerAccountId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionTombstonesCompanion(
                sessionId: sessionId,
                ownerEmail: ownerEmail,
                ownerAccountId: ownerAccountId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required String ownerEmail,
                Value<String?> ownerAccountId = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => SessionTombstonesCompanion.insert(
                sessionId: sessionId,
                ownerEmail: ownerEmail,
                ownerAccountId: ownerAccountId,
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

typedef $$SessionTombstonesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionTombstonesTable,
      SessionTombstone,
      $$SessionTombstonesTableFilterComposer,
      $$SessionTombstonesTableOrderingComposer,
      $$SessionTombstonesTableAnnotationComposer,
      $$SessionTombstonesTableCreateCompanionBuilder,
      $$SessionTombstonesTableUpdateCompanionBuilder,
      (
        SessionTombstone,
        BaseReferences<
          _$AppDatabase,
          $SessionTombstonesTable,
          SessionTombstone
        >,
      ),
      SessionTombstone,
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
  $$CachedAudioProfilesTableTableManager get cachedAudioProfiles =>
      $$CachedAudioProfilesTableTableManager(_db, _db.cachedAudioProfiles);
  $$CalibrationPlansTableTableManager get calibrationPlans =>
      $$CalibrationPlansTableTableManager(_db, _db.calibrationPlans);
  $$CalibrationAttemptsTableTableManager get calibrationAttempts =>
      $$CalibrationAttemptsTableTableManager(_db, _db.calibrationAttempts);
  $$MeditationFeedbackRowsTableTableManager get meditationFeedbackRows =>
      $$MeditationFeedbackRowsTableTableManager(
        _db,
        _db.meditationFeedbackRows,
      );
  $$MeditationTrainingOutboxTableTableManager get meditationTrainingOutbox =>
      $$MeditationTrainingOutboxTableTableManager(
        _db,
        _db.meditationTrainingOutbox,
      );
  $$SessionTombstonesTableTableManager get sessionTombstones =>
      $$SessionTombstonesTableTableManager(_db, _db.sessionTombstones);
}
