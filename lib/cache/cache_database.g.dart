// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_database.dart';

// ignore_for_file: type=lint
class $CachedPatientsTable extends CachedPatients
    with TableInfo<$CachedPatientsTable, CachedPatient> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedPatientsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
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
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _registrationNumberMeta =
      const VerificationMeta('registrationNumber');
  @override
  late final GeneratedColumn<String> registrationNumber =
      GeneratedColumn<String>(
        'registration_number',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _normalizedNameMeta = const VerificationMeta(
    'normalizedName',
  );
  @override
  late final GeneratedColumn<String> normalizedName = GeneratedColumn<String>(
    'normalized_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    id,
    status,
    registrationNumber,
    normalizedName,
    updatedAt,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_patients';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedPatient> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('registration_number')) {
      context.handle(
        _registrationNumberMeta,
        registrationNumber.isAcceptableOrUnknown(
          data['registration_number']!,
          _registrationNumberMeta,
        ),
      );
    }
    if (data.containsKey('normalized_name')) {
      context.handle(
        _normalizedNameMeta,
        normalizedName.isAcceptableOrUnknown(
          data['normalized_name']!,
          _normalizedNameMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, id};
  @override
  CachedPatient map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedPatient(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
      registrationNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}registration_number'],
      ),
      normalizedName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_name'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $CachedPatientsTable createAlias(String alias) {
    return $CachedPatientsTable(attachedDatabase, alias);
  }
}

class CachedPatient extends DataClass implements Insertable<CachedPatient> {
  final String accountId;
  final String id;
  final String? status;
  final String? registrationNumber;
  final String? normalizedName;
  final int updatedAt;
  final String payload;
  const CachedPatient({
    required this.accountId,
    required this.id,
    this.status,
    this.registrationNumber,
    this.normalizedName,
    required this.updatedAt,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    if (!nullToAbsent || registrationNumber != null) {
      map['registration_number'] = Variable<String>(registrationNumber);
    }
    if (!nullToAbsent || normalizedName != null) {
      map['normalized_name'] = Variable<String>(normalizedName);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  CachedPatientsCompanion toCompanion(bool nullToAbsent) {
    return CachedPatientsCompanion(
      accountId: Value(accountId),
      id: Value(id),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
      registrationNumber: registrationNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(registrationNumber),
      normalizedName: normalizedName == null && nullToAbsent
          ? const Value.absent()
          : Value(normalizedName),
      updatedAt: Value(updatedAt),
      payload: Value(payload),
    );
  }

  factory CachedPatient.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedPatient(
      accountId: serializer.fromJson<String>(json['accountId']),
      id: serializer.fromJson<String>(json['id']),
      status: serializer.fromJson<String?>(json['status']),
      registrationNumber: serializer.fromJson<String?>(
        json['registrationNumber'],
      ),
      normalizedName: serializer.fromJson<String?>(json['normalizedName']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'id': serializer.toJson<String>(id),
      'status': serializer.toJson<String?>(status),
      'registrationNumber': serializer.toJson<String?>(registrationNumber),
      'normalizedName': serializer.toJson<String?>(normalizedName),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'payload': serializer.toJson<String>(payload),
    };
  }

  CachedPatient copyWith({
    String? accountId,
    String? id,
    Value<String?> status = const Value.absent(),
    Value<String?> registrationNumber = const Value.absent(),
    Value<String?> normalizedName = const Value.absent(),
    int? updatedAt,
    String? payload,
  }) => CachedPatient(
    accountId: accountId ?? this.accountId,
    id: id ?? this.id,
    status: status.present ? status.value : this.status,
    registrationNumber: registrationNumber.present
        ? registrationNumber.value
        : this.registrationNumber,
    normalizedName: normalizedName.present
        ? normalizedName.value
        : this.normalizedName,
    updatedAt: updatedAt ?? this.updatedAt,
    payload: payload ?? this.payload,
  );
  CachedPatient copyWithCompanion(CachedPatientsCompanion data) {
    return CachedPatient(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      id: data.id.present ? data.id.value : this.id,
      status: data.status.present ? data.status.value : this.status,
      registrationNumber: data.registrationNumber.present
          ? data.registrationNumber.value
          : this.registrationNumber,
      normalizedName: data.normalizedName.present
          ? data.normalizedName.value
          : this.normalizedName,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedPatient(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('status: $status, ')
          ..write('registrationNumber: $registrationNumber, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    id,
    status,
    registrationNumber,
    normalizedName,
    updatedAt,
    payload,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedPatient &&
          other.accountId == this.accountId &&
          other.id == this.id &&
          other.status == this.status &&
          other.registrationNumber == this.registrationNumber &&
          other.normalizedName == this.normalizedName &&
          other.updatedAt == this.updatedAt &&
          other.payload == this.payload);
}

class CachedPatientsCompanion extends UpdateCompanion<CachedPatient> {
  final Value<String> accountId;
  final Value<String> id;
  final Value<String?> status;
  final Value<String?> registrationNumber;
  final Value<String?> normalizedName;
  final Value<int> updatedAt;
  final Value<String> payload;
  final Value<int> rowid;
  const CachedPatientsCompanion({
    this.accountId = const Value.absent(),
    this.id = const Value.absent(),
    this.status = const Value.absent(),
    this.registrationNumber = const Value.absent(),
    this.normalizedName = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedPatientsCompanion.insert({
    required String accountId,
    required String id,
    this.status = const Value.absent(),
    this.registrationNumber = const Value.absent(),
    this.normalizedName = const Value.absent(),
    this.updatedAt = const Value.absent(),
    required String payload,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       id = Value(id),
       payload = Value(payload);
  static Insertable<CachedPatient> custom({
    Expression<String>? accountId,
    Expression<String>? id,
    Expression<String>? status,
    Expression<String>? registrationNumber,
    Expression<String>? normalizedName,
    Expression<int>? updatedAt,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (id != null) 'id': id,
      if (status != null) 'status': status,
      if (registrationNumber != null) 'registration_number': registrationNumber,
      if (normalizedName != null) 'normalized_name': normalizedName,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedPatientsCompanion copyWith({
    Value<String>? accountId,
    Value<String>? id,
    Value<String?>? status,
    Value<String?>? registrationNumber,
    Value<String?>? normalizedName,
    Value<int>? updatedAt,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return CachedPatientsCompanion(
      accountId: accountId ?? this.accountId,
      id: id ?? this.id,
      status: status ?? this.status,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      normalizedName: normalizedName ?? this.normalizedName,
      updatedAt: updatedAt ?? this.updatedAt,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (registrationNumber.present) {
      map['registration_number'] = Variable<String>(registrationNumber.value);
    }
    if (normalizedName.present) {
      map['normalized_name'] = Variable<String>(normalizedName.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedPatientsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('status: $status, ')
          ..write('registrationNumber: $registrationNumber, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedStaysTable extends CachedStays
    with TableInfo<$CachedStaysTable, CachedStay> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedStaysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
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
  static const VerificationMeta _patientIdMeta = const VerificationMeta(
    'patientId',
  );
  @override
  late final GeneratedColumn<String> patientId = GeneratedColumn<String>(
    'patient_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _roomIdMeta = const VerificationMeta('roomId');
  @override
  late final GeneratedColumn<String> roomId = GeneratedColumn<String>(
    'room_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _expectedDischargeDateMeta =
      const VerificationMeta('expectedDischargeDate');
  @override
  late final GeneratedColumn<int> expectedDischargeDate = GeneratedColumn<int>(
    'expected_discharge_date',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
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
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    id,
    patientId,
    roomId,
    status,
    expectedDischargeDate,
    updatedAt,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_stays';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedStay> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('patient_id')) {
      context.handle(
        _patientIdMeta,
        patientId.isAcceptableOrUnknown(data['patient_id']!, _patientIdMeta),
      );
    }
    if (data.containsKey('room_id')) {
      context.handle(
        _roomIdMeta,
        roomId.isAcceptableOrUnknown(data['room_id']!, _roomIdMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('expected_discharge_date')) {
      context.handle(
        _expectedDischargeDateMeta,
        expectedDischargeDate.isAcceptableOrUnknown(
          data['expected_discharge_date']!,
          _expectedDischargeDateMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, id};
  @override
  CachedStay map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedStay(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      patientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}patient_id'],
      ),
      roomId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room_id'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
      expectedDischargeDate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected_discharge_date'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $CachedStaysTable createAlias(String alias) {
    return $CachedStaysTable(attachedDatabase, alias);
  }
}

class CachedStay extends DataClass implements Insertable<CachedStay> {
  final String accountId;
  final String id;
  final String? patientId;
  final String? roomId;
  final String? status;
  final int? expectedDischargeDate;
  final int updatedAt;
  final String payload;
  const CachedStay({
    required this.accountId,
    required this.id,
    this.patientId,
    this.roomId,
    this.status,
    this.expectedDischargeDate,
    required this.updatedAt,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || patientId != null) {
      map['patient_id'] = Variable<String>(patientId);
    }
    if (!nullToAbsent || roomId != null) {
      map['room_id'] = Variable<String>(roomId);
    }
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    if (!nullToAbsent || expectedDischargeDate != null) {
      map['expected_discharge_date'] = Variable<int>(expectedDischargeDate);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  CachedStaysCompanion toCompanion(bool nullToAbsent) {
    return CachedStaysCompanion(
      accountId: Value(accountId),
      id: Value(id),
      patientId: patientId == null && nullToAbsent
          ? const Value.absent()
          : Value(patientId),
      roomId: roomId == null && nullToAbsent
          ? const Value.absent()
          : Value(roomId),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
      expectedDischargeDate: expectedDischargeDate == null && nullToAbsent
          ? const Value.absent()
          : Value(expectedDischargeDate),
      updatedAt: Value(updatedAt),
      payload: Value(payload),
    );
  }

  factory CachedStay.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedStay(
      accountId: serializer.fromJson<String>(json['accountId']),
      id: serializer.fromJson<String>(json['id']),
      patientId: serializer.fromJson<String?>(json['patientId']),
      roomId: serializer.fromJson<String?>(json['roomId']),
      status: serializer.fromJson<String?>(json['status']),
      expectedDischargeDate: serializer.fromJson<int?>(
        json['expectedDischargeDate'],
      ),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'id': serializer.toJson<String>(id),
      'patientId': serializer.toJson<String?>(patientId),
      'roomId': serializer.toJson<String?>(roomId),
      'status': serializer.toJson<String?>(status),
      'expectedDischargeDate': serializer.toJson<int?>(expectedDischargeDate),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'payload': serializer.toJson<String>(payload),
    };
  }

  CachedStay copyWith({
    String? accountId,
    String? id,
    Value<String?> patientId = const Value.absent(),
    Value<String?> roomId = const Value.absent(),
    Value<String?> status = const Value.absent(),
    Value<int?> expectedDischargeDate = const Value.absent(),
    int? updatedAt,
    String? payload,
  }) => CachedStay(
    accountId: accountId ?? this.accountId,
    id: id ?? this.id,
    patientId: patientId.present ? patientId.value : this.patientId,
    roomId: roomId.present ? roomId.value : this.roomId,
    status: status.present ? status.value : this.status,
    expectedDischargeDate: expectedDischargeDate.present
        ? expectedDischargeDate.value
        : this.expectedDischargeDate,
    updatedAt: updatedAt ?? this.updatedAt,
    payload: payload ?? this.payload,
  );
  CachedStay copyWithCompanion(CachedStaysCompanion data) {
    return CachedStay(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      id: data.id.present ? data.id.value : this.id,
      patientId: data.patientId.present ? data.patientId.value : this.patientId,
      roomId: data.roomId.present ? data.roomId.value : this.roomId,
      status: data.status.present ? data.status.value : this.status,
      expectedDischargeDate: data.expectedDischargeDate.present
          ? data.expectedDischargeDate.value
          : this.expectedDischargeDate,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedStay(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('patientId: $patientId, ')
          ..write('roomId: $roomId, ')
          ..write('status: $status, ')
          ..write('expectedDischargeDate: $expectedDischargeDate, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    id,
    patientId,
    roomId,
    status,
    expectedDischargeDate,
    updatedAt,
    payload,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedStay &&
          other.accountId == this.accountId &&
          other.id == this.id &&
          other.patientId == this.patientId &&
          other.roomId == this.roomId &&
          other.status == this.status &&
          other.expectedDischargeDate == this.expectedDischargeDate &&
          other.updatedAt == this.updatedAt &&
          other.payload == this.payload);
}

class CachedStaysCompanion extends UpdateCompanion<CachedStay> {
  final Value<String> accountId;
  final Value<String> id;
  final Value<String?> patientId;
  final Value<String?> roomId;
  final Value<String?> status;
  final Value<int?> expectedDischargeDate;
  final Value<int> updatedAt;
  final Value<String> payload;
  final Value<int> rowid;
  const CachedStaysCompanion({
    this.accountId = const Value.absent(),
    this.id = const Value.absent(),
    this.patientId = const Value.absent(),
    this.roomId = const Value.absent(),
    this.status = const Value.absent(),
    this.expectedDischargeDate = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedStaysCompanion.insert({
    required String accountId,
    required String id,
    this.patientId = const Value.absent(),
    this.roomId = const Value.absent(),
    this.status = const Value.absent(),
    this.expectedDischargeDate = const Value.absent(),
    this.updatedAt = const Value.absent(),
    required String payload,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       id = Value(id),
       payload = Value(payload);
  static Insertable<CachedStay> custom({
    Expression<String>? accountId,
    Expression<String>? id,
    Expression<String>? patientId,
    Expression<String>? roomId,
    Expression<String>? status,
    Expression<int>? expectedDischargeDate,
    Expression<int>? updatedAt,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (id != null) 'id': id,
      if (patientId != null) 'patient_id': patientId,
      if (roomId != null) 'room_id': roomId,
      if (status != null) 'status': status,
      if (expectedDischargeDate != null)
        'expected_discharge_date': expectedDischargeDate,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedStaysCompanion copyWith({
    Value<String>? accountId,
    Value<String>? id,
    Value<String?>? patientId,
    Value<String?>? roomId,
    Value<String?>? status,
    Value<int?>? expectedDischargeDate,
    Value<int>? updatedAt,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return CachedStaysCompanion(
      accountId: accountId ?? this.accountId,
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      roomId: roomId ?? this.roomId,
      status: status ?? this.status,
      expectedDischargeDate:
          expectedDischargeDate ?? this.expectedDischargeDate,
      updatedAt: updatedAt ?? this.updatedAt,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (patientId.present) {
      map['patient_id'] = Variable<String>(patientId.value);
    }
    if (roomId.present) {
      map['room_id'] = Variable<String>(roomId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (expectedDischargeDate.present) {
      map['expected_discharge_date'] = Variable<int>(
        expectedDischargeDate.value,
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedStaysCompanion(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('patientId: $patientId, ')
          ..write('roomId: $roomId, ')
          ..write('status: $status, ')
          ..write('expectedDischargeDate: $expectedDischargeDate, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedRoomsTable extends CachedRooms
    with TableInfo<$CachedRoomsTable, CachedRoom> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedRoomsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
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
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _floorMeta = const VerificationMeta('floor');
  @override
  late final GeneratedColumn<int> floor = GeneratedColumn<int>(
    'floor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _roomTypeMeta = const VerificationMeta(
    'roomType',
  );
  @override
  late final GeneratedColumn<String> roomType = GeneratedColumn<String>(
    'room_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    id,
    status,
    floor,
    roomType,
    updatedAt,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_rooms';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedRoom> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('floor')) {
      context.handle(
        _floorMeta,
        floor.isAcceptableOrUnknown(data['floor']!, _floorMeta),
      );
    }
    if (data.containsKey('room_type')) {
      context.handle(
        _roomTypeMeta,
        roomType.isAcceptableOrUnknown(data['room_type']!, _roomTypeMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, id};
  @override
  CachedRoom map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedRoom(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
      floor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}floor'],
      ),
      roomType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room_type'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $CachedRoomsTable createAlias(String alias) {
    return $CachedRoomsTable(attachedDatabase, alias);
  }
}

class CachedRoom extends DataClass implements Insertable<CachedRoom> {
  final String accountId;
  final String id;
  final String? status;
  final int? floor;
  final String? roomType;
  final int updatedAt;
  final String payload;
  const CachedRoom({
    required this.accountId,
    required this.id,
    this.status,
    this.floor,
    this.roomType,
    required this.updatedAt,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    if (!nullToAbsent || floor != null) {
      map['floor'] = Variable<int>(floor);
    }
    if (!nullToAbsent || roomType != null) {
      map['room_type'] = Variable<String>(roomType);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  CachedRoomsCompanion toCompanion(bool nullToAbsent) {
    return CachedRoomsCompanion(
      accountId: Value(accountId),
      id: Value(id),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
      floor: floor == null && nullToAbsent
          ? const Value.absent()
          : Value(floor),
      roomType: roomType == null && nullToAbsent
          ? const Value.absent()
          : Value(roomType),
      updatedAt: Value(updatedAt),
      payload: Value(payload),
    );
  }

  factory CachedRoom.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedRoom(
      accountId: serializer.fromJson<String>(json['accountId']),
      id: serializer.fromJson<String>(json['id']),
      status: serializer.fromJson<String?>(json['status']),
      floor: serializer.fromJson<int?>(json['floor']),
      roomType: serializer.fromJson<String?>(json['roomType']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'id': serializer.toJson<String>(id),
      'status': serializer.toJson<String?>(status),
      'floor': serializer.toJson<int?>(floor),
      'roomType': serializer.toJson<String?>(roomType),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'payload': serializer.toJson<String>(payload),
    };
  }

  CachedRoom copyWith({
    String? accountId,
    String? id,
    Value<String?> status = const Value.absent(),
    Value<int?> floor = const Value.absent(),
    Value<String?> roomType = const Value.absent(),
    int? updatedAt,
    String? payload,
  }) => CachedRoom(
    accountId: accountId ?? this.accountId,
    id: id ?? this.id,
    status: status.present ? status.value : this.status,
    floor: floor.present ? floor.value : this.floor,
    roomType: roomType.present ? roomType.value : this.roomType,
    updatedAt: updatedAt ?? this.updatedAt,
    payload: payload ?? this.payload,
  );
  CachedRoom copyWithCompanion(CachedRoomsCompanion data) {
    return CachedRoom(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      id: data.id.present ? data.id.value : this.id,
      status: data.status.present ? data.status.value : this.status,
      floor: data.floor.present ? data.floor.value : this.floor,
      roomType: data.roomType.present ? data.roomType.value : this.roomType,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedRoom(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('status: $status, ')
          ..write('floor: $floor, ')
          ..write('roomType: $roomType, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(accountId, id, status, floor, roomType, updatedAt, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedRoom &&
          other.accountId == this.accountId &&
          other.id == this.id &&
          other.status == this.status &&
          other.floor == this.floor &&
          other.roomType == this.roomType &&
          other.updatedAt == this.updatedAt &&
          other.payload == this.payload);
}

class CachedRoomsCompanion extends UpdateCompanion<CachedRoom> {
  final Value<String> accountId;
  final Value<String> id;
  final Value<String?> status;
  final Value<int?> floor;
  final Value<String?> roomType;
  final Value<int> updatedAt;
  final Value<String> payload;
  final Value<int> rowid;
  const CachedRoomsCompanion({
    this.accountId = const Value.absent(),
    this.id = const Value.absent(),
    this.status = const Value.absent(),
    this.floor = const Value.absent(),
    this.roomType = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedRoomsCompanion.insert({
    required String accountId,
    required String id,
    this.status = const Value.absent(),
    this.floor = const Value.absent(),
    this.roomType = const Value.absent(),
    this.updatedAt = const Value.absent(),
    required String payload,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       id = Value(id),
       payload = Value(payload);
  static Insertable<CachedRoom> custom({
    Expression<String>? accountId,
    Expression<String>? id,
    Expression<String>? status,
    Expression<int>? floor,
    Expression<String>? roomType,
    Expression<int>? updatedAt,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (id != null) 'id': id,
      if (status != null) 'status': status,
      if (floor != null) 'floor': floor,
      if (roomType != null) 'room_type': roomType,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedRoomsCompanion copyWith({
    Value<String>? accountId,
    Value<String>? id,
    Value<String?>? status,
    Value<int?>? floor,
    Value<String?>? roomType,
    Value<int>? updatedAt,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return CachedRoomsCompanion(
      accountId: accountId ?? this.accountId,
      id: id ?? this.id,
      status: status ?? this.status,
      floor: floor ?? this.floor,
      roomType: roomType ?? this.roomType,
      updatedAt: updatedAt ?? this.updatedAt,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (floor.present) {
      map['floor'] = Variable<int>(floor.value);
    }
    if (roomType.present) {
      map['room_type'] = Variable<String>(roomType.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedRoomsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('status: $status, ')
          ..write('floor: $floor, ')
          ..write('roomType: $roomType, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedAttendanceTable extends CachedAttendance
    with TableInfo<$CachedAttendanceTable, CachedAttendanceData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedAttendanceTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
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
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _patientIdMeta = const VerificationMeta(
    'patientId',
  );
  @override
  late final GeneratedColumn<String> patientId = GeneratedColumn<String>(
    'patient_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    id,
    kind,
    date,
    patientId,
    updatedAt,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_attendance';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedAttendanceData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
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
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('patient_id')) {
      context.handle(
        _patientIdMeta,
        patientId.isAcceptableOrUnknown(data['patient_id']!, _patientIdMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, id};
  @override
  CachedAttendanceData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedAttendanceData(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      patientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}patient_id'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $CachedAttendanceTable createAlias(String alias) {
    return $CachedAttendanceTable(attachedDatabase, alias);
  }
}

class CachedAttendanceData extends DataClass
    implements Insertable<CachedAttendanceData> {
  final String accountId;
  final String id;
  final String kind;
  final String date;
  final String? patientId;
  final int updatedAt;
  final String payload;
  const CachedAttendanceData({
    required this.accountId,
    required this.id,
    required this.kind,
    required this.date,
    this.patientId,
    required this.updatedAt,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    map['date'] = Variable<String>(date);
    if (!nullToAbsent || patientId != null) {
      map['patient_id'] = Variable<String>(patientId);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  CachedAttendanceCompanion toCompanion(bool nullToAbsent) {
    return CachedAttendanceCompanion(
      accountId: Value(accountId),
      id: Value(id),
      kind: Value(kind),
      date: Value(date),
      patientId: patientId == null && nullToAbsent
          ? const Value.absent()
          : Value(patientId),
      updatedAt: Value(updatedAt),
      payload: Value(payload),
    );
  }

  factory CachedAttendanceData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedAttendanceData(
      accountId: serializer.fromJson<String>(json['accountId']),
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      date: serializer.fromJson<String>(json['date']),
      patientId: serializer.fromJson<String?>(json['patientId']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'date': serializer.toJson<String>(date),
      'patientId': serializer.toJson<String?>(patientId),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'payload': serializer.toJson<String>(payload),
    };
  }

  CachedAttendanceData copyWith({
    String? accountId,
    String? id,
    String? kind,
    String? date,
    Value<String?> patientId = const Value.absent(),
    int? updatedAt,
    String? payload,
  }) => CachedAttendanceData(
    accountId: accountId ?? this.accountId,
    id: id ?? this.id,
    kind: kind ?? this.kind,
    date: date ?? this.date,
    patientId: patientId.present ? patientId.value : this.patientId,
    updatedAt: updatedAt ?? this.updatedAt,
    payload: payload ?? this.payload,
  );
  CachedAttendanceData copyWithCompanion(CachedAttendanceCompanion data) {
    return CachedAttendanceData(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      date: data.date.present ? data.date.value : this.date,
      patientId: data.patientId.present ? data.patientId.value : this.patientId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedAttendanceData(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('date: $date, ')
          ..write('patientId: $patientId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(accountId, id, kind, date, patientId, updatedAt, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedAttendanceData &&
          other.accountId == this.accountId &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.date == this.date &&
          other.patientId == this.patientId &&
          other.updatedAt == this.updatedAt &&
          other.payload == this.payload);
}

class CachedAttendanceCompanion extends UpdateCompanion<CachedAttendanceData> {
  final Value<String> accountId;
  final Value<String> id;
  final Value<String> kind;
  final Value<String> date;
  final Value<String?> patientId;
  final Value<int> updatedAt;
  final Value<String> payload;
  final Value<int> rowid;
  const CachedAttendanceCompanion({
    this.accountId = const Value.absent(),
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.date = const Value.absent(),
    this.patientId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedAttendanceCompanion.insert({
    required String accountId,
    required String id,
    required String kind,
    required String date,
    this.patientId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    required String payload,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       id = Value(id),
       kind = Value(kind),
       date = Value(date),
       payload = Value(payload);
  static Insertable<CachedAttendanceData> custom({
    Expression<String>? accountId,
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? date,
    Expression<String>? patientId,
    Expression<int>? updatedAt,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (date != null) 'date': date,
      if (patientId != null) 'patient_id': patientId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedAttendanceCompanion copyWith({
    Value<String>? accountId,
    Value<String>? id,
    Value<String>? kind,
    Value<String>? date,
    Value<String?>? patientId,
    Value<int>? updatedAt,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return CachedAttendanceCompanion(
      accountId: accountId ?? this.accountId,
      id: id ?? this.id,
      kind: kind ?? this.kind,
      date: date ?? this.date,
      patientId: patientId ?? this.patientId,
      updatedAt: updatedAt ?? this.updatedAt,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (patientId.present) {
      map['patient_id'] = Variable<String>(patientId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedAttendanceCompanion(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('date: $date, ')
          ..write('patientId: $patientId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedPaymentsTable extends CachedPayments
    with TableInfo<$CachedPaymentsTable, CachedPayment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedPaymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
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
  static const VerificationMeta _collectionMeta = const VerificationMeta(
    'collection',
  );
  @override
  late final GeneratedColumn<String> collection = GeneratedColumn<String>(
    'collection',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _patientIdMeta = const VerificationMeta(
    'patientId',
  );
  @override
  late final GeneratedColumn<String> patientId = GeneratedColumn<String>(
    'patient_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<int> date = GeneratedColumn<int>(
    'date',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
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
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    id,
    collection,
    patientId,
    date,
    updatedAt,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_payments';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedPayment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('collection')) {
      context.handle(
        _collectionMeta,
        collection.isAcceptableOrUnknown(data['collection']!, _collectionMeta),
      );
    } else if (isInserting) {
      context.missing(_collectionMeta);
    }
    if (data.containsKey('patient_id')) {
      context.handle(
        _patientIdMeta,
        patientId.isAcceptableOrUnknown(data['patient_id']!, _patientIdMeta),
      );
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, collection, id};
  @override
  CachedPayment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedPayment(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      collection: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection'],
      )!,
      patientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}patient_id'],
      ),
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $CachedPaymentsTable createAlias(String alias) {
    return $CachedPaymentsTable(attachedDatabase, alias);
  }
}

class CachedPayment extends DataClass implements Insertable<CachedPayment> {
  final String accountId;
  final String id;
  final String collection;
  final String? patientId;
  final int? date;
  final int updatedAt;
  final String payload;
  const CachedPayment({
    required this.accountId,
    required this.id,
    required this.collection,
    this.patientId,
    this.date,
    required this.updatedAt,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['id'] = Variable<String>(id);
    map['collection'] = Variable<String>(collection);
    if (!nullToAbsent || patientId != null) {
      map['patient_id'] = Variable<String>(patientId);
    }
    if (!nullToAbsent || date != null) {
      map['date'] = Variable<int>(date);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  CachedPaymentsCompanion toCompanion(bool nullToAbsent) {
    return CachedPaymentsCompanion(
      accountId: Value(accountId),
      id: Value(id),
      collection: Value(collection),
      patientId: patientId == null && nullToAbsent
          ? const Value.absent()
          : Value(patientId),
      date: date == null && nullToAbsent ? const Value.absent() : Value(date),
      updatedAt: Value(updatedAt),
      payload: Value(payload),
    );
  }

  factory CachedPayment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedPayment(
      accountId: serializer.fromJson<String>(json['accountId']),
      id: serializer.fromJson<String>(json['id']),
      collection: serializer.fromJson<String>(json['collection']),
      patientId: serializer.fromJson<String?>(json['patientId']),
      date: serializer.fromJson<int?>(json['date']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'id': serializer.toJson<String>(id),
      'collection': serializer.toJson<String>(collection),
      'patientId': serializer.toJson<String?>(patientId),
      'date': serializer.toJson<int?>(date),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'payload': serializer.toJson<String>(payload),
    };
  }

  CachedPayment copyWith({
    String? accountId,
    String? id,
    String? collection,
    Value<String?> patientId = const Value.absent(),
    Value<int?> date = const Value.absent(),
    int? updatedAt,
    String? payload,
  }) => CachedPayment(
    accountId: accountId ?? this.accountId,
    id: id ?? this.id,
    collection: collection ?? this.collection,
    patientId: patientId.present ? patientId.value : this.patientId,
    date: date.present ? date.value : this.date,
    updatedAt: updatedAt ?? this.updatedAt,
    payload: payload ?? this.payload,
  );
  CachedPayment copyWithCompanion(CachedPaymentsCompanion data) {
    return CachedPayment(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      id: data.id.present ? data.id.value : this.id,
      collection: data.collection.present
          ? data.collection.value
          : this.collection,
      patientId: data.patientId.present ? data.patientId.value : this.patientId,
      date: data.date.present ? data.date.value : this.date,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedPayment(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('collection: $collection, ')
          ..write('patientId: $patientId, ')
          ..write('date: $date, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    id,
    collection,
    patientId,
    date,
    updatedAt,
    payload,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedPayment &&
          other.accountId == this.accountId &&
          other.id == this.id &&
          other.collection == this.collection &&
          other.patientId == this.patientId &&
          other.date == this.date &&
          other.updatedAt == this.updatedAt &&
          other.payload == this.payload);
}

class CachedPaymentsCompanion extends UpdateCompanion<CachedPayment> {
  final Value<String> accountId;
  final Value<String> id;
  final Value<String> collection;
  final Value<String?> patientId;
  final Value<int?> date;
  final Value<int> updatedAt;
  final Value<String> payload;
  final Value<int> rowid;
  const CachedPaymentsCompanion({
    this.accountId = const Value.absent(),
    this.id = const Value.absent(),
    this.collection = const Value.absent(),
    this.patientId = const Value.absent(),
    this.date = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedPaymentsCompanion.insert({
    required String accountId,
    required String id,
    required String collection,
    this.patientId = const Value.absent(),
    this.date = const Value.absent(),
    this.updatedAt = const Value.absent(),
    required String payload,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       id = Value(id),
       collection = Value(collection),
       payload = Value(payload);
  static Insertable<CachedPayment> custom({
    Expression<String>? accountId,
    Expression<String>? id,
    Expression<String>? collection,
    Expression<String>? patientId,
    Expression<int>? date,
    Expression<int>? updatedAt,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (id != null) 'id': id,
      if (collection != null) 'collection': collection,
      if (patientId != null) 'patient_id': patientId,
      if (date != null) 'date': date,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedPaymentsCompanion copyWith({
    Value<String>? accountId,
    Value<String>? id,
    Value<String>? collection,
    Value<String?>? patientId,
    Value<int?>? date,
    Value<int>? updatedAt,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return CachedPaymentsCompanion(
      accountId: accountId ?? this.accountId,
      id: id ?? this.id,
      collection: collection ?? this.collection,
      patientId: patientId ?? this.patientId,
      date: date ?? this.date,
      updatedAt: updatedAt ?? this.updatedAt,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (collection.present) {
      map['collection'] = Variable<String>(collection.value);
    }
    if (patientId.present) {
      map['patient_id'] = Variable<String>(patientId.value);
    }
    if (date.present) {
      map['date'] = Variable<int>(date.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedPaymentsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('collection: $collection, ')
          ..write('patientId: $patientId, ')
          ..write('date: $date, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedProfilesTable extends CachedProfiles
    with TableInfo<$CachedProfilesTable, CachedProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [accountId, id, updatedAt, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, id};
  @override
  CachedProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedProfile(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $CachedProfilesTable createAlias(String alias) {
    return $CachedProfilesTable(attachedDatabase, alias);
  }
}

class CachedProfile extends DataClass implements Insertable<CachedProfile> {
  final String accountId;
  final String id;
  final int updatedAt;
  final String payload;
  const CachedProfile({
    required this.accountId,
    required this.id,
    required this.updatedAt,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['id'] = Variable<String>(id);
    map['updated_at'] = Variable<int>(updatedAt);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  CachedProfilesCompanion toCompanion(bool nullToAbsent) {
    return CachedProfilesCompanion(
      accountId: Value(accountId),
      id: Value(id),
      updatedAt: Value(updatedAt),
      payload: Value(payload),
    );
  }

  factory CachedProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedProfile(
      accountId: serializer.fromJson<String>(json['accountId']),
      id: serializer.fromJson<String>(json['id']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'id': serializer.toJson<String>(id),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'payload': serializer.toJson<String>(payload),
    };
  }

  CachedProfile copyWith({
    String? accountId,
    String? id,
    int? updatedAt,
    String? payload,
  }) => CachedProfile(
    accountId: accountId ?? this.accountId,
    id: id ?? this.id,
    updatedAt: updatedAt ?? this.updatedAt,
    payload: payload ?? this.payload,
  );
  CachedProfile copyWithCompanion(CachedProfilesCompanion data) {
    return CachedProfile(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      id: data.id.present ? data.id.value : this.id,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedProfile(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, id, updatedAt, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedProfile &&
          other.accountId == this.accountId &&
          other.id == this.id &&
          other.updatedAt == this.updatedAt &&
          other.payload == this.payload);
}

class CachedProfilesCompanion extends UpdateCompanion<CachedProfile> {
  final Value<String> accountId;
  final Value<String> id;
  final Value<int> updatedAt;
  final Value<String> payload;
  final Value<int> rowid;
  const CachedProfilesCompanion({
    this.accountId = const Value.absent(),
    this.id = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedProfilesCompanion.insert({
    required String accountId,
    required String id,
    this.updatedAt = const Value.absent(),
    required String payload,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       id = Value(id),
       payload = Value(payload);
  static Insertable<CachedProfile> custom({
    Expression<String>? accountId,
    Expression<String>? id,
    Expression<int>? updatedAt,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (id != null) 'id': id,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedProfilesCompanion copyWith({
    Value<String>? accountId,
    Value<String>? id,
    Value<int>? updatedAt,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return CachedProfilesCompanion(
      accountId: accountId ?? this.accountId,
      id: id ?? this.id,
      updatedAt: updatedAt ?? this.updatedAt,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedProfilesCompanion(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedSettingsTable extends CachedSettings
    with TableInfo<$CachedSettingsTable, CachedSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [accountId, id, updatedAt, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, id};
  @override
  CachedSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedSetting(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $CachedSettingsTable createAlias(String alias) {
    return $CachedSettingsTable(attachedDatabase, alias);
  }
}

class CachedSetting extends DataClass implements Insertable<CachedSetting> {
  final String accountId;
  final String id;
  final int updatedAt;
  final String payload;
  const CachedSetting({
    required this.accountId,
    required this.id,
    required this.updatedAt,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['id'] = Variable<String>(id);
    map['updated_at'] = Variable<int>(updatedAt);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  CachedSettingsCompanion toCompanion(bool nullToAbsent) {
    return CachedSettingsCompanion(
      accountId: Value(accountId),
      id: Value(id),
      updatedAt: Value(updatedAt),
      payload: Value(payload),
    );
  }

  factory CachedSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedSetting(
      accountId: serializer.fromJson<String>(json['accountId']),
      id: serializer.fromJson<String>(json['id']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'id': serializer.toJson<String>(id),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'payload': serializer.toJson<String>(payload),
    };
  }

  CachedSetting copyWith({
    String? accountId,
    String? id,
    int? updatedAt,
    String? payload,
  }) => CachedSetting(
    accountId: accountId ?? this.accountId,
    id: id ?? this.id,
    updatedAt: updatedAt ?? this.updatedAt,
    payload: payload ?? this.payload,
  );
  CachedSetting copyWithCompanion(CachedSettingsCompanion data) {
    return CachedSetting(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      id: data.id.present ? data.id.value : this.id,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedSetting(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, id, updatedAt, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedSetting &&
          other.accountId == this.accountId &&
          other.id == this.id &&
          other.updatedAt == this.updatedAt &&
          other.payload == this.payload);
}

class CachedSettingsCompanion extends UpdateCompanion<CachedSetting> {
  final Value<String> accountId;
  final Value<String> id;
  final Value<int> updatedAt;
  final Value<String> payload;
  final Value<int> rowid;
  const CachedSettingsCompanion({
    this.accountId = const Value.absent(),
    this.id = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedSettingsCompanion.insert({
    required String accountId,
    required String id,
    this.updatedAt = const Value.absent(),
    required String payload,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       id = Value(id),
       payload = Value(payload);
  static Insertable<CachedSetting> custom({
    Expression<String>? accountId,
    Expression<String>? id,
    Expression<int>? updatedAt,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (id != null) 'id': id,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedSettingsCompanion copyWith({
    Value<String>? accountId,
    Value<String>? id,
    Value<int>? updatedAt,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return CachedSettingsCompanion(
      accountId: accountId ?? this.accountId,
      id: id ?? this.id,
      updatedAt: updatedAt ?? this.updatedAt,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedSettingsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedPhotoMetadataTable extends CachedPhotoMetadata
    with TableInfo<$CachedPhotoMetadataTable, CachedPhotoMetadataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedPhotoMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _photoRefMeta = const VerificationMeta(
    'photoRef',
  );
  @override
  late final GeneratedColumn<String> photoRef = GeneratedColumn<String>(
    'photo_ref',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _contentTypeMeta = const VerificationMeta(
    'contentType',
  );
  @override
  late final GeneratedColumn<String> contentType = GeneratedColumn<String>(
    'content_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastAccessedAtMeta = const VerificationMeta(
    'lastAccessedAt',
  );
  @override
  late final GeneratedColumn<int> lastAccessedAt = GeneratedColumn<int>(
    'last_accessed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    photoRef,
    version,
    contentType,
    contentHash,
    updatedAt,
    lastAccessedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_photo_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedPhotoMetadataData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('photo_ref')) {
      context.handle(
        _photoRefMeta,
        photoRef.isAcceptableOrUnknown(data['photo_ref']!, _photoRefMeta),
      );
    } else if (isInserting) {
      context.missing(_photoRefMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('content_type')) {
      context.handle(
        _contentTypeMeta,
        contentType.isAcceptableOrUnknown(
          data['content_type']!,
          _contentTypeMeta,
        ),
      );
    }
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('last_accessed_at')) {
      context.handle(
        _lastAccessedAtMeta,
        lastAccessedAt.isAcceptableOrUnknown(
          data['last_accessed_at']!,
          _lastAccessedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, photoRef};
  @override
  CachedPhotoMetadataData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedPhotoMetadataData(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      photoRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_ref'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      contentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_type'],
      ),
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      lastAccessedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_accessed_at'],
      )!,
    );
  }

  @override
  $CachedPhotoMetadataTable createAlias(String alias) {
    return $CachedPhotoMetadataTable(attachedDatabase, alias);
  }
}

class CachedPhotoMetadataData extends DataClass
    implements Insertable<CachedPhotoMetadataData> {
  final String accountId;
  final String photoRef;
  final int version;
  final String? contentType;
  final String? contentHash;
  final int updatedAt;
  final int lastAccessedAt;
  const CachedPhotoMetadataData({
    required this.accountId,
    required this.photoRef,
    required this.version,
    this.contentType,
    this.contentHash,
    required this.updatedAt,
    required this.lastAccessedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['photo_ref'] = Variable<String>(photoRef);
    map['version'] = Variable<int>(version);
    if (!nullToAbsent || contentType != null) {
      map['content_type'] = Variable<String>(contentType);
    }
    if (!nullToAbsent || contentHash != null) {
      map['content_hash'] = Variable<String>(contentHash);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    map['last_accessed_at'] = Variable<int>(lastAccessedAt);
    return map;
  }

  CachedPhotoMetadataCompanion toCompanion(bool nullToAbsent) {
    return CachedPhotoMetadataCompanion(
      accountId: Value(accountId),
      photoRef: Value(photoRef),
      version: Value(version),
      contentType: contentType == null && nullToAbsent
          ? const Value.absent()
          : Value(contentType),
      contentHash: contentHash == null && nullToAbsent
          ? const Value.absent()
          : Value(contentHash),
      updatedAt: Value(updatedAt),
      lastAccessedAt: Value(lastAccessedAt),
    );
  }

  factory CachedPhotoMetadataData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedPhotoMetadataData(
      accountId: serializer.fromJson<String>(json['accountId']),
      photoRef: serializer.fromJson<String>(json['photoRef']),
      version: serializer.fromJson<int>(json['version']),
      contentType: serializer.fromJson<String?>(json['contentType']),
      contentHash: serializer.fromJson<String?>(json['contentHash']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      lastAccessedAt: serializer.fromJson<int>(json['lastAccessedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'photoRef': serializer.toJson<String>(photoRef),
      'version': serializer.toJson<int>(version),
      'contentType': serializer.toJson<String?>(contentType),
      'contentHash': serializer.toJson<String?>(contentHash),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'lastAccessedAt': serializer.toJson<int>(lastAccessedAt),
    };
  }

  CachedPhotoMetadataData copyWith({
    String? accountId,
    String? photoRef,
    int? version,
    Value<String?> contentType = const Value.absent(),
    Value<String?> contentHash = const Value.absent(),
    int? updatedAt,
    int? lastAccessedAt,
  }) => CachedPhotoMetadataData(
    accountId: accountId ?? this.accountId,
    photoRef: photoRef ?? this.photoRef,
    version: version ?? this.version,
    contentType: contentType.present ? contentType.value : this.contentType,
    contentHash: contentHash.present ? contentHash.value : this.contentHash,
    updatedAt: updatedAt ?? this.updatedAt,
    lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
  );
  CachedPhotoMetadataData copyWithCompanion(CachedPhotoMetadataCompanion data) {
    return CachedPhotoMetadataData(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      photoRef: data.photoRef.present ? data.photoRef.value : this.photoRef,
      version: data.version.present ? data.version.value : this.version,
      contentType: data.contentType.present
          ? data.contentType.value
          : this.contentType,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      lastAccessedAt: data.lastAccessedAt.present
          ? data.lastAccessedAt.value
          : this.lastAccessedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedPhotoMetadataData(')
          ..write('accountId: $accountId, ')
          ..write('photoRef: $photoRef, ')
          ..write('version: $version, ')
          ..write('contentType: $contentType, ')
          ..write('contentHash: $contentHash, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastAccessedAt: $lastAccessedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    photoRef,
    version,
    contentType,
    contentHash,
    updatedAt,
    lastAccessedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedPhotoMetadataData &&
          other.accountId == this.accountId &&
          other.photoRef == this.photoRef &&
          other.version == this.version &&
          other.contentType == this.contentType &&
          other.contentHash == this.contentHash &&
          other.updatedAt == this.updatedAt &&
          other.lastAccessedAt == this.lastAccessedAt);
}

class CachedPhotoMetadataCompanion
    extends UpdateCompanion<CachedPhotoMetadataData> {
  final Value<String> accountId;
  final Value<String> photoRef;
  final Value<int> version;
  final Value<String?> contentType;
  final Value<String?> contentHash;
  final Value<int> updatedAt;
  final Value<int> lastAccessedAt;
  final Value<int> rowid;
  const CachedPhotoMetadataCompanion({
    this.accountId = const Value.absent(),
    this.photoRef = const Value.absent(),
    this.version = const Value.absent(),
    this.contentType = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastAccessedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedPhotoMetadataCompanion.insert({
    required String accountId,
    required String photoRef,
    this.version = const Value.absent(),
    this.contentType = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastAccessedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       photoRef = Value(photoRef);
  static Insertable<CachedPhotoMetadataData> custom({
    Expression<String>? accountId,
    Expression<String>? photoRef,
    Expression<int>? version,
    Expression<String>? contentType,
    Expression<String>? contentHash,
    Expression<int>? updatedAt,
    Expression<int>? lastAccessedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (photoRef != null) 'photo_ref': photoRef,
      if (version != null) 'version': version,
      if (contentType != null) 'content_type': contentType,
      if (contentHash != null) 'content_hash': contentHash,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (lastAccessedAt != null) 'last_accessed_at': lastAccessedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedPhotoMetadataCompanion copyWith({
    Value<String>? accountId,
    Value<String>? photoRef,
    Value<int>? version,
    Value<String?>? contentType,
    Value<String?>? contentHash,
    Value<int>? updatedAt,
    Value<int>? lastAccessedAt,
    Value<int>? rowid,
  }) {
    return CachedPhotoMetadataCompanion(
      accountId: accountId ?? this.accountId,
      photoRef: photoRef ?? this.photoRef,
      version: version ?? this.version,
      contentType: contentType ?? this.contentType,
      contentHash: contentHash ?? this.contentHash,
      updatedAt: updatedAt ?? this.updatedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (photoRef.present) {
      map['photo_ref'] = Variable<String>(photoRef.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (contentType.present) {
      map['content_type'] = Variable<String>(contentType.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (lastAccessedAt.present) {
      map['last_accessed_at'] = Variable<int>(lastAccessedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedPhotoMetadataCompanion(')
          ..write('accountId: $accountId, ')
          ..write('photoRef: $photoRef, ')
          ..write('version: $version, ')
          ..write('contentType: $contentType, ')
          ..write('contentHash: $contentHash, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastAccessedAt: $lastAccessedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStatesTable extends SyncStates
    with TableInfo<$SyncStatesTable, SyncState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSuccessfulSyncMeta =
      const VerificationMeta('lastSuccessfulSync');
  @override
  late final GeneratedColumn<int> lastSuccessfulSync = GeneratedColumn<int>(
    'last_successful_sync',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _highWaterMarkMeta = const VerificationMeta(
    'highWaterMark',
  );
  @override
  late final GeneratedColumn<int> highWaterMark = GeneratedColumn<int>(
    'high_water_mark',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('idle'),
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    entity,
    lastSuccessfulSync,
    highWaterMark,
    schemaVersion,
    status,
    error,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('last_successful_sync')) {
      context.handle(
        _lastSuccessfulSyncMeta,
        lastSuccessfulSync.isAcceptableOrUnknown(
          data['last_successful_sync']!,
          _lastSuccessfulSyncMeta,
        ),
      );
    }
    if (data.containsKey('high_water_mark')) {
      context.handle(
        _highWaterMarkMeta,
        highWaterMark.isAcceptableOrUnknown(
          data['high_water_mark']!,
          _highWaterMarkMeta,
        ),
      );
    }
    if (data.containsKey('schema_version')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schema_version']!,
          _schemaVersionMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, entity};
  @override
  SyncState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncState(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      lastSuccessfulSync: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_successful_sync'],
      ),
      highWaterMark: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}high_water_mark'],
      ),
      schemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_version'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
    );
  }

  @override
  $SyncStatesTable createAlias(String alias) {
    return $SyncStatesTable(attachedDatabase, alias);
  }
}

class SyncState extends DataClass implements Insertable<SyncState> {
  final String accountId;
  final String entity;
  final int? lastSuccessfulSync;
  final int? highWaterMark;
  final int schemaVersion;
  final String status;
  final String? error;
  const SyncState({
    required this.accountId,
    required this.entity,
    this.lastSuccessfulSync,
    this.highWaterMark,
    required this.schemaVersion,
    required this.status,
    this.error,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['entity'] = Variable<String>(entity);
    if (!nullToAbsent || lastSuccessfulSync != null) {
      map['last_successful_sync'] = Variable<int>(lastSuccessfulSync);
    }
    if (!nullToAbsent || highWaterMark != null) {
      map['high_water_mark'] = Variable<int>(highWaterMark);
    }
    map['schema_version'] = Variable<int>(schemaVersion);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    return map;
  }

  SyncStatesCompanion toCompanion(bool nullToAbsent) {
    return SyncStatesCompanion(
      accountId: Value(accountId),
      entity: Value(entity),
      lastSuccessfulSync: lastSuccessfulSync == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSuccessfulSync),
      highWaterMark: highWaterMark == null && nullToAbsent
          ? const Value.absent()
          : Value(highWaterMark),
      schemaVersion: Value(schemaVersion),
      status: Value(status),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
    );
  }

  factory SyncState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncState(
      accountId: serializer.fromJson<String>(json['accountId']),
      entity: serializer.fromJson<String>(json['entity']),
      lastSuccessfulSync: serializer.fromJson<int?>(json['lastSuccessfulSync']),
      highWaterMark: serializer.fromJson<int?>(json['highWaterMark']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      status: serializer.fromJson<String>(json['status']),
      error: serializer.fromJson<String?>(json['error']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'entity': serializer.toJson<String>(entity),
      'lastSuccessfulSync': serializer.toJson<int?>(lastSuccessfulSync),
      'highWaterMark': serializer.toJson<int?>(highWaterMark),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'status': serializer.toJson<String>(status),
      'error': serializer.toJson<String?>(error),
    };
  }

  SyncState copyWith({
    String? accountId,
    String? entity,
    Value<int?> lastSuccessfulSync = const Value.absent(),
    Value<int?> highWaterMark = const Value.absent(),
    int? schemaVersion,
    String? status,
    Value<String?> error = const Value.absent(),
  }) => SyncState(
    accountId: accountId ?? this.accountId,
    entity: entity ?? this.entity,
    lastSuccessfulSync: lastSuccessfulSync.present
        ? lastSuccessfulSync.value
        : this.lastSuccessfulSync,
    highWaterMark: highWaterMark.present
        ? highWaterMark.value
        : this.highWaterMark,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    status: status ?? this.status,
    error: error.present ? error.value : this.error,
  );
  SyncState copyWithCompanion(SyncStatesCompanion data) {
    return SyncState(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      entity: data.entity.present ? data.entity.value : this.entity,
      lastSuccessfulSync: data.lastSuccessfulSync.present
          ? data.lastSuccessfulSync.value
          : this.lastSuccessfulSync,
      highWaterMark: data.highWaterMark.present
          ? data.highWaterMark.value
          : this.highWaterMark,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      status: data.status.present ? data.status.value : this.status,
      error: data.error.present ? data.error.value : this.error,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncState(')
          ..write('accountId: $accountId, ')
          ..write('entity: $entity, ')
          ..write('lastSuccessfulSync: $lastSuccessfulSync, ')
          ..write('highWaterMark: $highWaterMark, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('status: $status, ')
          ..write('error: $error')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    entity,
    lastSuccessfulSync,
    highWaterMark,
    schemaVersion,
    status,
    error,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncState &&
          other.accountId == this.accountId &&
          other.entity == this.entity &&
          other.lastSuccessfulSync == this.lastSuccessfulSync &&
          other.highWaterMark == this.highWaterMark &&
          other.schemaVersion == this.schemaVersion &&
          other.status == this.status &&
          other.error == this.error);
}

class SyncStatesCompanion extends UpdateCompanion<SyncState> {
  final Value<String> accountId;
  final Value<String> entity;
  final Value<int?> lastSuccessfulSync;
  final Value<int?> highWaterMark;
  final Value<int> schemaVersion;
  final Value<String> status;
  final Value<String?> error;
  final Value<int> rowid;
  const SyncStatesCompanion({
    this.accountId = const Value.absent(),
    this.entity = const Value.absent(),
    this.lastSuccessfulSync = const Value.absent(),
    this.highWaterMark = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.status = const Value.absent(),
    this.error = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStatesCompanion.insert({
    required String accountId,
    required String entity,
    this.lastSuccessfulSync = const Value.absent(),
    this.highWaterMark = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.status = const Value.absent(),
    this.error = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       entity = Value(entity);
  static Insertable<SyncState> custom({
    Expression<String>? accountId,
    Expression<String>? entity,
    Expression<int>? lastSuccessfulSync,
    Expression<int>? highWaterMark,
    Expression<int>? schemaVersion,
    Expression<String>? status,
    Expression<String>? error,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (entity != null) 'entity': entity,
      if (lastSuccessfulSync != null)
        'last_successful_sync': lastSuccessfulSync,
      if (highWaterMark != null) 'high_water_mark': highWaterMark,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (status != null) 'status': status,
      if (error != null) 'error': error,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStatesCompanion copyWith({
    Value<String>? accountId,
    Value<String>? entity,
    Value<int?>? lastSuccessfulSync,
    Value<int?>? highWaterMark,
    Value<int>? schemaVersion,
    Value<String>? status,
    Value<String?>? error,
    Value<int>? rowid,
  }) {
    return SyncStatesCompanion(
      accountId: accountId ?? this.accountId,
      entity: entity ?? this.entity,
      lastSuccessfulSync: lastSuccessfulSync ?? this.lastSuccessfulSync,
      highWaterMark: highWaterMark ?? this.highWaterMark,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      status: status ?? this.status,
      error: error ?? this.error,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (lastSuccessfulSync.present) {
      map['last_successful_sync'] = Variable<int>(lastSuccessfulSync.value);
    }
    if (highWaterMark.present) {
      map['high_water_mark'] = Variable<int>(highWaterMark.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStatesCompanion(')
          ..write('accountId: $accountId, ')
          ..write('entity: $entity, ')
          ..write('lastSuccessfulSync: $lastSuccessfulSync, ')
          ..write('highWaterMark: $highWaterMark, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('status: $status, ')
          ..write('error: $error, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CacheDatabase extends GeneratedDatabase {
  _$CacheDatabase(QueryExecutor e) : super(e);
  $CacheDatabaseManager get managers => $CacheDatabaseManager(this);
  late final $CachedPatientsTable cachedPatients = $CachedPatientsTable(this);
  late final $CachedStaysTable cachedStays = $CachedStaysTable(this);
  late final $CachedRoomsTable cachedRooms = $CachedRoomsTable(this);
  late final $CachedAttendanceTable cachedAttendance = $CachedAttendanceTable(
    this,
  );
  late final $CachedPaymentsTable cachedPayments = $CachedPaymentsTable(this);
  late final $CachedProfilesTable cachedProfiles = $CachedProfilesTable(this);
  late final $CachedSettingsTable cachedSettings = $CachedSettingsTable(this);
  late final $CachedPhotoMetadataTable cachedPhotoMetadata =
      $CachedPhotoMetadataTable(this);
  late final $SyncStatesTable syncStates = $SyncStatesTable(this);
  late final Index patientsStatusIdx = Index(
    'patients_status_idx',
    'CREATE INDEX patients_status_idx ON cached_patients (account_id, status)',
  );
  late final Index patientsRegistrationIdx = Index(
    'patients_registration_idx',
    'CREATE INDEX patients_registration_idx ON cached_patients (account_id, registration_number)',
  );
  late final Index patientsNameIdx = Index(
    'patients_name_idx',
    'CREATE INDEX patients_name_idx ON cached_patients (account_id, normalized_name)',
  );
  late final Index patientsUpdatedIdx = Index(
    'patients_updated_idx',
    'CREATE INDEX patients_updated_idx ON cached_patients (account_id, updated_at)',
  );
  late final Index staysPatientIdx = Index(
    'stays_patient_idx',
    'CREATE INDEX stays_patient_idx ON cached_stays (account_id, patient_id)',
  );
  late final Index staysRoomIdx = Index(
    'stays_room_idx',
    'CREATE INDEX stays_room_idx ON cached_stays (account_id, room_id)',
  );
  late final Index staysStatusIdx = Index(
    'stays_status_idx',
    'CREATE INDEX stays_status_idx ON cached_stays (account_id, status)',
  );
  late final Index staysDischargeIdx = Index(
    'stays_discharge_idx',
    'CREATE INDEX stays_discharge_idx ON cached_stays (account_id, expected_discharge_date)',
  );
  late final Index staysUpdatedIdx = Index(
    'stays_updated_idx',
    'CREATE INDEX stays_updated_idx ON cached_stays (account_id, updated_at)',
  );
  late final Index roomsStatusIdx = Index(
    'rooms_status_idx',
    'CREATE INDEX rooms_status_idx ON cached_rooms (account_id, status)',
  );
  late final Index roomsUpdatedIdx = Index(
    'rooms_updated_idx',
    'CREATE INDEX rooms_updated_idx ON cached_rooms (account_id, updated_at)',
  );
  late final Index attendanceDateIdx = Index(
    'attendance_date_idx',
    'CREATE INDEX attendance_date_idx ON cached_attendance (account_id, kind, date)',
  );
  late final Index attendancePatientIdx = Index(
    'attendance_patient_idx',
    'CREATE INDEX attendance_patient_idx ON cached_attendance (account_id, patient_id)',
  );
  late final Index paymentsPatientIdx = Index(
    'payments_patient_idx',
    'CREATE INDEX payments_patient_idx ON cached_payments (account_id, patient_id)',
  );
  late final Index paymentsDateIdx = Index(
    'payments_date_idx',
    'CREATE INDEX payments_date_idx ON cached_payments (account_id, date)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedPatients,
    cachedStays,
    cachedRooms,
    cachedAttendance,
    cachedPayments,
    cachedProfiles,
    cachedSettings,
    cachedPhotoMetadata,
    syncStates,
    patientsStatusIdx,
    patientsRegistrationIdx,
    patientsNameIdx,
    patientsUpdatedIdx,
    staysPatientIdx,
    staysRoomIdx,
    staysStatusIdx,
    staysDischargeIdx,
    staysUpdatedIdx,
    roomsStatusIdx,
    roomsUpdatedIdx,
    attendanceDateIdx,
    attendancePatientIdx,
    paymentsPatientIdx,
    paymentsDateIdx,
  ];
}

typedef $$CachedPatientsTableCreateCompanionBuilder =
    CachedPatientsCompanion Function({
      required String accountId,
      required String id,
      Value<String?> status,
      Value<String?> registrationNumber,
      Value<String?> normalizedName,
      Value<int> updatedAt,
      required String payload,
      Value<int> rowid,
    });
typedef $$CachedPatientsTableUpdateCompanionBuilder =
    CachedPatientsCompanion Function({
      Value<String> accountId,
      Value<String> id,
      Value<String?> status,
      Value<String?> registrationNumber,
      Value<String?> normalizedName,
      Value<int> updatedAt,
      Value<String> payload,
      Value<int> rowid,
    });

class $$CachedPatientsTableFilterComposer
    extends Composer<_$CacheDatabase, $CachedPatientsTable> {
  $$CachedPatientsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get registrationNumber => $composableBuilder(
    column: $table.registrationNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedPatientsTableOrderingComposer
    extends Composer<_$CacheDatabase, $CachedPatientsTable> {
  $$CachedPatientsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get registrationNumber => $composableBuilder(
    column: $table.registrationNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedPatientsTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CachedPatientsTable> {
  $$CachedPatientsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get registrationNumber => $composableBuilder(
    column: $table.registrationNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$CachedPatientsTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CachedPatientsTable,
          CachedPatient,
          $$CachedPatientsTableFilterComposer,
          $$CachedPatientsTableOrderingComposer,
          $$CachedPatientsTableAnnotationComposer,
          $$CachedPatientsTableCreateCompanionBuilder,
          $$CachedPatientsTableUpdateCompanionBuilder,
          (
            CachedPatient,
            BaseReferences<
              _$CacheDatabase,
              $CachedPatientsTable,
              CachedPatient
            >,
          ),
          CachedPatient,
          PrefetchHooks Function()
        > {
  $$CachedPatientsTableTableManager(
    _$CacheDatabase db,
    $CachedPatientsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedPatientsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedPatientsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedPatientsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String?> status = const Value.absent(),
                Value<String?> registrationNumber = const Value.absent(),
                Value<String?> normalizedName = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedPatientsCompanion(
                accountId: accountId,
                id: id,
                status: status,
                registrationNumber: registrationNumber,
                normalizedName: normalizedName,
                updatedAt: updatedAt,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String id,
                Value<String?> status = const Value.absent(),
                Value<String?> registrationNumber = const Value.absent(),
                Value<String?> normalizedName = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => CachedPatientsCompanion.insert(
                accountId: accountId,
                id: id,
                status: status,
                registrationNumber: registrationNumber,
                normalizedName: normalizedName,
                updatedAt: updatedAt,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedPatientsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CachedPatientsTable,
      CachedPatient,
      $$CachedPatientsTableFilterComposer,
      $$CachedPatientsTableOrderingComposer,
      $$CachedPatientsTableAnnotationComposer,
      $$CachedPatientsTableCreateCompanionBuilder,
      $$CachedPatientsTableUpdateCompanionBuilder,
      (
        CachedPatient,
        BaseReferences<_$CacheDatabase, $CachedPatientsTable, CachedPatient>,
      ),
      CachedPatient,
      PrefetchHooks Function()
    >;
typedef $$CachedStaysTableCreateCompanionBuilder =
    CachedStaysCompanion Function({
      required String accountId,
      required String id,
      Value<String?> patientId,
      Value<String?> roomId,
      Value<String?> status,
      Value<int?> expectedDischargeDate,
      Value<int> updatedAt,
      required String payload,
      Value<int> rowid,
    });
typedef $$CachedStaysTableUpdateCompanionBuilder =
    CachedStaysCompanion Function({
      Value<String> accountId,
      Value<String> id,
      Value<String?> patientId,
      Value<String?> roomId,
      Value<String?> status,
      Value<int?> expectedDischargeDate,
      Value<int> updatedAt,
      Value<String> payload,
      Value<int> rowid,
    });

class $$CachedStaysTableFilterComposer
    extends Composer<_$CacheDatabase, $CachedStaysTable> {
  $$CachedStaysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get patientId => $composableBuilder(
    column: $table.patientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expectedDischargeDate => $composableBuilder(
    column: $table.expectedDischargeDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedStaysTableOrderingComposer
    extends Composer<_$CacheDatabase, $CachedStaysTable> {
  $$CachedStaysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get patientId => $composableBuilder(
    column: $table.patientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expectedDischargeDate => $composableBuilder(
    column: $table.expectedDischargeDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedStaysTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CachedStaysTable> {
  $$CachedStaysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get patientId =>
      $composableBuilder(column: $table.patientId, builder: (column) => column);

  GeneratedColumn<String> get roomId =>
      $composableBuilder(column: $table.roomId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get expectedDischargeDate => $composableBuilder(
    column: $table.expectedDischargeDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$CachedStaysTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CachedStaysTable,
          CachedStay,
          $$CachedStaysTableFilterComposer,
          $$CachedStaysTableOrderingComposer,
          $$CachedStaysTableAnnotationComposer,
          $$CachedStaysTableCreateCompanionBuilder,
          $$CachedStaysTableUpdateCompanionBuilder,
          (
            CachedStay,
            BaseReferences<_$CacheDatabase, $CachedStaysTable, CachedStay>,
          ),
          CachedStay,
          PrefetchHooks Function()
        > {
  $$CachedStaysTableTableManager(_$CacheDatabase db, $CachedStaysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedStaysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedStaysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedStaysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String?> patientId = const Value.absent(),
                Value<String?> roomId = const Value.absent(),
                Value<String?> status = const Value.absent(),
                Value<int?> expectedDischargeDate = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedStaysCompanion(
                accountId: accountId,
                id: id,
                patientId: patientId,
                roomId: roomId,
                status: status,
                expectedDischargeDate: expectedDischargeDate,
                updatedAt: updatedAt,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String id,
                Value<String?> patientId = const Value.absent(),
                Value<String?> roomId = const Value.absent(),
                Value<String?> status = const Value.absent(),
                Value<int?> expectedDischargeDate = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => CachedStaysCompanion.insert(
                accountId: accountId,
                id: id,
                patientId: patientId,
                roomId: roomId,
                status: status,
                expectedDischargeDate: expectedDischargeDate,
                updatedAt: updatedAt,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedStaysTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CachedStaysTable,
      CachedStay,
      $$CachedStaysTableFilterComposer,
      $$CachedStaysTableOrderingComposer,
      $$CachedStaysTableAnnotationComposer,
      $$CachedStaysTableCreateCompanionBuilder,
      $$CachedStaysTableUpdateCompanionBuilder,
      (
        CachedStay,
        BaseReferences<_$CacheDatabase, $CachedStaysTable, CachedStay>,
      ),
      CachedStay,
      PrefetchHooks Function()
    >;
typedef $$CachedRoomsTableCreateCompanionBuilder =
    CachedRoomsCompanion Function({
      required String accountId,
      required String id,
      Value<String?> status,
      Value<int?> floor,
      Value<String?> roomType,
      Value<int> updatedAt,
      required String payload,
      Value<int> rowid,
    });
typedef $$CachedRoomsTableUpdateCompanionBuilder =
    CachedRoomsCompanion Function({
      Value<String> accountId,
      Value<String> id,
      Value<String?> status,
      Value<int?> floor,
      Value<String?> roomType,
      Value<int> updatedAt,
      Value<String> payload,
      Value<int> rowid,
    });

class $$CachedRoomsTableFilterComposer
    extends Composer<_$CacheDatabase, $CachedRoomsTable> {
  $$CachedRoomsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get floor => $composableBuilder(
    column: $table.floor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roomType => $composableBuilder(
    column: $table.roomType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedRoomsTableOrderingComposer
    extends Composer<_$CacheDatabase, $CachedRoomsTable> {
  $$CachedRoomsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get floor => $composableBuilder(
    column: $table.floor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roomType => $composableBuilder(
    column: $table.roomType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedRoomsTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CachedRoomsTable> {
  $$CachedRoomsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get floor =>
      $composableBuilder(column: $table.floor, builder: (column) => column);

  GeneratedColumn<String> get roomType =>
      $composableBuilder(column: $table.roomType, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$CachedRoomsTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CachedRoomsTable,
          CachedRoom,
          $$CachedRoomsTableFilterComposer,
          $$CachedRoomsTableOrderingComposer,
          $$CachedRoomsTableAnnotationComposer,
          $$CachedRoomsTableCreateCompanionBuilder,
          $$CachedRoomsTableUpdateCompanionBuilder,
          (
            CachedRoom,
            BaseReferences<_$CacheDatabase, $CachedRoomsTable, CachedRoom>,
          ),
          CachedRoom,
          PrefetchHooks Function()
        > {
  $$CachedRoomsTableTableManager(_$CacheDatabase db, $CachedRoomsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedRoomsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedRoomsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedRoomsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String?> status = const Value.absent(),
                Value<int?> floor = const Value.absent(),
                Value<String?> roomType = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedRoomsCompanion(
                accountId: accountId,
                id: id,
                status: status,
                floor: floor,
                roomType: roomType,
                updatedAt: updatedAt,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String id,
                Value<String?> status = const Value.absent(),
                Value<int?> floor = const Value.absent(),
                Value<String?> roomType = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => CachedRoomsCompanion.insert(
                accountId: accountId,
                id: id,
                status: status,
                floor: floor,
                roomType: roomType,
                updatedAt: updatedAt,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedRoomsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CachedRoomsTable,
      CachedRoom,
      $$CachedRoomsTableFilterComposer,
      $$CachedRoomsTableOrderingComposer,
      $$CachedRoomsTableAnnotationComposer,
      $$CachedRoomsTableCreateCompanionBuilder,
      $$CachedRoomsTableUpdateCompanionBuilder,
      (
        CachedRoom,
        BaseReferences<_$CacheDatabase, $CachedRoomsTable, CachedRoom>,
      ),
      CachedRoom,
      PrefetchHooks Function()
    >;
typedef $$CachedAttendanceTableCreateCompanionBuilder =
    CachedAttendanceCompanion Function({
      required String accountId,
      required String id,
      required String kind,
      required String date,
      Value<String?> patientId,
      Value<int> updatedAt,
      required String payload,
      Value<int> rowid,
    });
typedef $$CachedAttendanceTableUpdateCompanionBuilder =
    CachedAttendanceCompanion Function({
      Value<String> accountId,
      Value<String> id,
      Value<String> kind,
      Value<String> date,
      Value<String?> patientId,
      Value<int> updatedAt,
      Value<String> payload,
      Value<int> rowid,
    });

class $$CachedAttendanceTableFilterComposer
    extends Composer<_$CacheDatabase, $CachedAttendanceTable> {
  $$CachedAttendanceTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get patientId => $composableBuilder(
    column: $table.patientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedAttendanceTableOrderingComposer
    extends Composer<_$CacheDatabase, $CachedAttendanceTable> {
  $$CachedAttendanceTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get patientId => $composableBuilder(
    column: $table.patientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedAttendanceTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CachedAttendanceTable> {
  $$CachedAttendanceTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get patientId =>
      $composableBuilder(column: $table.patientId, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$CachedAttendanceTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CachedAttendanceTable,
          CachedAttendanceData,
          $$CachedAttendanceTableFilterComposer,
          $$CachedAttendanceTableOrderingComposer,
          $$CachedAttendanceTableAnnotationComposer,
          $$CachedAttendanceTableCreateCompanionBuilder,
          $$CachedAttendanceTableUpdateCompanionBuilder,
          (
            CachedAttendanceData,
            BaseReferences<
              _$CacheDatabase,
              $CachedAttendanceTable,
              CachedAttendanceData
            >,
          ),
          CachedAttendanceData,
          PrefetchHooks Function()
        > {
  $$CachedAttendanceTableTableManager(
    _$CacheDatabase db,
    $CachedAttendanceTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedAttendanceTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedAttendanceTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedAttendanceTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<String?> patientId = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedAttendanceCompanion(
                accountId: accountId,
                id: id,
                kind: kind,
                date: date,
                patientId: patientId,
                updatedAt: updatedAt,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String id,
                required String kind,
                required String date,
                Value<String?> patientId = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => CachedAttendanceCompanion.insert(
                accountId: accountId,
                id: id,
                kind: kind,
                date: date,
                patientId: patientId,
                updatedAt: updatedAt,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedAttendanceTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CachedAttendanceTable,
      CachedAttendanceData,
      $$CachedAttendanceTableFilterComposer,
      $$CachedAttendanceTableOrderingComposer,
      $$CachedAttendanceTableAnnotationComposer,
      $$CachedAttendanceTableCreateCompanionBuilder,
      $$CachedAttendanceTableUpdateCompanionBuilder,
      (
        CachedAttendanceData,
        BaseReferences<
          _$CacheDatabase,
          $CachedAttendanceTable,
          CachedAttendanceData
        >,
      ),
      CachedAttendanceData,
      PrefetchHooks Function()
    >;
typedef $$CachedPaymentsTableCreateCompanionBuilder =
    CachedPaymentsCompanion Function({
      required String accountId,
      required String id,
      required String collection,
      Value<String?> patientId,
      Value<int?> date,
      Value<int> updatedAt,
      required String payload,
      Value<int> rowid,
    });
typedef $$CachedPaymentsTableUpdateCompanionBuilder =
    CachedPaymentsCompanion Function({
      Value<String> accountId,
      Value<String> id,
      Value<String> collection,
      Value<String?> patientId,
      Value<int?> date,
      Value<int> updatedAt,
      Value<String> payload,
      Value<int> rowid,
    });

class $$CachedPaymentsTableFilterComposer
    extends Composer<_$CacheDatabase, $CachedPaymentsTable> {
  $$CachedPaymentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collection => $composableBuilder(
    column: $table.collection,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get patientId => $composableBuilder(
    column: $table.patientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedPaymentsTableOrderingComposer
    extends Composer<_$CacheDatabase, $CachedPaymentsTable> {
  $$CachedPaymentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collection => $composableBuilder(
    column: $table.collection,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get patientId => $composableBuilder(
    column: $table.patientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedPaymentsTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CachedPaymentsTable> {
  $$CachedPaymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get collection => $composableBuilder(
    column: $table.collection,
    builder: (column) => column,
  );

  GeneratedColumn<String> get patientId =>
      $composableBuilder(column: $table.patientId, builder: (column) => column);

  GeneratedColumn<int> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$CachedPaymentsTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CachedPaymentsTable,
          CachedPayment,
          $$CachedPaymentsTableFilterComposer,
          $$CachedPaymentsTableOrderingComposer,
          $$CachedPaymentsTableAnnotationComposer,
          $$CachedPaymentsTableCreateCompanionBuilder,
          $$CachedPaymentsTableUpdateCompanionBuilder,
          (
            CachedPayment,
            BaseReferences<
              _$CacheDatabase,
              $CachedPaymentsTable,
              CachedPayment
            >,
          ),
          CachedPayment,
          PrefetchHooks Function()
        > {
  $$CachedPaymentsTableTableManager(
    _$CacheDatabase db,
    $CachedPaymentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedPaymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedPaymentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedPaymentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> collection = const Value.absent(),
                Value<String?> patientId = const Value.absent(),
                Value<int?> date = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedPaymentsCompanion(
                accountId: accountId,
                id: id,
                collection: collection,
                patientId: patientId,
                date: date,
                updatedAt: updatedAt,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String id,
                required String collection,
                Value<String?> patientId = const Value.absent(),
                Value<int?> date = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => CachedPaymentsCompanion.insert(
                accountId: accountId,
                id: id,
                collection: collection,
                patientId: patientId,
                date: date,
                updatedAt: updatedAt,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedPaymentsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CachedPaymentsTable,
      CachedPayment,
      $$CachedPaymentsTableFilterComposer,
      $$CachedPaymentsTableOrderingComposer,
      $$CachedPaymentsTableAnnotationComposer,
      $$CachedPaymentsTableCreateCompanionBuilder,
      $$CachedPaymentsTableUpdateCompanionBuilder,
      (
        CachedPayment,
        BaseReferences<_$CacheDatabase, $CachedPaymentsTable, CachedPayment>,
      ),
      CachedPayment,
      PrefetchHooks Function()
    >;
typedef $$CachedProfilesTableCreateCompanionBuilder =
    CachedProfilesCompanion Function({
      required String accountId,
      required String id,
      Value<int> updatedAt,
      required String payload,
      Value<int> rowid,
    });
typedef $$CachedProfilesTableUpdateCompanionBuilder =
    CachedProfilesCompanion Function({
      Value<String> accountId,
      Value<String> id,
      Value<int> updatedAt,
      Value<String> payload,
      Value<int> rowid,
    });

class $$CachedProfilesTableFilterComposer
    extends Composer<_$CacheDatabase, $CachedProfilesTable> {
  $$CachedProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedProfilesTableOrderingComposer
    extends Composer<_$CacheDatabase, $CachedProfilesTable> {
  $$CachedProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedProfilesTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CachedProfilesTable> {
  $$CachedProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$CachedProfilesTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CachedProfilesTable,
          CachedProfile,
          $$CachedProfilesTableFilterComposer,
          $$CachedProfilesTableOrderingComposer,
          $$CachedProfilesTableAnnotationComposer,
          $$CachedProfilesTableCreateCompanionBuilder,
          $$CachedProfilesTableUpdateCompanionBuilder,
          (
            CachedProfile,
            BaseReferences<
              _$CacheDatabase,
              $CachedProfilesTable,
              CachedProfile
            >,
          ),
          CachedProfile,
          PrefetchHooks Function()
        > {
  $$CachedProfilesTableTableManager(
    _$CacheDatabase db,
    $CachedProfilesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedProfilesCompanion(
                accountId: accountId,
                id: id,
                updatedAt: updatedAt,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String id,
                Value<int> updatedAt = const Value.absent(),
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => CachedProfilesCompanion.insert(
                accountId: accountId,
                id: id,
                updatedAt: updatedAt,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CachedProfilesTable,
      CachedProfile,
      $$CachedProfilesTableFilterComposer,
      $$CachedProfilesTableOrderingComposer,
      $$CachedProfilesTableAnnotationComposer,
      $$CachedProfilesTableCreateCompanionBuilder,
      $$CachedProfilesTableUpdateCompanionBuilder,
      (
        CachedProfile,
        BaseReferences<_$CacheDatabase, $CachedProfilesTable, CachedProfile>,
      ),
      CachedProfile,
      PrefetchHooks Function()
    >;
typedef $$CachedSettingsTableCreateCompanionBuilder =
    CachedSettingsCompanion Function({
      required String accountId,
      required String id,
      Value<int> updatedAt,
      required String payload,
      Value<int> rowid,
    });
typedef $$CachedSettingsTableUpdateCompanionBuilder =
    CachedSettingsCompanion Function({
      Value<String> accountId,
      Value<String> id,
      Value<int> updatedAt,
      Value<String> payload,
      Value<int> rowid,
    });

class $$CachedSettingsTableFilterComposer
    extends Composer<_$CacheDatabase, $CachedSettingsTable> {
  $$CachedSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedSettingsTableOrderingComposer
    extends Composer<_$CacheDatabase, $CachedSettingsTable> {
  $$CachedSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedSettingsTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CachedSettingsTable> {
  $$CachedSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$CachedSettingsTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CachedSettingsTable,
          CachedSetting,
          $$CachedSettingsTableFilterComposer,
          $$CachedSettingsTableOrderingComposer,
          $$CachedSettingsTableAnnotationComposer,
          $$CachedSettingsTableCreateCompanionBuilder,
          $$CachedSettingsTableUpdateCompanionBuilder,
          (
            CachedSetting,
            BaseReferences<
              _$CacheDatabase,
              $CachedSettingsTable,
              CachedSetting
            >,
          ),
          CachedSetting,
          PrefetchHooks Function()
        > {
  $$CachedSettingsTableTableManager(
    _$CacheDatabase db,
    $CachedSettingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedSettingsCompanion(
                accountId: accountId,
                id: id,
                updatedAt: updatedAt,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String id,
                Value<int> updatedAt = const Value.absent(),
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => CachedSettingsCompanion.insert(
                accountId: accountId,
                id: id,
                updatedAt: updatedAt,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CachedSettingsTable,
      CachedSetting,
      $$CachedSettingsTableFilterComposer,
      $$CachedSettingsTableOrderingComposer,
      $$CachedSettingsTableAnnotationComposer,
      $$CachedSettingsTableCreateCompanionBuilder,
      $$CachedSettingsTableUpdateCompanionBuilder,
      (
        CachedSetting,
        BaseReferences<_$CacheDatabase, $CachedSettingsTable, CachedSetting>,
      ),
      CachedSetting,
      PrefetchHooks Function()
    >;
typedef $$CachedPhotoMetadataTableCreateCompanionBuilder =
    CachedPhotoMetadataCompanion Function({
      required String accountId,
      required String photoRef,
      Value<int> version,
      Value<String?> contentType,
      Value<String?> contentHash,
      Value<int> updatedAt,
      Value<int> lastAccessedAt,
      Value<int> rowid,
    });
typedef $$CachedPhotoMetadataTableUpdateCompanionBuilder =
    CachedPhotoMetadataCompanion Function({
      Value<String> accountId,
      Value<String> photoRef,
      Value<int> version,
      Value<String?> contentType,
      Value<String?> contentHash,
      Value<int> updatedAt,
      Value<int> lastAccessedAt,
      Value<int> rowid,
    });

class $$CachedPhotoMetadataTableFilterComposer
    extends Composer<_$CacheDatabase, $CachedPhotoMetadataTable> {
  $$CachedPhotoMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoRef => $composableBuilder(
    column: $table.photoRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedPhotoMetadataTableOrderingComposer
    extends Composer<_$CacheDatabase, $CachedPhotoMetadataTable> {
  $$CachedPhotoMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoRef => $composableBuilder(
    column: $table.photoRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedPhotoMetadataTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CachedPhotoMetadataTable> {
  $$CachedPhotoMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get photoRef =>
      $composableBuilder(column: $table.photoRef, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => column,
  );
}

class $$CachedPhotoMetadataTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CachedPhotoMetadataTable,
          CachedPhotoMetadataData,
          $$CachedPhotoMetadataTableFilterComposer,
          $$CachedPhotoMetadataTableOrderingComposer,
          $$CachedPhotoMetadataTableAnnotationComposer,
          $$CachedPhotoMetadataTableCreateCompanionBuilder,
          $$CachedPhotoMetadataTableUpdateCompanionBuilder,
          (
            CachedPhotoMetadataData,
            BaseReferences<
              _$CacheDatabase,
              $CachedPhotoMetadataTable,
              CachedPhotoMetadataData
            >,
          ),
          CachedPhotoMetadataData,
          PrefetchHooks Function()
        > {
  $$CachedPhotoMetadataTableTableManager(
    _$CacheDatabase db,
    $CachedPhotoMetadataTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedPhotoMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedPhotoMetadataTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedPhotoMetadataTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> photoRef = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String?> contentType = const Value.absent(),
                Value<String?> contentHash = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> lastAccessedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedPhotoMetadataCompanion(
                accountId: accountId,
                photoRef: photoRef,
                version: version,
                contentType: contentType,
                contentHash: contentHash,
                updatedAt: updatedAt,
                lastAccessedAt: lastAccessedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String photoRef,
                Value<int> version = const Value.absent(),
                Value<String?> contentType = const Value.absent(),
                Value<String?> contentHash = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> lastAccessedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedPhotoMetadataCompanion.insert(
                accountId: accountId,
                photoRef: photoRef,
                version: version,
                contentType: contentType,
                contentHash: contentHash,
                updatedAt: updatedAt,
                lastAccessedAt: lastAccessedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedPhotoMetadataTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CachedPhotoMetadataTable,
      CachedPhotoMetadataData,
      $$CachedPhotoMetadataTableFilterComposer,
      $$CachedPhotoMetadataTableOrderingComposer,
      $$CachedPhotoMetadataTableAnnotationComposer,
      $$CachedPhotoMetadataTableCreateCompanionBuilder,
      $$CachedPhotoMetadataTableUpdateCompanionBuilder,
      (
        CachedPhotoMetadataData,
        BaseReferences<
          _$CacheDatabase,
          $CachedPhotoMetadataTable,
          CachedPhotoMetadataData
        >,
      ),
      CachedPhotoMetadataData,
      PrefetchHooks Function()
    >;
typedef $$SyncStatesTableCreateCompanionBuilder =
    SyncStatesCompanion Function({
      required String accountId,
      required String entity,
      Value<int?> lastSuccessfulSync,
      Value<int?> highWaterMark,
      Value<int> schemaVersion,
      Value<String> status,
      Value<String?> error,
      Value<int> rowid,
    });
typedef $$SyncStatesTableUpdateCompanionBuilder =
    SyncStatesCompanion Function({
      Value<String> accountId,
      Value<String> entity,
      Value<int?> lastSuccessfulSync,
      Value<int?> highWaterMark,
      Value<int> schemaVersion,
      Value<String> status,
      Value<String?> error,
      Value<int> rowid,
    });

class $$SyncStatesTableFilterComposer
    extends Composer<_$CacheDatabase, $SyncStatesTable> {
  $$SyncStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSuccessfulSync => $composableBuilder(
    column: $table.lastSuccessfulSync,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get highWaterMark => $composableBuilder(
    column: $table.highWaterMark,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStatesTableOrderingComposer
    extends Composer<_$CacheDatabase, $SyncStatesTable> {
  $$SyncStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSuccessfulSync => $composableBuilder(
    column: $table.lastSuccessfulSync,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get highWaterMark => $composableBuilder(
    column: $table.highWaterMark,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStatesTableAnnotationComposer
    extends Composer<_$CacheDatabase, $SyncStatesTable> {
  $$SyncStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<int> get lastSuccessfulSync => $composableBuilder(
    column: $table.lastSuccessfulSync,
    builder: (column) => column,
  );

  GeneratedColumn<int> get highWaterMark => $composableBuilder(
    column: $table.highWaterMark,
    builder: (column) => column,
  );

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);
}

class $$SyncStatesTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $SyncStatesTable,
          SyncState,
          $$SyncStatesTableFilterComposer,
          $$SyncStatesTableOrderingComposer,
          $$SyncStatesTableAnnotationComposer,
          $$SyncStatesTableCreateCompanionBuilder,
          $$SyncStatesTableUpdateCompanionBuilder,
          (
            SyncState,
            BaseReferences<_$CacheDatabase, $SyncStatesTable, SyncState>,
          ),
          SyncState,
          PrefetchHooks Function()
        > {
  $$SyncStatesTableTableManager(_$CacheDatabase db, $SyncStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> entity = const Value.absent(),
                Value<int?> lastSuccessfulSync = const Value.absent(),
                Value<int?> highWaterMark = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStatesCompanion(
                accountId: accountId,
                entity: entity,
                lastSuccessfulSync: lastSuccessfulSync,
                highWaterMark: highWaterMark,
                schemaVersion: schemaVersion,
                status: status,
                error: error,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String entity,
                Value<int?> lastSuccessfulSync = const Value.absent(),
                Value<int?> highWaterMark = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStatesCompanion.insert(
                accountId: accountId,
                entity: entity,
                lastSuccessfulSync: lastSuccessfulSync,
                highWaterMark: highWaterMark,
                schemaVersion: schemaVersion,
                status: status,
                error: error,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $SyncStatesTable,
      SyncState,
      $$SyncStatesTableFilterComposer,
      $$SyncStatesTableOrderingComposer,
      $$SyncStatesTableAnnotationComposer,
      $$SyncStatesTableCreateCompanionBuilder,
      $$SyncStatesTableUpdateCompanionBuilder,
      (SyncState, BaseReferences<_$CacheDatabase, $SyncStatesTable, SyncState>),
      SyncState,
      PrefetchHooks Function()
    >;

class $CacheDatabaseManager {
  final _$CacheDatabase _db;
  $CacheDatabaseManager(this._db);
  $$CachedPatientsTableTableManager get cachedPatients =>
      $$CachedPatientsTableTableManager(_db, _db.cachedPatients);
  $$CachedStaysTableTableManager get cachedStays =>
      $$CachedStaysTableTableManager(_db, _db.cachedStays);
  $$CachedRoomsTableTableManager get cachedRooms =>
      $$CachedRoomsTableTableManager(_db, _db.cachedRooms);
  $$CachedAttendanceTableTableManager get cachedAttendance =>
      $$CachedAttendanceTableTableManager(_db, _db.cachedAttendance);
  $$CachedPaymentsTableTableManager get cachedPayments =>
      $$CachedPaymentsTableTableManager(_db, _db.cachedPayments);
  $$CachedProfilesTableTableManager get cachedProfiles =>
      $$CachedProfilesTableTableManager(_db, _db.cachedProfiles);
  $$CachedSettingsTableTableManager get cachedSettings =>
      $$CachedSettingsTableTableManager(_db, _db.cachedSettings);
  $$CachedPhotoMetadataTableTableManager get cachedPhotoMetadata =>
      $$CachedPhotoMetadataTableTableManager(_db, _db.cachedPhotoMetadata);
  $$SyncStatesTableTableManager get syncStates =>
      $$SyncStatesTableTableManager(_db, _db.syncStates);
}
