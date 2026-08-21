// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ServersTable extends Servers with TableInfo<$ServersTable, Server> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ServersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(22),
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastConnectedAtMeta = const VerificationMeta(
    'lastConnectedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastConnectedAt =
      GeneratedColumn<DateTime>(
        'last_connected_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
    'sync_id',
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
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _credentialTypeMeta = const VerificationMeta(
    'credentialType',
  );
  @override
  late final GeneratedColumn<String> credentialType = GeneratedColumn<String>(
    'credential_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _encryptedCredentialMeta =
      const VerificationMeta('encryptedCredential');
  @override
  late final GeneratedColumn<String> encryptedCredential =
      GeneratedColumn<String>(
        'encrypted_credential',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _credentialNonceMeta = const VerificationMeta(
    'credentialNonce',
  );
  @override
  late final GeneratedColumn<String> credentialNonce = GeneratedColumn<String>(
    'credential_nonce',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _credentialIdMeta = const VerificationMeta(
    'credentialId',
  );
  @override
  late final GeneratedColumn<int> credentialId = GeneratedColumn<int>(
    'credential_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hostKeyAlgorithmMeta = const VerificationMeta(
    'hostKeyAlgorithm',
  );
  @override
  late final GeneratedColumn<String> hostKeyAlgorithm = GeneratedColumn<String>(
    'host_key_algorithm',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hostKeyFingerprintMeta =
      const VerificationMeta('hostKeyFingerprint');
  @override
  late final GeneratedColumn<String> hostKeyFingerprint =
      GeneratedColumn<String>(
        'host_key_fingerprint',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _collectStatsMeta = const VerificationMeta(
    'collectStats',
  );
  @override
  late final GeneratedColumn<bool> collectStats = GeneratedColumn<bool>(
    'collect_stats',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("collect_stats" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _collectSystemInfoMeta = const VerificationMeta(
    'collectSystemInfo',
  );
  @override
  late final GeneratedColumn<bool> collectSystemInfo = GeneratedColumn<bool>(
    'collect_system_info',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("collect_system_info" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _proxyTypeMeta = const VerificationMeta(
    'proxyType',
  );
  @override
  late final GeneratedColumn<String> proxyType = GeneratedColumn<String>(
    'proxy_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _proxyHostMeta = const VerificationMeta(
    'proxyHost',
  );
  @override
  late final GeneratedColumn<String> proxyHost = GeneratedColumn<String>(
    'proxy_host',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _proxyPortMeta = const VerificationMeta(
    'proxyPort',
  );
  @override
  late final GeneratedColumn<int> proxyPort = GeneratedColumn<int>(
    'proxy_port',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _proxyUsernameMeta = const VerificationMeta(
    'proxyUsername',
  );
  @override
  late final GeneratedColumn<String> proxyUsername = GeneratedColumn<String>(
    'proxy_username',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _encryptedProxyPasswordMeta =
      const VerificationMeta('encryptedProxyPassword');
  @override
  late final GeneratedColumn<String> encryptedProxyPassword =
      GeneratedColumn<String>(
        'encrypted_proxy_password',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _proxyPasswordNonceMeta =
      const VerificationMeta('proxyPasswordNonce');
  @override
  late final GeneratedColumn<String> proxyPasswordNonce =
      GeneratedColumn<String>(
        'proxy_password_nonce',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _jumpHostServerIdMeta = const VerificationMeta(
    'jumpHostServerId',
  );
  @override
  late final GeneratedColumn<int> jumpHostServerId = GeneratedColumn<int>(
    'jump_host_server_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _environmentMeta = const VerificationMeta(
    'environment',
  );
  @override
  late final GeneratedColumn<String> environment = GeneratedColumn<String>(
    'environment',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _initialSnippetsMeta = const VerificationMeta(
    'initialSnippets',
  );
  @override
  late final GeneratedColumn<String> initialSnippets = GeneratedColumn<String>(
    'initial_snippets',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
    'tags',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _connectionTypeMeta = const VerificationMeta(
    'connectionType',
  );
  @override
  late final GeneratedColumn<String> connectionType = GeneratedColumn<String>(
    'connection_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('ssh'),
  );
  static const VerificationMeta _serialConfigMeta = const VerificationMeta(
    'serialConfig',
  );
  @override
  late final GeneratedColumn<String> serialConfig = GeneratedColumn<String>(
    'serial_config',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maidCafeDaemonUrlMeta = const VerificationMeta(
    'maidCafeDaemonUrl',
  );
  @override
  late final GeneratedColumn<String> maidCafeDaemonUrl =
      GeneratedColumn<String>(
        'maid_cafe_daemon_url',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _encryptedMaidCafeWebhookSecretMeta =
      const VerificationMeta('encryptedMaidCafeWebhookSecret');
  @override
  late final GeneratedColumn<String> encryptedMaidCafeWebhookSecret =
      GeneratedColumn<String>(
        'encrypted_maid_cafe_webhook_secret',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _maidCafeWebhookSecretNonceMeta =
      const VerificationMeta('maidCafeWebhookSecretNonce');
  @override
  late final GeneratedColumn<String> maidCafeWebhookSecretNonce =
      GeneratedColumn<String>(
        'maid_cafe_webhook_secret_nonce',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _encryptedMaidCafeMetricsSecretMeta =
      const VerificationMeta('encryptedMaidCafeMetricsSecret');
  @override
  late final GeneratedColumn<String> encryptedMaidCafeMetricsSecret =
      GeneratedColumn<String>(
        'encrypted_maid_cafe_metrics_secret',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _maidCafeMetricsSecretNonceMeta =
      const VerificationMeta('maidCafeMetricsSecretNonce');
  @override
  late final GeneratedColumn<String> maidCafeMetricsSecretNonce =
      GeneratedColumn<String>(
        'maid_cafe_metrics_secret_nonce',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileManagementInitialPathMeta =
      const VerificationMeta('fileManagementInitialPath');
  @override
  late final GeneratedColumn<String> fileManagementInitialPath =
      GeneratedColumn<String>(
        'file_management_initial_path',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _fileManagementFavoritesMeta =
      const VerificationMeta('fileManagementFavorites');
  @override
  late final GeneratedColumn<String> fileManagementFavorites =
      GeneratedColumn<String>(
        'file_management_favorites',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    host,
    port,
    username,
    lastConnectedAt,
    syncId,
    createdAt,
    updatedAt,
    deletedAt,
    credentialType,
    encryptedCredential,
    credentialNonce,
    credentialId,
    hostKeyAlgorithm,
    hostKeyFingerprint,
    collectStats,
    collectSystemInfo,
    proxyType,
    proxyHost,
    proxyPort,
    proxyUsername,
    encryptedProxyPassword,
    proxyPasswordNonce,
    jumpHostServerId,
    environment,
    initialSnippets,
    tags,
    connectionType,
    serialConfig,
    maidCafeDaemonUrl,
    encryptedMaidCafeWebhookSecret,
    maidCafeWebhookSecretNonce,
    encryptedMaidCafeMetricsSecret,
    maidCafeMetricsSecretNonce,
    sortOrder,
    fileManagementInitialPath,
    fileManagementFavorites,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'servers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Server> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('last_connected_at')) {
      context.handle(
        _lastConnectedAtMeta,
        lastConnectedAt.isAcceptableOrUnknown(
          data['last_connected_at']!,
          _lastConnectedAtMeta,
        ),
      );
    }
    if (data.containsKey('sync_id')) {
      context.handle(
        _syncIdMeta,
        syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('credential_type')) {
      context.handle(
        _credentialTypeMeta,
        credentialType.isAcceptableOrUnknown(
          data['credential_type']!,
          _credentialTypeMeta,
        ),
      );
    }
    if (data.containsKey('encrypted_credential')) {
      context.handle(
        _encryptedCredentialMeta,
        encryptedCredential.isAcceptableOrUnknown(
          data['encrypted_credential']!,
          _encryptedCredentialMeta,
        ),
      );
    }
    if (data.containsKey('credential_nonce')) {
      context.handle(
        _credentialNonceMeta,
        credentialNonce.isAcceptableOrUnknown(
          data['credential_nonce']!,
          _credentialNonceMeta,
        ),
      );
    }
    if (data.containsKey('credential_id')) {
      context.handle(
        _credentialIdMeta,
        credentialId.isAcceptableOrUnknown(
          data['credential_id']!,
          _credentialIdMeta,
        ),
      );
    }
    if (data.containsKey('host_key_algorithm')) {
      context.handle(
        _hostKeyAlgorithmMeta,
        hostKeyAlgorithm.isAcceptableOrUnknown(
          data['host_key_algorithm']!,
          _hostKeyAlgorithmMeta,
        ),
      );
    }
    if (data.containsKey('host_key_fingerprint')) {
      context.handle(
        _hostKeyFingerprintMeta,
        hostKeyFingerprint.isAcceptableOrUnknown(
          data['host_key_fingerprint']!,
          _hostKeyFingerprintMeta,
        ),
      );
    }
    if (data.containsKey('collect_stats')) {
      context.handle(
        _collectStatsMeta,
        collectStats.isAcceptableOrUnknown(
          data['collect_stats']!,
          _collectStatsMeta,
        ),
      );
    }
    if (data.containsKey('collect_system_info')) {
      context.handle(
        _collectSystemInfoMeta,
        collectSystemInfo.isAcceptableOrUnknown(
          data['collect_system_info']!,
          _collectSystemInfoMeta,
        ),
      );
    }
    if (data.containsKey('proxy_type')) {
      context.handle(
        _proxyTypeMeta,
        proxyType.isAcceptableOrUnknown(data['proxy_type']!, _proxyTypeMeta),
      );
    }
    if (data.containsKey('proxy_host')) {
      context.handle(
        _proxyHostMeta,
        proxyHost.isAcceptableOrUnknown(data['proxy_host']!, _proxyHostMeta),
      );
    }
    if (data.containsKey('proxy_port')) {
      context.handle(
        _proxyPortMeta,
        proxyPort.isAcceptableOrUnknown(data['proxy_port']!, _proxyPortMeta),
      );
    }
    if (data.containsKey('proxy_username')) {
      context.handle(
        _proxyUsernameMeta,
        proxyUsername.isAcceptableOrUnknown(
          data['proxy_username']!,
          _proxyUsernameMeta,
        ),
      );
    }
    if (data.containsKey('encrypted_proxy_password')) {
      context.handle(
        _encryptedProxyPasswordMeta,
        encryptedProxyPassword.isAcceptableOrUnknown(
          data['encrypted_proxy_password']!,
          _encryptedProxyPasswordMeta,
        ),
      );
    }
    if (data.containsKey('proxy_password_nonce')) {
      context.handle(
        _proxyPasswordNonceMeta,
        proxyPasswordNonce.isAcceptableOrUnknown(
          data['proxy_password_nonce']!,
          _proxyPasswordNonceMeta,
        ),
      );
    }
    if (data.containsKey('jump_host_server_id')) {
      context.handle(
        _jumpHostServerIdMeta,
        jumpHostServerId.isAcceptableOrUnknown(
          data['jump_host_server_id']!,
          _jumpHostServerIdMeta,
        ),
      );
    }
    if (data.containsKey('environment')) {
      context.handle(
        _environmentMeta,
        environment.isAcceptableOrUnknown(
          data['environment']!,
          _environmentMeta,
        ),
      );
    }
    if (data.containsKey('initial_snippets')) {
      context.handle(
        _initialSnippetsMeta,
        initialSnippets.isAcceptableOrUnknown(
          data['initial_snippets']!,
          _initialSnippetsMeta,
        ),
      );
    }
    if (data.containsKey('tags')) {
      context.handle(
        _tagsMeta,
        tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta),
      );
    }
    if (data.containsKey('connection_type')) {
      context.handle(
        _connectionTypeMeta,
        connectionType.isAcceptableOrUnknown(
          data['connection_type']!,
          _connectionTypeMeta,
        ),
      );
    }
    if (data.containsKey('serial_config')) {
      context.handle(
        _serialConfigMeta,
        serialConfig.isAcceptableOrUnknown(
          data['serial_config']!,
          _serialConfigMeta,
        ),
      );
    }
    if (data.containsKey('maid_cafe_daemon_url')) {
      context.handle(
        _maidCafeDaemonUrlMeta,
        maidCafeDaemonUrl.isAcceptableOrUnknown(
          data['maid_cafe_daemon_url']!,
          _maidCafeDaemonUrlMeta,
        ),
      );
    }
    if (data.containsKey('encrypted_maid_cafe_webhook_secret')) {
      context.handle(
        _encryptedMaidCafeWebhookSecretMeta,
        encryptedMaidCafeWebhookSecret.isAcceptableOrUnknown(
          data['encrypted_maid_cafe_webhook_secret']!,
          _encryptedMaidCafeWebhookSecretMeta,
        ),
      );
    }
    if (data.containsKey('maid_cafe_webhook_secret_nonce')) {
      context.handle(
        _maidCafeWebhookSecretNonceMeta,
        maidCafeWebhookSecretNonce.isAcceptableOrUnknown(
          data['maid_cafe_webhook_secret_nonce']!,
          _maidCafeWebhookSecretNonceMeta,
        ),
      );
    }
    if (data.containsKey('encrypted_maid_cafe_metrics_secret')) {
      context.handle(
        _encryptedMaidCafeMetricsSecretMeta,
        encryptedMaidCafeMetricsSecret.isAcceptableOrUnknown(
          data['encrypted_maid_cafe_metrics_secret']!,
          _encryptedMaidCafeMetricsSecretMeta,
        ),
      );
    }
    if (data.containsKey('maid_cafe_metrics_secret_nonce')) {
      context.handle(
        _maidCafeMetricsSecretNonceMeta,
        maidCafeMetricsSecretNonce.isAcceptableOrUnknown(
          data['maid_cafe_metrics_secret_nonce']!,
          _maidCafeMetricsSecretNonceMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('file_management_initial_path')) {
      context.handle(
        _fileManagementInitialPathMeta,
        fileManagementInitialPath.isAcceptableOrUnknown(
          data['file_management_initial_path']!,
          _fileManagementInitialPathMeta,
        ),
      );
    }
    if (data.containsKey('file_management_favorites')) {
      context.handle(
        _fileManagementFavoritesMeta,
        fileManagementFavorites.isAcceptableOrUnknown(
          data['file_management_favorites']!,
          _fileManagementFavoritesMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Server map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Server(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      lastConnectedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_connected_at'],
      ),
      syncId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      credentialType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}credential_type'],
      ),
      encryptedCredential: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_credential'],
      ),
      credentialNonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}credential_nonce'],
      ),
      credentialId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}credential_id'],
      ),
      hostKeyAlgorithm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_key_algorithm'],
      ),
      hostKeyFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_key_fingerprint'],
      ),
      collectStats: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}collect_stats'],
      )!,
      collectSystemInfo: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}collect_system_info'],
      )!,
      proxyType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}proxy_type'],
      ),
      proxyHost: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}proxy_host'],
      ),
      proxyPort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}proxy_port'],
      ),
      proxyUsername: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}proxy_username'],
      ),
      encryptedProxyPassword: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_proxy_password'],
      ),
      proxyPasswordNonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}proxy_password_nonce'],
      ),
      jumpHostServerId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}jump_host_server_id'],
      ),
      environment: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}environment'],
      ),
      initialSnippets: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}initial_snippets'],
      ),
      tags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags'],
      ),
      connectionType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}connection_type'],
      )!,
      serialConfig: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}serial_config'],
      ),
      maidCafeDaemonUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}maid_cafe_daemon_url'],
      ),
      encryptedMaidCafeWebhookSecret: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_maid_cafe_webhook_secret'],
      ),
      maidCafeWebhookSecretNonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}maid_cafe_webhook_secret_nonce'],
      ),
      encryptedMaidCafeMetricsSecret: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_maid_cafe_metrics_secret'],
      ),
      maidCafeMetricsSecretNonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}maid_cafe_metrics_secret_nonce'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      ),
      fileManagementInitialPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_management_initial_path'],
      ),
      fileManagementFavorites: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_management_favorites'],
      ),
    );
  }

  @override
  $ServersTable createAlias(String alias) {
    return $ServersTable(attachedDatabase, alias);
  }
}

class Server extends DataClass implements Insertable<Server> {
  final int id;
  final String name;
  final String host;
  final int port;
  final String username;
  final DateTime? lastConnectedAt;
  final String? syncId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final String? credentialType;
  final String? encryptedCredential;
  final String? credentialNonce;
  final int? credentialId;
  final String? hostKeyAlgorithm;
  final String? hostKeyFingerprint;
  final bool collectStats;
  final bool collectSystemInfo;
  final String? proxyType;
  final String? proxyHost;
  final int? proxyPort;
  final String? proxyUsername;
  final String? encryptedProxyPassword;
  final String? proxyPasswordNonce;
  final int? jumpHostServerId;
  final String? environment;
  final String? initialSnippets;
  final String? tags;
  final String connectionType;
  final String? serialConfig;
  final String? maidCafeDaemonUrl;
  final String? encryptedMaidCafeWebhookSecret;
  final String? maidCafeWebhookSecretNonce;
  final String? encryptedMaidCafeMetricsSecret;
  final String? maidCafeMetricsSecretNonce;
  final int? sortOrder;
  final String? fileManagementInitialPath;
  final String? fileManagementFavorites;
  const Server({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    this.lastConnectedAt,
    this.syncId,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.credentialType,
    this.encryptedCredential,
    this.credentialNonce,
    this.credentialId,
    this.hostKeyAlgorithm,
    this.hostKeyFingerprint,
    required this.collectStats,
    required this.collectSystemInfo,
    this.proxyType,
    this.proxyHost,
    this.proxyPort,
    this.proxyUsername,
    this.encryptedProxyPassword,
    this.proxyPasswordNonce,
    this.jumpHostServerId,
    this.environment,
    this.initialSnippets,
    this.tags,
    required this.connectionType,
    this.serialConfig,
    this.maidCafeDaemonUrl,
    this.encryptedMaidCafeWebhookSecret,
    this.maidCafeWebhookSecretNonce,
    this.encryptedMaidCafeMetricsSecret,
    this.maidCafeMetricsSecretNonce,
    this.sortOrder,
    this.fileManagementInitialPath,
    this.fileManagementFavorites,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['host'] = Variable<String>(host);
    map['port'] = Variable<int>(port);
    map['username'] = Variable<String>(username);
    if (!nullToAbsent || lastConnectedAt != null) {
      map['last_connected_at'] = Variable<DateTime>(lastConnectedAt);
    }
    if (!nullToAbsent || syncId != null) {
      map['sync_id'] = Variable<String>(syncId);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    if (!nullToAbsent || credentialType != null) {
      map['credential_type'] = Variable<String>(credentialType);
    }
    if (!nullToAbsent || encryptedCredential != null) {
      map['encrypted_credential'] = Variable<String>(encryptedCredential);
    }
    if (!nullToAbsent || credentialNonce != null) {
      map['credential_nonce'] = Variable<String>(credentialNonce);
    }
    if (!nullToAbsent || credentialId != null) {
      map['credential_id'] = Variable<int>(credentialId);
    }
    if (!nullToAbsent || hostKeyAlgorithm != null) {
      map['host_key_algorithm'] = Variable<String>(hostKeyAlgorithm);
    }
    if (!nullToAbsent || hostKeyFingerprint != null) {
      map['host_key_fingerprint'] = Variable<String>(hostKeyFingerprint);
    }
    map['collect_stats'] = Variable<bool>(collectStats);
    map['collect_system_info'] = Variable<bool>(collectSystemInfo);
    if (!nullToAbsent || proxyType != null) {
      map['proxy_type'] = Variable<String>(proxyType);
    }
    if (!nullToAbsent || proxyHost != null) {
      map['proxy_host'] = Variable<String>(proxyHost);
    }
    if (!nullToAbsent || proxyPort != null) {
      map['proxy_port'] = Variable<int>(proxyPort);
    }
    if (!nullToAbsent || proxyUsername != null) {
      map['proxy_username'] = Variable<String>(proxyUsername);
    }
    if (!nullToAbsent || encryptedProxyPassword != null) {
      map['encrypted_proxy_password'] = Variable<String>(
        encryptedProxyPassword,
      );
    }
    if (!nullToAbsent || proxyPasswordNonce != null) {
      map['proxy_password_nonce'] = Variable<String>(proxyPasswordNonce);
    }
    if (!nullToAbsent || jumpHostServerId != null) {
      map['jump_host_server_id'] = Variable<int>(jumpHostServerId);
    }
    if (!nullToAbsent || environment != null) {
      map['environment'] = Variable<String>(environment);
    }
    if (!nullToAbsent || initialSnippets != null) {
      map['initial_snippets'] = Variable<String>(initialSnippets);
    }
    if (!nullToAbsent || tags != null) {
      map['tags'] = Variable<String>(tags);
    }
    map['connection_type'] = Variable<String>(connectionType);
    if (!nullToAbsent || serialConfig != null) {
      map['serial_config'] = Variable<String>(serialConfig);
    }
    if (!nullToAbsent || maidCafeDaemonUrl != null) {
      map['maid_cafe_daemon_url'] = Variable<String>(maidCafeDaemonUrl);
    }
    if (!nullToAbsent || encryptedMaidCafeWebhookSecret != null) {
      map['encrypted_maid_cafe_webhook_secret'] = Variable<String>(
        encryptedMaidCafeWebhookSecret,
      );
    }
    if (!nullToAbsent || maidCafeWebhookSecretNonce != null) {
      map['maid_cafe_webhook_secret_nonce'] = Variable<String>(
        maidCafeWebhookSecretNonce,
      );
    }
    if (!nullToAbsent || encryptedMaidCafeMetricsSecret != null) {
      map['encrypted_maid_cafe_metrics_secret'] = Variable<String>(
        encryptedMaidCafeMetricsSecret,
      );
    }
    if (!nullToAbsent || maidCafeMetricsSecretNonce != null) {
      map['maid_cafe_metrics_secret_nonce'] = Variable<String>(
        maidCafeMetricsSecretNonce,
      );
    }
    if (!nullToAbsent || sortOrder != null) {
      map['sort_order'] = Variable<int>(sortOrder);
    }
    if (!nullToAbsent || fileManagementInitialPath != null) {
      map['file_management_initial_path'] = Variable<String>(
        fileManagementInitialPath,
      );
    }
    if (!nullToAbsent || fileManagementFavorites != null) {
      map['file_management_favorites'] = Variable<String>(
        fileManagementFavorites,
      );
    }
    return map;
  }

  ServersCompanion toCompanion(bool nullToAbsent) {
    return ServersCompanion(
      id: Value(id),
      name: Value(name),
      host: Value(host),
      port: Value(port),
      username: Value(username),
      lastConnectedAt: lastConnectedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastConnectedAt),
      syncId: syncId == null && nullToAbsent
          ? const Value.absent()
          : Value(syncId),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      credentialType: credentialType == null && nullToAbsent
          ? const Value.absent()
          : Value(credentialType),
      encryptedCredential: encryptedCredential == null && nullToAbsent
          ? const Value.absent()
          : Value(encryptedCredential),
      credentialNonce: credentialNonce == null && nullToAbsent
          ? const Value.absent()
          : Value(credentialNonce),
      credentialId: credentialId == null && nullToAbsent
          ? const Value.absent()
          : Value(credentialId),
      hostKeyAlgorithm: hostKeyAlgorithm == null && nullToAbsent
          ? const Value.absent()
          : Value(hostKeyAlgorithm),
      hostKeyFingerprint: hostKeyFingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(hostKeyFingerprint),
      collectStats: Value(collectStats),
      collectSystemInfo: Value(collectSystemInfo),
      proxyType: proxyType == null && nullToAbsent
          ? const Value.absent()
          : Value(proxyType),
      proxyHost: proxyHost == null && nullToAbsent
          ? const Value.absent()
          : Value(proxyHost),
      proxyPort: proxyPort == null && nullToAbsent
          ? const Value.absent()
          : Value(proxyPort),
      proxyUsername: proxyUsername == null && nullToAbsent
          ? const Value.absent()
          : Value(proxyUsername),
      encryptedProxyPassword: encryptedProxyPassword == null && nullToAbsent
          ? const Value.absent()
          : Value(encryptedProxyPassword),
      proxyPasswordNonce: proxyPasswordNonce == null && nullToAbsent
          ? const Value.absent()
          : Value(proxyPasswordNonce),
      jumpHostServerId: jumpHostServerId == null && nullToAbsent
          ? const Value.absent()
          : Value(jumpHostServerId),
      environment: environment == null && nullToAbsent
          ? const Value.absent()
          : Value(environment),
      initialSnippets: initialSnippets == null && nullToAbsent
          ? const Value.absent()
          : Value(initialSnippets),
      tags: tags == null && nullToAbsent ? const Value.absent() : Value(tags),
      connectionType: Value(connectionType),
      serialConfig: serialConfig == null && nullToAbsent
          ? const Value.absent()
          : Value(serialConfig),
      maidCafeDaemonUrl: maidCafeDaemonUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(maidCafeDaemonUrl),
      encryptedMaidCafeWebhookSecret:
          encryptedMaidCafeWebhookSecret == null && nullToAbsent
          ? const Value.absent()
          : Value(encryptedMaidCafeWebhookSecret),
      maidCafeWebhookSecretNonce:
          maidCafeWebhookSecretNonce == null && nullToAbsent
          ? const Value.absent()
          : Value(maidCafeWebhookSecretNonce),
      encryptedMaidCafeMetricsSecret:
          encryptedMaidCafeMetricsSecret == null && nullToAbsent
          ? const Value.absent()
          : Value(encryptedMaidCafeMetricsSecret),
      maidCafeMetricsSecretNonce:
          maidCafeMetricsSecretNonce == null && nullToAbsent
          ? const Value.absent()
          : Value(maidCafeMetricsSecretNonce),
      sortOrder: sortOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(sortOrder),
      fileManagementInitialPath:
          fileManagementInitialPath == null && nullToAbsent
          ? const Value.absent()
          : Value(fileManagementInitialPath),
      fileManagementFavorites: fileManagementFavorites == null && nullToAbsent
          ? const Value.absent()
          : Value(fileManagementFavorites),
    );
  }

  factory Server.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Server(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      host: serializer.fromJson<String>(json['host']),
      port: serializer.fromJson<int>(json['port']),
      username: serializer.fromJson<String>(json['username']),
      lastConnectedAt: serializer.fromJson<DateTime?>(json['lastConnectedAt']),
      syncId: serializer.fromJson<String?>(json['syncId']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      credentialType: serializer.fromJson<String?>(json['credentialType']),
      encryptedCredential: serializer.fromJson<String?>(
        json['encryptedCredential'],
      ),
      credentialNonce: serializer.fromJson<String?>(json['credentialNonce']),
      credentialId: serializer.fromJson<int?>(json['credentialId']),
      hostKeyAlgorithm: serializer.fromJson<String?>(json['hostKeyAlgorithm']),
      hostKeyFingerprint: serializer.fromJson<String?>(
        json['hostKeyFingerprint'],
      ),
      collectStats: serializer.fromJson<bool>(json['collectStats']),
      collectSystemInfo: serializer.fromJson<bool>(json['collectSystemInfo']),
      proxyType: serializer.fromJson<String?>(json['proxyType']),
      proxyHost: serializer.fromJson<String?>(json['proxyHost']),
      proxyPort: serializer.fromJson<int?>(json['proxyPort']),
      proxyUsername: serializer.fromJson<String?>(json['proxyUsername']),
      encryptedProxyPassword: serializer.fromJson<String?>(
        json['encryptedProxyPassword'],
      ),
      proxyPasswordNonce: serializer.fromJson<String?>(
        json['proxyPasswordNonce'],
      ),
      jumpHostServerId: serializer.fromJson<int?>(json['jumpHostServerId']),
      environment: serializer.fromJson<String?>(json['environment']),
      initialSnippets: serializer.fromJson<String?>(json['initialSnippets']),
      tags: serializer.fromJson<String?>(json['tags']),
      connectionType: serializer.fromJson<String>(json['connectionType']),
      serialConfig: serializer.fromJson<String?>(json['serialConfig']),
      maidCafeDaemonUrl: serializer.fromJson<String?>(
        json['maidCafeDaemonUrl'],
      ),
      encryptedMaidCafeWebhookSecret: serializer.fromJson<String?>(
        json['encryptedMaidCafeWebhookSecret'],
      ),
      maidCafeWebhookSecretNonce: serializer.fromJson<String?>(
        json['maidCafeWebhookSecretNonce'],
      ),
      encryptedMaidCafeMetricsSecret: serializer.fromJson<String?>(
        json['encryptedMaidCafeMetricsSecret'],
      ),
      maidCafeMetricsSecretNonce: serializer.fromJson<String?>(
        json['maidCafeMetricsSecretNonce'],
      ),
      sortOrder: serializer.fromJson<int?>(json['sortOrder']),
      fileManagementInitialPath: serializer.fromJson<String?>(
        json['fileManagementInitialPath'],
      ),
      fileManagementFavorites: serializer.fromJson<String?>(
        json['fileManagementFavorites'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'host': serializer.toJson<String>(host),
      'port': serializer.toJson<int>(port),
      'username': serializer.toJson<String>(username),
      'lastConnectedAt': serializer.toJson<DateTime?>(lastConnectedAt),
      'syncId': serializer.toJson<String?>(syncId),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'credentialType': serializer.toJson<String?>(credentialType),
      'encryptedCredential': serializer.toJson<String?>(encryptedCredential),
      'credentialNonce': serializer.toJson<String?>(credentialNonce),
      'credentialId': serializer.toJson<int?>(credentialId),
      'hostKeyAlgorithm': serializer.toJson<String?>(hostKeyAlgorithm),
      'hostKeyFingerprint': serializer.toJson<String?>(hostKeyFingerprint),
      'collectStats': serializer.toJson<bool>(collectStats),
      'collectSystemInfo': serializer.toJson<bool>(collectSystemInfo),
      'proxyType': serializer.toJson<String?>(proxyType),
      'proxyHost': serializer.toJson<String?>(proxyHost),
      'proxyPort': serializer.toJson<int?>(proxyPort),
      'proxyUsername': serializer.toJson<String?>(proxyUsername),
      'encryptedProxyPassword': serializer.toJson<String?>(
        encryptedProxyPassword,
      ),
      'proxyPasswordNonce': serializer.toJson<String?>(proxyPasswordNonce),
      'jumpHostServerId': serializer.toJson<int?>(jumpHostServerId),
      'environment': serializer.toJson<String?>(environment),
      'initialSnippets': serializer.toJson<String?>(initialSnippets),
      'tags': serializer.toJson<String?>(tags),
      'connectionType': serializer.toJson<String>(connectionType),
      'serialConfig': serializer.toJson<String?>(serialConfig),
      'maidCafeDaemonUrl': serializer.toJson<String?>(maidCafeDaemonUrl),
      'encryptedMaidCafeWebhookSecret': serializer.toJson<String?>(
        encryptedMaidCafeWebhookSecret,
      ),
      'maidCafeWebhookSecretNonce': serializer.toJson<String?>(
        maidCafeWebhookSecretNonce,
      ),
      'encryptedMaidCafeMetricsSecret': serializer.toJson<String?>(
        encryptedMaidCafeMetricsSecret,
      ),
      'maidCafeMetricsSecretNonce': serializer.toJson<String?>(
        maidCafeMetricsSecretNonce,
      ),
      'sortOrder': serializer.toJson<int?>(sortOrder),
      'fileManagementInitialPath': serializer.toJson<String?>(
        fileManagementInitialPath,
      ),
      'fileManagementFavorites': serializer.toJson<String?>(
        fileManagementFavorites,
      ),
    };
  }

  Server copyWith({
    int? id,
    String? name,
    String? host,
    int? port,
    String? username,
    Value<DateTime?> lastConnectedAt = const Value.absent(),
    Value<String?> syncId = const Value.absent(),
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
    Value<DateTime?> deletedAt = const Value.absent(),
    Value<String?> credentialType = const Value.absent(),
    Value<String?> encryptedCredential = const Value.absent(),
    Value<String?> credentialNonce = const Value.absent(),
    Value<int?> credentialId = const Value.absent(),
    Value<String?> hostKeyAlgorithm = const Value.absent(),
    Value<String?> hostKeyFingerprint = const Value.absent(),
    bool? collectStats,
    bool? collectSystemInfo,
    Value<String?> proxyType = const Value.absent(),
    Value<String?> proxyHost = const Value.absent(),
    Value<int?> proxyPort = const Value.absent(),
    Value<String?> proxyUsername = const Value.absent(),
    Value<String?> encryptedProxyPassword = const Value.absent(),
    Value<String?> proxyPasswordNonce = const Value.absent(),
    Value<int?> jumpHostServerId = const Value.absent(),
    Value<String?> environment = const Value.absent(),
    Value<String?> initialSnippets = const Value.absent(),
    Value<String?> tags = const Value.absent(),
    String? connectionType,
    Value<String?> serialConfig = const Value.absent(),
    Value<String?> maidCafeDaemonUrl = const Value.absent(),
    Value<String?> encryptedMaidCafeWebhookSecret = const Value.absent(),
    Value<String?> maidCafeWebhookSecretNonce = const Value.absent(),
    Value<String?> encryptedMaidCafeMetricsSecret = const Value.absent(),
    Value<String?> maidCafeMetricsSecretNonce = const Value.absent(),
    Value<int?> sortOrder = const Value.absent(),
    Value<String?> fileManagementInitialPath = const Value.absent(),
    Value<String?> fileManagementFavorites = const Value.absent(),
  }) => Server(
    id: id ?? this.id,
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
    username: username ?? this.username,
    lastConnectedAt: lastConnectedAt.present
        ? lastConnectedAt.value
        : this.lastConnectedAt,
    syncId: syncId.present ? syncId.value : this.syncId,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    credentialType: credentialType.present
        ? credentialType.value
        : this.credentialType,
    encryptedCredential: encryptedCredential.present
        ? encryptedCredential.value
        : this.encryptedCredential,
    credentialNonce: credentialNonce.present
        ? credentialNonce.value
        : this.credentialNonce,
    credentialId: credentialId.present ? credentialId.value : this.credentialId,
    hostKeyAlgorithm: hostKeyAlgorithm.present
        ? hostKeyAlgorithm.value
        : this.hostKeyAlgorithm,
    hostKeyFingerprint: hostKeyFingerprint.present
        ? hostKeyFingerprint.value
        : this.hostKeyFingerprint,
    collectStats: collectStats ?? this.collectStats,
    collectSystemInfo: collectSystemInfo ?? this.collectSystemInfo,
    proxyType: proxyType.present ? proxyType.value : this.proxyType,
    proxyHost: proxyHost.present ? proxyHost.value : this.proxyHost,
    proxyPort: proxyPort.present ? proxyPort.value : this.proxyPort,
    proxyUsername: proxyUsername.present
        ? proxyUsername.value
        : this.proxyUsername,
    encryptedProxyPassword: encryptedProxyPassword.present
        ? encryptedProxyPassword.value
        : this.encryptedProxyPassword,
    proxyPasswordNonce: proxyPasswordNonce.present
        ? proxyPasswordNonce.value
        : this.proxyPasswordNonce,
    jumpHostServerId: jumpHostServerId.present
        ? jumpHostServerId.value
        : this.jumpHostServerId,
    environment: environment.present ? environment.value : this.environment,
    initialSnippets: initialSnippets.present
        ? initialSnippets.value
        : this.initialSnippets,
    tags: tags.present ? tags.value : this.tags,
    connectionType: connectionType ?? this.connectionType,
    serialConfig: serialConfig.present ? serialConfig.value : this.serialConfig,
    maidCafeDaemonUrl: maidCafeDaemonUrl.present
        ? maidCafeDaemonUrl.value
        : this.maidCafeDaemonUrl,
    encryptedMaidCafeWebhookSecret: encryptedMaidCafeWebhookSecret.present
        ? encryptedMaidCafeWebhookSecret.value
        : this.encryptedMaidCafeWebhookSecret,
    maidCafeWebhookSecretNonce: maidCafeWebhookSecretNonce.present
        ? maidCafeWebhookSecretNonce.value
        : this.maidCafeWebhookSecretNonce,
    encryptedMaidCafeMetricsSecret: encryptedMaidCafeMetricsSecret.present
        ? encryptedMaidCafeMetricsSecret.value
        : this.encryptedMaidCafeMetricsSecret,
    maidCafeMetricsSecretNonce: maidCafeMetricsSecretNonce.present
        ? maidCafeMetricsSecretNonce.value
        : this.maidCafeMetricsSecretNonce,
    sortOrder: sortOrder.present ? sortOrder.value : this.sortOrder,
    fileManagementInitialPath: fileManagementInitialPath.present
        ? fileManagementInitialPath.value
        : this.fileManagementInitialPath,
    fileManagementFavorites: fileManagementFavorites.present
        ? fileManagementFavorites.value
        : this.fileManagementFavorites,
  );
  Server copyWithCompanion(ServersCompanion data) {
    return Server(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      host: data.host.present ? data.host.value : this.host,
      port: data.port.present ? data.port.value : this.port,
      username: data.username.present ? data.username.value : this.username,
      lastConnectedAt: data.lastConnectedAt.present
          ? data.lastConnectedAt.value
          : this.lastConnectedAt,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      credentialType: data.credentialType.present
          ? data.credentialType.value
          : this.credentialType,
      encryptedCredential: data.encryptedCredential.present
          ? data.encryptedCredential.value
          : this.encryptedCredential,
      credentialNonce: data.credentialNonce.present
          ? data.credentialNonce.value
          : this.credentialNonce,
      credentialId: data.credentialId.present
          ? data.credentialId.value
          : this.credentialId,
      hostKeyAlgorithm: data.hostKeyAlgorithm.present
          ? data.hostKeyAlgorithm.value
          : this.hostKeyAlgorithm,
      hostKeyFingerprint: data.hostKeyFingerprint.present
          ? data.hostKeyFingerprint.value
          : this.hostKeyFingerprint,
      collectStats: data.collectStats.present
          ? data.collectStats.value
          : this.collectStats,
      collectSystemInfo: data.collectSystemInfo.present
          ? data.collectSystemInfo.value
          : this.collectSystemInfo,
      proxyType: data.proxyType.present ? data.proxyType.value : this.proxyType,
      proxyHost: data.proxyHost.present ? data.proxyHost.value : this.proxyHost,
      proxyPort: data.proxyPort.present ? data.proxyPort.value : this.proxyPort,
      proxyUsername: data.proxyUsername.present
          ? data.proxyUsername.value
          : this.proxyUsername,
      encryptedProxyPassword: data.encryptedProxyPassword.present
          ? data.encryptedProxyPassword.value
          : this.encryptedProxyPassword,
      proxyPasswordNonce: data.proxyPasswordNonce.present
          ? data.proxyPasswordNonce.value
          : this.proxyPasswordNonce,
      jumpHostServerId: data.jumpHostServerId.present
          ? data.jumpHostServerId.value
          : this.jumpHostServerId,
      environment: data.environment.present
          ? data.environment.value
          : this.environment,
      initialSnippets: data.initialSnippets.present
          ? data.initialSnippets.value
          : this.initialSnippets,
      tags: data.tags.present ? data.tags.value : this.tags,
      connectionType: data.connectionType.present
          ? data.connectionType.value
          : this.connectionType,
      serialConfig: data.serialConfig.present
          ? data.serialConfig.value
          : this.serialConfig,
      maidCafeDaemonUrl: data.maidCafeDaemonUrl.present
          ? data.maidCafeDaemonUrl.value
          : this.maidCafeDaemonUrl,
      encryptedMaidCafeWebhookSecret:
          data.encryptedMaidCafeWebhookSecret.present
          ? data.encryptedMaidCafeWebhookSecret.value
          : this.encryptedMaidCafeWebhookSecret,
      maidCafeWebhookSecretNonce: data.maidCafeWebhookSecretNonce.present
          ? data.maidCafeWebhookSecretNonce.value
          : this.maidCafeWebhookSecretNonce,
      encryptedMaidCafeMetricsSecret:
          data.encryptedMaidCafeMetricsSecret.present
          ? data.encryptedMaidCafeMetricsSecret.value
          : this.encryptedMaidCafeMetricsSecret,
      maidCafeMetricsSecretNonce: data.maidCafeMetricsSecretNonce.present
          ? data.maidCafeMetricsSecretNonce.value
          : this.maidCafeMetricsSecretNonce,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      fileManagementInitialPath: data.fileManagementInitialPath.present
          ? data.fileManagementInitialPath.value
          : this.fileManagementInitialPath,
      fileManagementFavorites: data.fileManagementFavorites.present
          ? data.fileManagementFavorites.value
          : this.fileManagementFavorites,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Server(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('username: $username, ')
          ..write('lastConnectedAt: $lastConnectedAt, ')
          ..write('syncId: $syncId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('credentialType: $credentialType, ')
          ..write('encryptedCredential: $encryptedCredential, ')
          ..write('credentialNonce: $credentialNonce, ')
          ..write('credentialId: $credentialId, ')
          ..write('hostKeyAlgorithm: $hostKeyAlgorithm, ')
          ..write('hostKeyFingerprint: $hostKeyFingerprint, ')
          ..write('collectStats: $collectStats, ')
          ..write('collectSystemInfo: $collectSystemInfo, ')
          ..write('proxyType: $proxyType, ')
          ..write('proxyHost: $proxyHost, ')
          ..write('proxyPort: $proxyPort, ')
          ..write('proxyUsername: $proxyUsername, ')
          ..write('encryptedProxyPassword: $encryptedProxyPassword, ')
          ..write('proxyPasswordNonce: $proxyPasswordNonce, ')
          ..write('jumpHostServerId: $jumpHostServerId, ')
          ..write('environment: $environment, ')
          ..write('initialSnippets: $initialSnippets, ')
          ..write('tags: $tags, ')
          ..write('connectionType: $connectionType, ')
          ..write('serialConfig: $serialConfig, ')
          ..write('maidCafeDaemonUrl: $maidCafeDaemonUrl, ')
          ..write(
            'encryptedMaidCafeWebhookSecret: $encryptedMaidCafeWebhookSecret, ',
          )
          ..write('maidCafeWebhookSecretNonce: $maidCafeWebhookSecretNonce, ')
          ..write(
            'encryptedMaidCafeMetricsSecret: $encryptedMaidCafeMetricsSecret, ',
          )
          ..write('maidCafeMetricsSecretNonce: $maidCafeMetricsSecretNonce, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('fileManagementInitialPath: $fileManagementInitialPath, ')
          ..write('fileManagementFavorites: $fileManagementFavorites')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    host,
    port,
    username,
    lastConnectedAt,
    syncId,
    createdAt,
    updatedAt,
    deletedAt,
    credentialType,
    encryptedCredential,
    credentialNonce,
    credentialId,
    hostKeyAlgorithm,
    hostKeyFingerprint,
    collectStats,
    collectSystemInfo,
    proxyType,
    proxyHost,
    proxyPort,
    proxyUsername,
    encryptedProxyPassword,
    proxyPasswordNonce,
    jumpHostServerId,
    environment,
    initialSnippets,
    tags,
    connectionType,
    serialConfig,
    maidCafeDaemonUrl,
    encryptedMaidCafeWebhookSecret,
    maidCafeWebhookSecretNonce,
    encryptedMaidCafeMetricsSecret,
    maidCafeMetricsSecretNonce,
    sortOrder,
    fileManagementInitialPath,
    fileManagementFavorites,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Server &&
          other.id == this.id &&
          other.name == this.name &&
          other.host == this.host &&
          other.port == this.port &&
          other.username == this.username &&
          other.lastConnectedAt == this.lastConnectedAt &&
          other.syncId == this.syncId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.credentialType == this.credentialType &&
          other.encryptedCredential == this.encryptedCredential &&
          other.credentialNonce == this.credentialNonce &&
          other.credentialId == this.credentialId &&
          other.hostKeyAlgorithm == this.hostKeyAlgorithm &&
          other.hostKeyFingerprint == this.hostKeyFingerprint &&
          other.collectStats == this.collectStats &&
          other.collectSystemInfo == this.collectSystemInfo &&
          other.proxyType == this.proxyType &&
          other.proxyHost == this.proxyHost &&
          other.proxyPort == this.proxyPort &&
          other.proxyUsername == this.proxyUsername &&
          other.encryptedProxyPassword == this.encryptedProxyPassword &&
          other.proxyPasswordNonce == this.proxyPasswordNonce &&
          other.jumpHostServerId == this.jumpHostServerId &&
          other.environment == this.environment &&
          other.initialSnippets == this.initialSnippets &&
          other.tags == this.tags &&
          other.connectionType == this.connectionType &&
          other.serialConfig == this.serialConfig &&
          other.maidCafeDaemonUrl == this.maidCafeDaemonUrl &&
          other.encryptedMaidCafeWebhookSecret ==
              this.encryptedMaidCafeWebhookSecret &&
          other.maidCafeWebhookSecretNonce == this.maidCafeWebhookSecretNonce &&
          other.encryptedMaidCafeMetricsSecret ==
              this.encryptedMaidCafeMetricsSecret &&
          other.maidCafeMetricsSecretNonce == this.maidCafeMetricsSecretNonce &&
          other.sortOrder == this.sortOrder &&
          other.fileManagementInitialPath == this.fileManagementInitialPath &&
          other.fileManagementFavorites == this.fileManagementFavorites);
}

class ServersCompanion extends UpdateCompanion<Server> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> host;
  final Value<int> port;
  final Value<String> username;
  final Value<DateTime?> lastConnectedAt;
  final Value<String?> syncId;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String?> credentialType;
  final Value<String?> encryptedCredential;
  final Value<String?> credentialNonce;
  final Value<int?> credentialId;
  final Value<String?> hostKeyAlgorithm;
  final Value<String?> hostKeyFingerprint;
  final Value<bool> collectStats;
  final Value<bool> collectSystemInfo;
  final Value<String?> proxyType;
  final Value<String?> proxyHost;
  final Value<int?> proxyPort;
  final Value<String?> proxyUsername;
  final Value<String?> encryptedProxyPassword;
  final Value<String?> proxyPasswordNonce;
  final Value<int?> jumpHostServerId;
  final Value<String?> environment;
  final Value<String?> initialSnippets;
  final Value<String?> tags;
  final Value<String> connectionType;
  final Value<String?> serialConfig;
  final Value<String?> maidCafeDaemonUrl;
  final Value<String?> encryptedMaidCafeWebhookSecret;
  final Value<String?> maidCafeWebhookSecretNonce;
  final Value<String?> encryptedMaidCafeMetricsSecret;
  final Value<String?> maidCafeMetricsSecretNonce;
  final Value<int?> sortOrder;
  final Value<String?> fileManagementInitialPath;
  final Value<String?> fileManagementFavorites;
  const ServersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.host = const Value.absent(),
    this.port = const Value.absent(),
    this.username = const Value.absent(),
    this.lastConnectedAt = const Value.absent(),
    this.syncId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.credentialType = const Value.absent(),
    this.encryptedCredential = const Value.absent(),
    this.credentialNonce = const Value.absent(),
    this.credentialId = const Value.absent(),
    this.hostKeyAlgorithm = const Value.absent(),
    this.hostKeyFingerprint = const Value.absent(),
    this.collectStats = const Value.absent(),
    this.collectSystemInfo = const Value.absent(),
    this.proxyType = const Value.absent(),
    this.proxyHost = const Value.absent(),
    this.proxyPort = const Value.absent(),
    this.proxyUsername = const Value.absent(),
    this.encryptedProxyPassword = const Value.absent(),
    this.proxyPasswordNonce = const Value.absent(),
    this.jumpHostServerId = const Value.absent(),
    this.environment = const Value.absent(),
    this.initialSnippets = const Value.absent(),
    this.tags = const Value.absent(),
    this.connectionType = const Value.absent(),
    this.serialConfig = const Value.absent(),
    this.maidCafeDaemonUrl = const Value.absent(),
    this.encryptedMaidCafeWebhookSecret = const Value.absent(),
    this.maidCafeWebhookSecretNonce = const Value.absent(),
    this.encryptedMaidCafeMetricsSecret = const Value.absent(),
    this.maidCafeMetricsSecretNonce = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.fileManagementInitialPath = const Value.absent(),
    this.fileManagementFavorites = const Value.absent(),
  });
  ServersCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String host,
    this.port = const Value.absent(),
    required String username,
    this.lastConnectedAt = const Value.absent(),
    this.syncId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.credentialType = const Value.absent(),
    this.encryptedCredential = const Value.absent(),
    this.credentialNonce = const Value.absent(),
    this.credentialId = const Value.absent(),
    this.hostKeyAlgorithm = const Value.absent(),
    this.hostKeyFingerprint = const Value.absent(),
    this.collectStats = const Value.absent(),
    this.collectSystemInfo = const Value.absent(),
    this.proxyType = const Value.absent(),
    this.proxyHost = const Value.absent(),
    this.proxyPort = const Value.absent(),
    this.proxyUsername = const Value.absent(),
    this.encryptedProxyPassword = const Value.absent(),
    this.proxyPasswordNonce = const Value.absent(),
    this.jumpHostServerId = const Value.absent(),
    this.environment = const Value.absent(),
    this.initialSnippets = const Value.absent(),
    this.tags = const Value.absent(),
    this.connectionType = const Value.absent(),
    this.serialConfig = const Value.absent(),
    this.maidCafeDaemonUrl = const Value.absent(),
    this.encryptedMaidCafeWebhookSecret = const Value.absent(),
    this.maidCafeWebhookSecretNonce = const Value.absent(),
    this.encryptedMaidCafeMetricsSecret = const Value.absent(),
    this.maidCafeMetricsSecretNonce = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.fileManagementInitialPath = const Value.absent(),
    this.fileManagementFavorites = const Value.absent(),
  }) : name = Value(name),
       host = Value(host),
       username = Value(username);
  static Insertable<Server> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? host,
    Expression<int>? port,
    Expression<String>? username,
    Expression<DateTime>? lastConnectedAt,
    Expression<String>? syncId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? credentialType,
    Expression<String>? encryptedCredential,
    Expression<String>? credentialNonce,
    Expression<int>? credentialId,
    Expression<String>? hostKeyAlgorithm,
    Expression<String>? hostKeyFingerprint,
    Expression<bool>? collectStats,
    Expression<bool>? collectSystemInfo,
    Expression<String>? proxyType,
    Expression<String>? proxyHost,
    Expression<int>? proxyPort,
    Expression<String>? proxyUsername,
    Expression<String>? encryptedProxyPassword,
    Expression<String>? proxyPasswordNonce,
    Expression<int>? jumpHostServerId,
    Expression<String>? environment,
    Expression<String>? initialSnippets,
    Expression<String>? tags,
    Expression<String>? connectionType,
    Expression<String>? serialConfig,
    Expression<String>? maidCafeDaemonUrl,
    Expression<String>? encryptedMaidCafeWebhookSecret,
    Expression<String>? maidCafeWebhookSecretNonce,
    Expression<String>? encryptedMaidCafeMetricsSecret,
    Expression<String>? maidCafeMetricsSecretNonce,
    Expression<int>? sortOrder,
    Expression<String>? fileManagementInitialPath,
    Expression<String>? fileManagementFavorites,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (host != null) 'host': host,
      if (port != null) 'port': port,
      if (username != null) 'username': username,
      if (lastConnectedAt != null) 'last_connected_at': lastConnectedAt,
      if (syncId != null) 'sync_id': syncId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (credentialType != null) 'credential_type': credentialType,
      if (encryptedCredential != null)
        'encrypted_credential': encryptedCredential,
      if (credentialNonce != null) 'credential_nonce': credentialNonce,
      if (credentialId != null) 'credential_id': credentialId,
      if (hostKeyAlgorithm != null) 'host_key_algorithm': hostKeyAlgorithm,
      if (hostKeyFingerprint != null)
        'host_key_fingerprint': hostKeyFingerprint,
      if (collectStats != null) 'collect_stats': collectStats,
      if (collectSystemInfo != null) 'collect_system_info': collectSystemInfo,
      if (proxyType != null) 'proxy_type': proxyType,
      if (proxyHost != null) 'proxy_host': proxyHost,
      if (proxyPort != null) 'proxy_port': proxyPort,
      if (proxyUsername != null) 'proxy_username': proxyUsername,
      if (encryptedProxyPassword != null)
        'encrypted_proxy_password': encryptedProxyPassword,
      if (proxyPasswordNonce != null)
        'proxy_password_nonce': proxyPasswordNonce,
      if (jumpHostServerId != null) 'jump_host_server_id': jumpHostServerId,
      if (environment != null) 'environment': environment,
      if (initialSnippets != null) 'initial_snippets': initialSnippets,
      if (tags != null) 'tags': tags,
      if (connectionType != null) 'connection_type': connectionType,
      if (serialConfig != null) 'serial_config': serialConfig,
      if (maidCafeDaemonUrl != null) 'maid_cafe_daemon_url': maidCafeDaemonUrl,
      if (encryptedMaidCafeWebhookSecret != null)
        'encrypted_maid_cafe_webhook_secret': encryptedMaidCafeWebhookSecret,
      if (maidCafeWebhookSecretNonce != null)
        'maid_cafe_webhook_secret_nonce': maidCafeWebhookSecretNonce,
      if (encryptedMaidCafeMetricsSecret != null)
        'encrypted_maid_cafe_metrics_secret': encryptedMaidCafeMetricsSecret,
      if (maidCafeMetricsSecretNonce != null)
        'maid_cafe_metrics_secret_nonce': maidCafeMetricsSecretNonce,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (fileManagementInitialPath != null)
        'file_management_initial_path': fileManagementInitialPath,
      if (fileManagementFavorites != null)
        'file_management_favorites': fileManagementFavorites,
    });
  }

  ServersCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? host,
    Value<int>? port,
    Value<String>? username,
    Value<DateTime?>? lastConnectedAt,
    Value<String?>? syncId,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String?>? credentialType,
    Value<String?>? encryptedCredential,
    Value<String?>? credentialNonce,
    Value<int?>? credentialId,
    Value<String?>? hostKeyAlgorithm,
    Value<String?>? hostKeyFingerprint,
    Value<bool>? collectStats,
    Value<bool>? collectSystemInfo,
    Value<String?>? proxyType,
    Value<String?>? proxyHost,
    Value<int?>? proxyPort,
    Value<String?>? proxyUsername,
    Value<String?>? encryptedProxyPassword,
    Value<String?>? proxyPasswordNonce,
    Value<int?>? jumpHostServerId,
    Value<String?>? environment,
    Value<String?>? initialSnippets,
    Value<String?>? tags,
    Value<String>? connectionType,
    Value<String?>? serialConfig,
    Value<String?>? maidCafeDaemonUrl,
    Value<String?>? encryptedMaidCafeWebhookSecret,
    Value<String?>? maidCafeWebhookSecretNonce,
    Value<String?>? encryptedMaidCafeMetricsSecret,
    Value<String?>? maidCafeMetricsSecretNonce,
    Value<int?>? sortOrder,
    Value<String?>? fileManagementInitialPath,
    Value<String?>? fileManagementFavorites,
  }) {
    return ServersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      syncId: syncId ?? this.syncId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      credentialType: credentialType ?? this.credentialType,
      encryptedCredential: encryptedCredential ?? this.encryptedCredential,
      credentialNonce: credentialNonce ?? this.credentialNonce,
      credentialId: credentialId ?? this.credentialId,
      hostKeyAlgorithm: hostKeyAlgorithm ?? this.hostKeyAlgorithm,
      hostKeyFingerprint: hostKeyFingerprint ?? this.hostKeyFingerprint,
      collectStats: collectStats ?? this.collectStats,
      collectSystemInfo: collectSystemInfo ?? this.collectSystemInfo,
      proxyType: proxyType ?? this.proxyType,
      proxyHost: proxyHost ?? this.proxyHost,
      proxyPort: proxyPort ?? this.proxyPort,
      proxyUsername: proxyUsername ?? this.proxyUsername,
      encryptedProxyPassword:
          encryptedProxyPassword ?? this.encryptedProxyPassword,
      proxyPasswordNonce: proxyPasswordNonce ?? this.proxyPasswordNonce,
      jumpHostServerId: jumpHostServerId ?? this.jumpHostServerId,
      environment: environment ?? this.environment,
      initialSnippets: initialSnippets ?? this.initialSnippets,
      tags: tags ?? this.tags,
      connectionType: connectionType ?? this.connectionType,
      serialConfig: serialConfig ?? this.serialConfig,
      maidCafeDaemonUrl: maidCafeDaemonUrl ?? this.maidCafeDaemonUrl,
      encryptedMaidCafeWebhookSecret:
          encryptedMaidCafeWebhookSecret ?? this.encryptedMaidCafeWebhookSecret,
      maidCafeWebhookSecretNonce:
          maidCafeWebhookSecretNonce ?? this.maidCafeWebhookSecretNonce,
      encryptedMaidCafeMetricsSecret:
          encryptedMaidCafeMetricsSecret ?? this.encryptedMaidCafeMetricsSecret,
      maidCafeMetricsSecretNonce:
          maidCafeMetricsSecretNonce ?? this.maidCafeMetricsSecretNonce,
      sortOrder: sortOrder ?? this.sortOrder,
      fileManagementInitialPath:
          fileManagementInitialPath ?? this.fileManagementInitialPath,
      fileManagementFavorites:
          fileManagementFavorites ?? this.fileManagementFavorites,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (lastConnectedAt.present) {
      map['last_connected_at'] = Variable<DateTime>(lastConnectedAt.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (credentialType.present) {
      map['credential_type'] = Variable<String>(credentialType.value);
    }
    if (encryptedCredential.present) {
      map['encrypted_credential'] = Variable<String>(encryptedCredential.value);
    }
    if (credentialNonce.present) {
      map['credential_nonce'] = Variable<String>(credentialNonce.value);
    }
    if (credentialId.present) {
      map['credential_id'] = Variable<int>(credentialId.value);
    }
    if (hostKeyAlgorithm.present) {
      map['host_key_algorithm'] = Variable<String>(hostKeyAlgorithm.value);
    }
    if (hostKeyFingerprint.present) {
      map['host_key_fingerprint'] = Variable<String>(hostKeyFingerprint.value);
    }
    if (collectStats.present) {
      map['collect_stats'] = Variable<bool>(collectStats.value);
    }
    if (collectSystemInfo.present) {
      map['collect_system_info'] = Variable<bool>(collectSystemInfo.value);
    }
    if (proxyType.present) {
      map['proxy_type'] = Variable<String>(proxyType.value);
    }
    if (proxyHost.present) {
      map['proxy_host'] = Variable<String>(proxyHost.value);
    }
    if (proxyPort.present) {
      map['proxy_port'] = Variable<int>(proxyPort.value);
    }
    if (proxyUsername.present) {
      map['proxy_username'] = Variable<String>(proxyUsername.value);
    }
    if (encryptedProxyPassword.present) {
      map['encrypted_proxy_password'] = Variable<String>(
        encryptedProxyPassword.value,
      );
    }
    if (proxyPasswordNonce.present) {
      map['proxy_password_nonce'] = Variable<String>(proxyPasswordNonce.value);
    }
    if (jumpHostServerId.present) {
      map['jump_host_server_id'] = Variable<int>(jumpHostServerId.value);
    }
    if (environment.present) {
      map['environment'] = Variable<String>(environment.value);
    }
    if (initialSnippets.present) {
      map['initial_snippets'] = Variable<String>(initialSnippets.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (connectionType.present) {
      map['connection_type'] = Variable<String>(connectionType.value);
    }
    if (serialConfig.present) {
      map['serial_config'] = Variable<String>(serialConfig.value);
    }
    if (maidCafeDaemonUrl.present) {
      map['maid_cafe_daemon_url'] = Variable<String>(maidCafeDaemonUrl.value);
    }
    if (encryptedMaidCafeWebhookSecret.present) {
      map['encrypted_maid_cafe_webhook_secret'] = Variable<String>(
        encryptedMaidCafeWebhookSecret.value,
      );
    }
    if (maidCafeWebhookSecretNonce.present) {
      map['maid_cafe_webhook_secret_nonce'] = Variable<String>(
        maidCafeWebhookSecretNonce.value,
      );
    }
    if (encryptedMaidCafeMetricsSecret.present) {
      map['encrypted_maid_cafe_metrics_secret'] = Variable<String>(
        encryptedMaidCafeMetricsSecret.value,
      );
    }
    if (maidCafeMetricsSecretNonce.present) {
      map['maid_cafe_metrics_secret_nonce'] = Variable<String>(
        maidCafeMetricsSecretNonce.value,
      );
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (fileManagementInitialPath.present) {
      map['file_management_initial_path'] = Variable<String>(
        fileManagementInitialPath.value,
      );
    }
    if (fileManagementFavorites.present) {
      map['file_management_favorites'] = Variable<String>(
        fileManagementFavorites.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ServersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('username: $username, ')
          ..write('lastConnectedAt: $lastConnectedAt, ')
          ..write('syncId: $syncId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('credentialType: $credentialType, ')
          ..write('encryptedCredential: $encryptedCredential, ')
          ..write('credentialNonce: $credentialNonce, ')
          ..write('credentialId: $credentialId, ')
          ..write('hostKeyAlgorithm: $hostKeyAlgorithm, ')
          ..write('hostKeyFingerprint: $hostKeyFingerprint, ')
          ..write('collectStats: $collectStats, ')
          ..write('collectSystemInfo: $collectSystemInfo, ')
          ..write('proxyType: $proxyType, ')
          ..write('proxyHost: $proxyHost, ')
          ..write('proxyPort: $proxyPort, ')
          ..write('proxyUsername: $proxyUsername, ')
          ..write('encryptedProxyPassword: $encryptedProxyPassword, ')
          ..write('proxyPasswordNonce: $proxyPasswordNonce, ')
          ..write('jumpHostServerId: $jumpHostServerId, ')
          ..write('environment: $environment, ')
          ..write('initialSnippets: $initialSnippets, ')
          ..write('tags: $tags, ')
          ..write('connectionType: $connectionType, ')
          ..write('serialConfig: $serialConfig, ')
          ..write('maidCafeDaemonUrl: $maidCafeDaemonUrl, ')
          ..write(
            'encryptedMaidCafeWebhookSecret: $encryptedMaidCafeWebhookSecret, ',
          )
          ..write('maidCafeWebhookSecretNonce: $maidCafeWebhookSecretNonce, ')
          ..write(
            'encryptedMaidCafeMetricsSecret: $encryptedMaidCafeMetricsSecret, ',
          )
          ..write('maidCafeMetricsSecretNonce: $maidCafeMetricsSecretNonce, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('fileManagementInitialPath: $fileManagementInitialPath, ')
          ..write('fileManagementFavorites: $fileManagementFavorites')
          ..write(')'))
        .toString();
  }
}

class $SavedCredentialsTable extends SavedCredentials
    with TableInfo<$SavedCredentialsTable, SavedCredential> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedCredentialsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _credentialTypeMeta = const VerificationMeta(
    'credentialType',
  );
  @override
  late final GeneratedColumn<String> credentialType = GeneratedColumn<String>(
    'credential_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _encryptedCredentialMeta =
      const VerificationMeta('encryptedCredential');
  @override
  late final GeneratedColumn<String> encryptedCredential =
      GeneratedColumn<String>(
        'encrypted_credential',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _credentialNonceMeta = const VerificationMeta(
    'credentialNonce',
  );
  @override
  late final GeneratedColumn<String> credentialNonce = GeneratedColumn<String>(
    'credential_nonce',
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    credentialType,
    encryptedCredential,
    credentialNonce,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_credentials';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedCredential> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('credential_type')) {
      context.handle(
        _credentialTypeMeta,
        credentialType.isAcceptableOrUnknown(
          data['credential_type']!,
          _credentialTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_credentialTypeMeta);
    }
    if (data.containsKey('encrypted_credential')) {
      context.handle(
        _encryptedCredentialMeta,
        encryptedCredential.isAcceptableOrUnknown(
          data['encrypted_credential']!,
          _encryptedCredentialMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptedCredentialMeta);
    }
    if (data.containsKey('credential_nonce')) {
      context.handle(
        _credentialNonceMeta,
        credentialNonce.isAcceptableOrUnknown(
          data['credential_nonce']!,
          _credentialNonceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_credentialNonceMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedCredential map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedCredential(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      credentialType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}credential_type'],
      )!,
      encryptedCredential: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_credential'],
      )!,
      credentialNonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}credential_nonce'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SavedCredentialsTable createAlias(String alias) {
    return $SavedCredentialsTable(attachedDatabase, alias);
  }
}

class SavedCredential extends DataClass implements Insertable<SavedCredential> {
  final int id;
  final String name;
  final String credentialType;
  final String encryptedCredential;
  final String credentialNonce;
  final DateTime createdAt;
  final DateTime updatedAt;
  const SavedCredential({
    required this.id,
    required this.name,
    required this.credentialType,
    required this.encryptedCredential,
    required this.credentialNonce,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['credential_type'] = Variable<String>(credentialType);
    map['encrypted_credential'] = Variable<String>(encryptedCredential);
    map['credential_nonce'] = Variable<String>(credentialNonce);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SavedCredentialsCompanion toCompanion(bool nullToAbsent) {
    return SavedCredentialsCompanion(
      id: Value(id),
      name: Value(name),
      credentialType: Value(credentialType),
      encryptedCredential: Value(encryptedCredential),
      credentialNonce: Value(credentialNonce),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SavedCredential.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedCredential(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      credentialType: serializer.fromJson<String>(json['credentialType']),
      encryptedCredential: serializer.fromJson<String>(
        json['encryptedCredential'],
      ),
      credentialNonce: serializer.fromJson<String>(json['credentialNonce']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'credentialType': serializer.toJson<String>(credentialType),
      'encryptedCredential': serializer.toJson<String>(encryptedCredential),
      'credentialNonce': serializer.toJson<String>(credentialNonce),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SavedCredential copyWith({
    int? id,
    String? name,
    String? credentialType,
    String? encryptedCredential,
    String? credentialNonce,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SavedCredential(
    id: id ?? this.id,
    name: name ?? this.name,
    credentialType: credentialType ?? this.credentialType,
    encryptedCredential: encryptedCredential ?? this.encryptedCredential,
    credentialNonce: credentialNonce ?? this.credentialNonce,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SavedCredential copyWithCompanion(SavedCredentialsCompanion data) {
    return SavedCredential(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      credentialType: data.credentialType.present
          ? data.credentialType.value
          : this.credentialType,
      encryptedCredential: data.encryptedCredential.present
          ? data.encryptedCredential.value
          : this.encryptedCredential,
      credentialNonce: data.credentialNonce.present
          ? data.credentialNonce.value
          : this.credentialNonce,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedCredential(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('credentialType: $credentialType, ')
          ..write('encryptedCredential: $encryptedCredential, ')
          ..write('credentialNonce: $credentialNonce, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    credentialType,
    encryptedCredential,
    credentialNonce,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedCredential &&
          other.id == this.id &&
          other.name == this.name &&
          other.credentialType == this.credentialType &&
          other.encryptedCredential == this.encryptedCredential &&
          other.credentialNonce == this.credentialNonce &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SavedCredentialsCompanion extends UpdateCompanion<SavedCredential> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> credentialType;
  final Value<String> encryptedCredential;
  final Value<String> credentialNonce;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const SavedCredentialsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.credentialType = const Value.absent(),
    this.encryptedCredential = const Value.absent(),
    this.credentialNonce = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  SavedCredentialsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String credentialType,
    required String encryptedCredential,
    required String credentialNonce,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : name = Value(name),
       credentialType = Value(credentialType),
       encryptedCredential = Value(encryptedCredential),
       credentialNonce = Value(credentialNonce),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SavedCredential> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? credentialType,
    Expression<String>? encryptedCredential,
    Expression<String>? credentialNonce,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (credentialType != null) 'credential_type': credentialType,
      if (encryptedCredential != null)
        'encrypted_credential': encryptedCredential,
      if (credentialNonce != null) 'credential_nonce': credentialNonce,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  SavedCredentialsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? credentialType,
    Value<String>? encryptedCredential,
    Value<String>? credentialNonce,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return SavedCredentialsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      credentialType: credentialType ?? this.credentialType,
      encryptedCredential: encryptedCredential ?? this.encryptedCredential,
      credentialNonce: credentialNonce ?? this.credentialNonce,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (credentialType.present) {
      map['credential_type'] = Variable<String>(credentialType.value);
    }
    if (encryptedCredential.present) {
      map['encrypted_credential'] = Variable<String>(encryptedCredential.value);
    }
    if (credentialNonce.present) {
      map['credential_nonce'] = Variable<String>(credentialNonce.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedCredentialsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('credentialType: $credentialType, ')
          ..write('encryptedCredential: $encryptedCredential, ')
          ..write('credentialNonce: $credentialNonce, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $VaultMetadataTable extends VaultMetadata
    with TableInfo<$VaultMetadataTable, VaultMetadataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VaultMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _formatVersionMeta = const VerificationMeta(
    'formatVersion',
  );
  @override
  late final GeneratedColumn<int> formatVersion = GeneratedColumn<int>(
    'format_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _saltMeta = const VerificationMeta('salt');
  @override
  late final GeneratedColumn<String> salt = GeneratedColumn<String>(
    'salt',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wrappedDataKeyMeta = const VerificationMeta(
    'wrappedDataKey',
  );
  @override
  late final GeneratedColumn<String> wrappedDataKey = GeneratedColumn<String>(
    'wrapped_data_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wrappedDataKeyNonceMeta =
      const VerificationMeta('wrappedDataKeyNonce');
  @override
  late final GeneratedColumn<String> wrappedDataKeyNonce =
      GeneratedColumn<String>(
        'wrapped_data_key_nonce',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _verifierMeta = const VerificationMeta(
    'verifier',
  );
  @override
  late final GeneratedColumn<String> verifier = GeneratedColumn<String>(
    'verifier',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _verifierNonceMeta = const VerificationMeta(
    'verifierNonce',
  );
  @override
  late final GeneratedColumn<String> verifierNonce = GeneratedColumn<String>(
    'verifier_nonce',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncPassphraseCiphertextMeta =
      const VerificationMeta('syncPassphraseCiphertext');
  @override
  late final GeneratedColumn<String> syncPassphraseCiphertext =
      GeneratedColumn<String>(
        'sync_passphrase_ciphertext',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _syncPassphraseNonceMeta =
      const VerificationMeta('syncPassphraseNonce');
  @override
  late final GeneratedColumn<String> syncPassphraseNonce =
      GeneratedColumn<String>(
        'sync_passphrase_nonce',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _encryptedTailscaleAuthKeyMeta =
      const VerificationMeta('encryptedTailscaleAuthKey');
  @override
  late final GeneratedColumn<String> encryptedTailscaleAuthKey =
      GeneratedColumn<String>(
        'encrypted_tailscale_auth_key',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _tailscaleAuthKeyNonceMeta =
      const VerificationMeta('tailscaleAuthKeyNonce');
  @override
  late final GeneratedColumn<String> tailscaleAuthKeyNonce =
      GeneratedColumn<String>(
        'tailscale_auth_key_nonce',
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
    id,
    formatVersion,
    salt,
    wrappedDataKey,
    wrappedDataKeyNonce,
    verifier,
    verifierNonce,
    syncPassphraseCiphertext,
    syncPassphraseNonce,
    encryptedTailscaleAuthKey,
    tailscaleAuthKeyNonce,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vault_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<VaultMetadataData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('format_version')) {
      context.handle(
        _formatVersionMeta,
        formatVersion.isAcceptableOrUnknown(
          data['format_version']!,
          _formatVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_formatVersionMeta);
    }
    if (data.containsKey('salt')) {
      context.handle(
        _saltMeta,
        salt.isAcceptableOrUnknown(data['salt']!, _saltMeta),
      );
    } else if (isInserting) {
      context.missing(_saltMeta);
    }
    if (data.containsKey('wrapped_data_key')) {
      context.handle(
        _wrappedDataKeyMeta,
        wrappedDataKey.isAcceptableOrUnknown(
          data['wrapped_data_key']!,
          _wrappedDataKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_wrappedDataKeyMeta);
    }
    if (data.containsKey('wrapped_data_key_nonce')) {
      context.handle(
        _wrappedDataKeyNonceMeta,
        wrappedDataKeyNonce.isAcceptableOrUnknown(
          data['wrapped_data_key_nonce']!,
          _wrappedDataKeyNonceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_wrappedDataKeyNonceMeta);
    }
    if (data.containsKey('verifier')) {
      context.handle(
        _verifierMeta,
        verifier.isAcceptableOrUnknown(data['verifier']!, _verifierMeta),
      );
    } else if (isInserting) {
      context.missing(_verifierMeta);
    }
    if (data.containsKey('verifier_nonce')) {
      context.handle(
        _verifierNonceMeta,
        verifierNonce.isAcceptableOrUnknown(
          data['verifier_nonce']!,
          _verifierNonceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_verifierNonceMeta);
    }
    if (data.containsKey('sync_passphrase_ciphertext')) {
      context.handle(
        _syncPassphraseCiphertextMeta,
        syncPassphraseCiphertext.isAcceptableOrUnknown(
          data['sync_passphrase_ciphertext']!,
          _syncPassphraseCiphertextMeta,
        ),
      );
    }
    if (data.containsKey('sync_passphrase_nonce')) {
      context.handle(
        _syncPassphraseNonceMeta,
        syncPassphraseNonce.isAcceptableOrUnknown(
          data['sync_passphrase_nonce']!,
          _syncPassphraseNonceMeta,
        ),
      );
    }
    if (data.containsKey('encrypted_tailscale_auth_key')) {
      context.handle(
        _encryptedTailscaleAuthKeyMeta,
        encryptedTailscaleAuthKey.isAcceptableOrUnknown(
          data['encrypted_tailscale_auth_key']!,
          _encryptedTailscaleAuthKeyMeta,
        ),
      );
    }
    if (data.containsKey('tailscale_auth_key_nonce')) {
      context.handle(
        _tailscaleAuthKeyNonceMeta,
        tailscaleAuthKeyNonce.isAcceptableOrUnknown(
          data['tailscale_auth_key_nonce']!,
          _tailscaleAuthKeyNonceMeta,
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VaultMetadataData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VaultMetadataData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      formatVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}format_version'],
      )!,
      salt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}salt'],
      )!,
      wrappedDataKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wrapped_data_key'],
      )!,
      wrappedDataKeyNonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wrapped_data_key_nonce'],
      )!,
      verifier: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}verifier'],
      )!,
      verifierNonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}verifier_nonce'],
      )!,
      syncPassphraseCiphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_passphrase_ciphertext'],
      ),
      syncPassphraseNonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_passphrase_nonce'],
      ),
      encryptedTailscaleAuthKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_tailscale_auth_key'],
      ),
      tailscaleAuthKeyNonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tailscale_auth_key_nonce'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $VaultMetadataTable createAlias(String alias) {
    return $VaultMetadataTable(attachedDatabase, alias);
  }
}

class VaultMetadataData extends DataClass
    implements Insertable<VaultMetadataData> {
  final int id;
  final int formatVersion;
  final String salt;
  final String wrappedDataKey;
  final String wrappedDataKeyNonce;
  final String verifier;
  final String verifierNonce;
  final String? syncPassphraseCiphertext;
  final String? syncPassphraseNonce;
  final String? encryptedTailscaleAuthKey;
  final String? tailscaleAuthKeyNonce;
  final DateTime createdAt;
  const VaultMetadataData({
    required this.id,
    required this.formatVersion,
    required this.salt,
    required this.wrappedDataKey,
    required this.wrappedDataKeyNonce,
    required this.verifier,
    required this.verifierNonce,
    this.syncPassphraseCiphertext,
    this.syncPassphraseNonce,
    this.encryptedTailscaleAuthKey,
    this.tailscaleAuthKeyNonce,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['format_version'] = Variable<int>(formatVersion);
    map['salt'] = Variable<String>(salt);
    map['wrapped_data_key'] = Variable<String>(wrappedDataKey);
    map['wrapped_data_key_nonce'] = Variable<String>(wrappedDataKeyNonce);
    map['verifier'] = Variable<String>(verifier);
    map['verifier_nonce'] = Variable<String>(verifierNonce);
    if (!nullToAbsent || syncPassphraseCiphertext != null) {
      map['sync_passphrase_ciphertext'] = Variable<String>(
        syncPassphraseCiphertext,
      );
    }
    if (!nullToAbsent || syncPassphraseNonce != null) {
      map['sync_passphrase_nonce'] = Variable<String>(syncPassphraseNonce);
    }
    if (!nullToAbsent || encryptedTailscaleAuthKey != null) {
      map['encrypted_tailscale_auth_key'] = Variable<String>(
        encryptedTailscaleAuthKey,
      );
    }
    if (!nullToAbsent || tailscaleAuthKeyNonce != null) {
      map['tailscale_auth_key_nonce'] = Variable<String>(tailscaleAuthKeyNonce);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  VaultMetadataCompanion toCompanion(bool nullToAbsent) {
    return VaultMetadataCompanion(
      id: Value(id),
      formatVersion: Value(formatVersion),
      salt: Value(salt),
      wrappedDataKey: Value(wrappedDataKey),
      wrappedDataKeyNonce: Value(wrappedDataKeyNonce),
      verifier: Value(verifier),
      verifierNonce: Value(verifierNonce),
      syncPassphraseCiphertext: syncPassphraseCiphertext == null && nullToAbsent
          ? const Value.absent()
          : Value(syncPassphraseCiphertext),
      syncPassphraseNonce: syncPassphraseNonce == null && nullToAbsent
          ? const Value.absent()
          : Value(syncPassphraseNonce),
      encryptedTailscaleAuthKey:
          encryptedTailscaleAuthKey == null && nullToAbsent
          ? const Value.absent()
          : Value(encryptedTailscaleAuthKey),
      tailscaleAuthKeyNonce: tailscaleAuthKeyNonce == null && nullToAbsent
          ? const Value.absent()
          : Value(tailscaleAuthKeyNonce),
      createdAt: Value(createdAt),
    );
  }

  factory VaultMetadataData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VaultMetadataData(
      id: serializer.fromJson<int>(json['id']),
      formatVersion: serializer.fromJson<int>(json['formatVersion']),
      salt: serializer.fromJson<String>(json['salt']),
      wrappedDataKey: serializer.fromJson<String>(json['wrappedDataKey']),
      wrappedDataKeyNonce: serializer.fromJson<String>(
        json['wrappedDataKeyNonce'],
      ),
      verifier: serializer.fromJson<String>(json['verifier']),
      verifierNonce: serializer.fromJson<String>(json['verifierNonce']),
      syncPassphraseCiphertext: serializer.fromJson<String?>(
        json['syncPassphraseCiphertext'],
      ),
      syncPassphraseNonce: serializer.fromJson<String?>(
        json['syncPassphraseNonce'],
      ),
      encryptedTailscaleAuthKey: serializer.fromJson<String?>(
        json['encryptedTailscaleAuthKey'],
      ),
      tailscaleAuthKeyNonce: serializer.fromJson<String?>(
        json['tailscaleAuthKeyNonce'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'formatVersion': serializer.toJson<int>(formatVersion),
      'salt': serializer.toJson<String>(salt),
      'wrappedDataKey': serializer.toJson<String>(wrappedDataKey),
      'wrappedDataKeyNonce': serializer.toJson<String>(wrappedDataKeyNonce),
      'verifier': serializer.toJson<String>(verifier),
      'verifierNonce': serializer.toJson<String>(verifierNonce),
      'syncPassphraseCiphertext': serializer.toJson<String?>(
        syncPassphraseCiphertext,
      ),
      'syncPassphraseNonce': serializer.toJson<String?>(syncPassphraseNonce),
      'encryptedTailscaleAuthKey': serializer.toJson<String?>(
        encryptedTailscaleAuthKey,
      ),
      'tailscaleAuthKeyNonce': serializer.toJson<String?>(
        tailscaleAuthKeyNonce,
      ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  VaultMetadataData copyWith({
    int? id,
    int? formatVersion,
    String? salt,
    String? wrappedDataKey,
    String? wrappedDataKeyNonce,
    String? verifier,
    String? verifierNonce,
    Value<String?> syncPassphraseCiphertext = const Value.absent(),
    Value<String?> syncPassphraseNonce = const Value.absent(),
    Value<String?> encryptedTailscaleAuthKey = const Value.absent(),
    Value<String?> tailscaleAuthKeyNonce = const Value.absent(),
    DateTime? createdAt,
  }) => VaultMetadataData(
    id: id ?? this.id,
    formatVersion: formatVersion ?? this.formatVersion,
    salt: salt ?? this.salt,
    wrappedDataKey: wrappedDataKey ?? this.wrappedDataKey,
    wrappedDataKeyNonce: wrappedDataKeyNonce ?? this.wrappedDataKeyNonce,
    verifier: verifier ?? this.verifier,
    verifierNonce: verifierNonce ?? this.verifierNonce,
    syncPassphraseCiphertext: syncPassphraseCiphertext.present
        ? syncPassphraseCiphertext.value
        : this.syncPassphraseCiphertext,
    syncPassphraseNonce: syncPassphraseNonce.present
        ? syncPassphraseNonce.value
        : this.syncPassphraseNonce,
    encryptedTailscaleAuthKey: encryptedTailscaleAuthKey.present
        ? encryptedTailscaleAuthKey.value
        : this.encryptedTailscaleAuthKey,
    tailscaleAuthKeyNonce: tailscaleAuthKeyNonce.present
        ? tailscaleAuthKeyNonce.value
        : this.tailscaleAuthKeyNonce,
    createdAt: createdAt ?? this.createdAt,
  );
  VaultMetadataData copyWithCompanion(VaultMetadataCompanion data) {
    return VaultMetadataData(
      id: data.id.present ? data.id.value : this.id,
      formatVersion: data.formatVersion.present
          ? data.formatVersion.value
          : this.formatVersion,
      salt: data.salt.present ? data.salt.value : this.salt,
      wrappedDataKey: data.wrappedDataKey.present
          ? data.wrappedDataKey.value
          : this.wrappedDataKey,
      wrappedDataKeyNonce: data.wrappedDataKeyNonce.present
          ? data.wrappedDataKeyNonce.value
          : this.wrappedDataKeyNonce,
      verifier: data.verifier.present ? data.verifier.value : this.verifier,
      verifierNonce: data.verifierNonce.present
          ? data.verifierNonce.value
          : this.verifierNonce,
      syncPassphraseCiphertext: data.syncPassphraseCiphertext.present
          ? data.syncPassphraseCiphertext.value
          : this.syncPassphraseCiphertext,
      syncPassphraseNonce: data.syncPassphraseNonce.present
          ? data.syncPassphraseNonce.value
          : this.syncPassphraseNonce,
      encryptedTailscaleAuthKey: data.encryptedTailscaleAuthKey.present
          ? data.encryptedTailscaleAuthKey.value
          : this.encryptedTailscaleAuthKey,
      tailscaleAuthKeyNonce: data.tailscaleAuthKeyNonce.present
          ? data.tailscaleAuthKeyNonce.value
          : this.tailscaleAuthKeyNonce,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VaultMetadataData(')
          ..write('id: $id, ')
          ..write('formatVersion: $formatVersion, ')
          ..write('salt: $salt, ')
          ..write('wrappedDataKey: $wrappedDataKey, ')
          ..write('wrappedDataKeyNonce: $wrappedDataKeyNonce, ')
          ..write('verifier: $verifier, ')
          ..write('verifierNonce: $verifierNonce, ')
          ..write('syncPassphraseCiphertext: $syncPassphraseCiphertext, ')
          ..write('syncPassphraseNonce: $syncPassphraseNonce, ')
          ..write('encryptedTailscaleAuthKey: $encryptedTailscaleAuthKey, ')
          ..write('tailscaleAuthKeyNonce: $tailscaleAuthKeyNonce, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    formatVersion,
    salt,
    wrappedDataKey,
    wrappedDataKeyNonce,
    verifier,
    verifierNonce,
    syncPassphraseCiphertext,
    syncPassphraseNonce,
    encryptedTailscaleAuthKey,
    tailscaleAuthKeyNonce,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VaultMetadataData &&
          other.id == this.id &&
          other.formatVersion == this.formatVersion &&
          other.salt == this.salt &&
          other.wrappedDataKey == this.wrappedDataKey &&
          other.wrappedDataKeyNonce == this.wrappedDataKeyNonce &&
          other.verifier == this.verifier &&
          other.verifierNonce == this.verifierNonce &&
          other.syncPassphraseCiphertext == this.syncPassphraseCiphertext &&
          other.syncPassphraseNonce == this.syncPassphraseNonce &&
          other.encryptedTailscaleAuthKey == this.encryptedTailscaleAuthKey &&
          other.tailscaleAuthKeyNonce == this.tailscaleAuthKeyNonce &&
          other.createdAt == this.createdAt);
}

class VaultMetadataCompanion extends UpdateCompanion<VaultMetadataData> {
  final Value<int> id;
  final Value<int> formatVersion;
  final Value<String> salt;
  final Value<String> wrappedDataKey;
  final Value<String> wrappedDataKeyNonce;
  final Value<String> verifier;
  final Value<String> verifierNonce;
  final Value<String?> syncPassphraseCiphertext;
  final Value<String?> syncPassphraseNonce;
  final Value<String?> encryptedTailscaleAuthKey;
  final Value<String?> tailscaleAuthKeyNonce;
  final Value<DateTime> createdAt;
  const VaultMetadataCompanion({
    this.id = const Value.absent(),
    this.formatVersion = const Value.absent(),
    this.salt = const Value.absent(),
    this.wrappedDataKey = const Value.absent(),
    this.wrappedDataKeyNonce = const Value.absent(),
    this.verifier = const Value.absent(),
    this.verifierNonce = const Value.absent(),
    this.syncPassphraseCiphertext = const Value.absent(),
    this.syncPassphraseNonce = const Value.absent(),
    this.encryptedTailscaleAuthKey = const Value.absent(),
    this.tailscaleAuthKeyNonce = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  VaultMetadataCompanion.insert({
    this.id = const Value.absent(),
    required int formatVersion,
    required String salt,
    required String wrappedDataKey,
    required String wrappedDataKeyNonce,
    required String verifier,
    required String verifierNonce,
    this.syncPassphraseCiphertext = const Value.absent(),
    this.syncPassphraseNonce = const Value.absent(),
    this.encryptedTailscaleAuthKey = const Value.absent(),
    this.tailscaleAuthKeyNonce = const Value.absent(),
    required DateTime createdAt,
  }) : formatVersion = Value(formatVersion),
       salt = Value(salt),
       wrappedDataKey = Value(wrappedDataKey),
       wrappedDataKeyNonce = Value(wrappedDataKeyNonce),
       verifier = Value(verifier),
       verifierNonce = Value(verifierNonce),
       createdAt = Value(createdAt);
  static Insertable<VaultMetadataData> custom({
    Expression<int>? id,
    Expression<int>? formatVersion,
    Expression<String>? salt,
    Expression<String>? wrappedDataKey,
    Expression<String>? wrappedDataKeyNonce,
    Expression<String>? verifier,
    Expression<String>? verifierNonce,
    Expression<String>? syncPassphraseCiphertext,
    Expression<String>? syncPassphraseNonce,
    Expression<String>? encryptedTailscaleAuthKey,
    Expression<String>? tailscaleAuthKeyNonce,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (formatVersion != null) 'format_version': formatVersion,
      if (salt != null) 'salt': salt,
      if (wrappedDataKey != null) 'wrapped_data_key': wrappedDataKey,
      if (wrappedDataKeyNonce != null)
        'wrapped_data_key_nonce': wrappedDataKeyNonce,
      if (verifier != null) 'verifier': verifier,
      if (verifierNonce != null) 'verifier_nonce': verifierNonce,
      if (syncPassphraseCiphertext != null)
        'sync_passphrase_ciphertext': syncPassphraseCiphertext,
      if (syncPassphraseNonce != null)
        'sync_passphrase_nonce': syncPassphraseNonce,
      if (encryptedTailscaleAuthKey != null)
        'encrypted_tailscale_auth_key': encryptedTailscaleAuthKey,
      if (tailscaleAuthKeyNonce != null)
        'tailscale_auth_key_nonce': tailscaleAuthKeyNonce,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  VaultMetadataCompanion copyWith({
    Value<int>? id,
    Value<int>? formatVersion,
    Value<String>? salt,
    Value<String>? wrappedDataKey,
    Value<String>? wrappedDataKeyNonce,
    Value<String>? verifier,
    Value<String>? verifierNonce,
    Value<String?>? syncPassphraseCiphertext,
    Value<String?>? syncPassphraseNonce,
    Value<String?>? encryptedTailscaleAuthKey,
    Value<String?>? tailscaleAuthKeyNonce,
    Value<DateTime>? createdAt,
  }) {
    return VaultMetadataCompanion(
      id: id ?? this.id,
      formatVersion: formatVersion ?? this.formatVersion,
      salt: salt ?? this.salt,
      wrappedDataKey: wrappedDataKey ?? this.wrappedDataKey,
      wrappedDataKeyNonce: wrappedDataKeyNonce ?? this.wrappedDataKeyNonce,
      verifier: verifier ?? this.verifier,
      verifierNonce: verifierNonce ?? this.verifierNonce,
      syncPassphraseCiphertext:
          syncPassphraseCiphertext ?? this.syncPassphraseCiphertext,
      syncPassphraseNonce: syncPassphraseNonce ?? this.syncPassphraseNonce,
      encryptedTailscaleAuthKey:
          encryptedTailscaleAuthKey ?? this.encryptedTailscaleAuthKey,
      tailscaleAuthKeyNonce:
          tailscaleAuthKeyNonce ?? this.tailscaleAuthKeyNonce,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (formatVersion.present) {
      map['format_version'] = Variable<int>(formatVersion.value);
    }
    if (salt.present) {
      map['salt'] = Variable<String>(salt.value);
    }
    if (wrappedDataKey.present) {
      map['wrapped_data_key'] = Variable<String>(wrappedDataKey.value);
    }
    if (wrappedDataKeyNonce.present) {
      map['wrapped_data_key_nonce'] = Variable<String>(
        wrappedDataKeyNonce.value,
      );
    }
    if (verifier.present) {
      map['verifier'] = Variable<String>(verifier.value);
    }
    if (verifierNonce.present) {
      map['verifier_nonce'] = Variable<String>(verifierNonce.value);
    }
    if (syncPassphraseCiphertext.present) {
      map['sync_passphrase_ciphertext'] = Variable<String>(
        syncPassphraseCiphertext.value,
      );
    }
    if (syncPassphraseNonce.present) {
      map['sync_passphrase_nonce'] = Variable<String>(
        syncPassphraseNonce.value,
      );
    }
    if (encryptedTailscaleAuthKey.present) {
      map['encrypted_tailscale_auth_key'] = Variable<String>(
        encryptedTailscaleAuthKey.value,
      );
    }
    if (tailscaleAuthKeyNonce.present) {
      map['tailscale_auth_key_nonce'] = Variable<String>(
        tailscaleAuthKeyNonce.value,
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VaultMetadataCompanion(')
          ..write('id: $id, ')
          ..write('formatVersion: $formatVersion, ')
          ..write('salt: $salt, ')
          ..write('wrappedDataKey: $wrappedDataKey, ')
          ..write('wrappedDataKeyNonce: $wrappedDataKeyNonce, ')
          ..write('verifier: $verifier, ')
          ..write('verifierNonce: $verifierNonce, ')
          ..write('syncPassphraseCiphertext: $syncPassphraseCiphertext, ')
          ..write('syncPassphraseNonce: $syncPassphraseNonce, ')
          ..write('encryptedTailscaleAuthKey: $encryptedTailscaleAuthKey, ')
          ..write('tailscaleAuthKeyNonce: $tailscaleAuthKeyNonce, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ComposeProjectLinksTable extends ComposeProjectLinks
    with TableInfo<$ComposeProjectLinksTable, ComposeProjectLink> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ComposeProjectLinksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directoryMeta = const VerificationMeta(
    'directory',
  );
  @override
  late final GeneratedColumn<String> directory = GeneratedColumn<String>(
    'directory',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _runtimeMeta = const VerificationMeta(
    'runtime',
  );
  @override
  late final GeneratedColumn<String> runtime = GeneratedColumn<String>(
    'runtime',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _linkedAtMeta = const VerificationMeta(
    'linkedAt',
  );
  @override
  late final GeneratedColumn<DateTime> linkedAt = GeneratedColumn<DateTime>(
    'linked_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverId,
    name,
    directory,
    runtime,
    scope,
    linkedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'compose_project_links';
  @override
  VerificationContext validateIntegrity(
    Insertable<ComposeProjectLink> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('directory')) {
      context.handle(
        _directoryMeta,
        directory.isAcceptableOrUnknown(data['directory']!, _directoryMeta),
      );
    } else if (isInserting) {
      context.missing(_directoryMeta);
    }
    if (data.containsKey('runtime')) {
      context.handle(
        _runtimeMeta,
        runtime.isAcceptableOrUnknown(data['runtime']!, _runtimeMeta),
      );
    } else if (isInserting) {
      context.missing(_runtimeMeta);
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('linked_at')) {
      context.handle(
        _linkedAtMeta,
        linkedAt.isAcceptableOrUnknown(data['linked_at']!, _linkedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_linkedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ComposeProjectLink map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ComposeProjectLink(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      directory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}directory'],
      )!,
      runtime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}runtime'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      linkedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}linked_at'],
      )!,
    );
  }

  @override
  $ComposeProjectLinksTable createAlias(String alias) {
    return $ComposeProjectLinksTable(attachedDatabase, alias);
  }
}

class ComposeProjectLink extends DataClass
    implements Insertable<ComposeProjectLink> {
  final int id;
  final int serverId;
  final String name;
  final String directory;
  final String runtime;
  final String scope;
  final DateTime linkedAt;
  const ComposeProjectLink({
    required this.id,
    required this.serverId,
    required this.name,
    required this.directory,
    required this.runtime,
    required this.scope,
    required this.linkedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['server_id'] = Variable<int>(serverId);
    map['name'] = Variable<String>(name);
    map['directory'] = Variable<String>(directory);
    map['runtime'] = Variable<String>(runtime);
    map['scope'] = Variable<String>(scope);
    map['linked_at'] = Variable<DateTime>(linkedAt);
    return map;
  }

  ComposeProjectLinksCompanion toCompanion(bool nullToAbsent) {
    return ComposeProjectLinksCompanion(
      id: Value(id),
      serverId: Value(serverId),
      name: Value(name),
      directory: Value(directory),
      runtime: Value(runtime),
      scope: Value(scope),
      linkedAt: Value(linkedAt),
    );
  }

  factory ComposeProjectLink.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ComposeProjectLink(
      id: serializer.fromJson<int>(json['id']),
      serverId: serializer.fromJson<int>(json['serverId']),
      name: serializer.fromJson<String>(json['name']),
      directory: serializer.fromJson<String>(json['directory']),
      runtime: serializer.fromJson<String>(json['runtime']),
      scope: serializer.fromJson<String>(json['scope']),
      linkedAt: serializer.fromJson<DateTime>(json['linkedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'serverId': serializer.toJson<int>(serverId),
      'name': serializer.toJson<String>(name),
      'directory': serializer.toJson<String>(directory),
      'runtime': serializer.toJson<String>(runtime),
      'scope': serializer.toJson<String>(scope),
      'linkedAt': serializer.toJson<DateTime>(linkedAt),
    };
  }

  ComposeProjectLink copyWith({
    int? id,
    int? serverId,
    String? name,
    String? directory,
    String? runtime,
    String? scope,
    DateTime? linkedAt,
  }) => ComposeProjectLink(
    id: id ?? this.id,
    serverId: serverId ?? this.serverId,
    name: name ?? this.name,
    directory: directory ?? this.directory,
    runtime: runtime ?? this.runtime,
    scope: scope ?? this.scope,
    linkedAt: linkedAt ?? this.linkedAt,
  );
  ComposeProjectLink copyWithCompanion(ComposeProjectLinksCompanion data) {
    return ComposeProjectLink(
      id: data.id.present ? data.id.value : this.id,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      name: data.name.present ? data.name.value : this.name,
      directory: data.directory.present ? data.directory.value : this.directory,
      runtime: data.runtime.present ? data.runtime.value : this.runtime,
      scope: data.scope.present ? data.scope.value : this.scope,
      linkedAt: data.linkedAt.present ? data.linkedAt.value : this.linkedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ComposeProjectLink(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('name: $name, ')
          ..write('directory: $directory, ')
          ..write('runtime: $runtime, ')
          ..write('scope: $scope, ')
          ..write('linkedAt: $linkedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, serverId, name, directory, runtime, scope, linkedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ComposeProjectLink &&
          other.id == this.id &&
          other.serverId == this.serverId &&
          other.name == this.name &&
          other.directory == this.directory &&
          other.runtime == this.runtime &&
          other.scope == this.scope &&
          other.linkedAt == this.linkedAt);
}

class ComposeProjectLinksCompanion extends UpdateCompanion<ComposeProjectLink> {
  final Value<int> id;
  final Value<int> serverId;
  final Value<String> name;
  final Value<String> directory;
  final Value<String> runtime;
  final Value<String> scope;
  final Value<DateTime> linkedAt;
  const ComposeProjectLinksCompanion({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    this.name = const Value.absent(),
    this.directory = const Value.absent(),
    this.runtime = const Value.absent(),
    this.scope = const Value.absent(),
    this.linkedAt = const Value.absent(),
  });
  ComposeProjectLinksCompanion.insert({
    this.id = const Value.absent(),
    required int serverId,
    required String name,
    required String directory,
    required String runtime,
    required String scope,
    required DateTime linkedAt,
  }) : serverId = Value(serverId),
       name = Value(name),
       directory = Value(directory),
       runtime = Value(runtime),
       scope = Value(scope),
       linkedAt = Value(linkedAt);
  static Insertable<ComposeProjectLink> custom({
    Expression<int>? id,
    Expression<int>? serverId,
    Expression<String>? name,
    Expression<String>? directory,
    Expression<String>? runtime,
    Expression<String>? scope,
    Expression<DateTime>? linkedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      if (name != null) 'name': name,
      if (directory != null) 'directory': directory,
      if (runtime != null) 'runtime': runtime,
      if (scope != null) 'scope': scope,
      if (linkedAt != null) 'linked_at': linkedAt,
    });
  }

  ComposeProjectLinksCompanion copyWith({
    Value<int>? id,
    Value<int>? serverId,
    Value<String>? name,
    Value<String>? directory,
    Value<String>? runtime,
    Value<String>? scope,
    Value<DateTime>? linkedAt,
  }) {
    return ComposeProjectLinksCompanion(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      name: name ?? this.name,
      directory: directory ?? this.directory,
      runtime: runtime ?? this.runtime,
      scope: scope ?? this.scope,
      linkedAt: linkedAt ?? this.linkedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (directory.present) {
      map['directory'] = Variable<String>(directory.value);
    }
    if (runtime.present) {
      map['runtime'] = Variable<String>(runtime.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (linkedAt.present) {
      map['linked_at'] = Variable<DateTime>(linkedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ComposeProjectLinksCompanion(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('name: $name, ')
          ..write('directory: $directory, ')
          ..write('runtime: $runtime, ')
          ..write('scope: $scope, ')
          ..write('linkedAt: $linkedAt')
          ..write(')'))
        .toString();
  }
}

class $ContainerCacheEntriesTable extends ContainerCacheEntries
    with TableInfo<$ContainerCacheEntriesTable, ContainerCacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContainerCacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _runtimeMeta = const VerificationMeta(
    'runtime',
  );
  @override
  late final GeneratedColumn<String> runtime = GeneratedColumn<String>(
    'runtime',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _containerIdMeta = const VerificationMeta(
    'containerId',
  );
  @override
  late final GeneratedColumn<String> containerId = GeneratedColumn<String>(
    'container_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _imageMeta = const VerificationMeta('image');
  @override
  late final GeneratedColumn<String> image = GeneratedColumn<String>(
    'image',
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
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _composeProjectMeta = const VerificationMeta(
    'composeProject',
  );
  @override
  late final GeneratedColumn<String> composeProject = GeneratedColumn<String>(
    'compose_project',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    serverId,
    runtime,
    scope,
    containerId,
    name,
    image,
    state,
    status,
    composeProject,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'container_cache_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<ContainerCacheEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('runtime')) {
      context.handle(
        _runtimeMeta,
        runtime.isAcceptableOrUnknown(data['runtime']!, _runtimeMeta),
      );
    } else if (isInserting) {
      context.missing(_runtimeMeta);
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('container_id')) {
      context.handle(
        _containerIdMeta,
        containerId.isAcceptableOrUnknown(
          data['container_id']!,
          _containerIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_containerIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('image')) {
      context.handle(
        _imageMeta,
        image.isAcceptableOrUnknown(data['image']!, _imageMeta),
      );
    } else if (isInserting) {
      context.missing(_imageMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('compose_project')) {
      context.handle(
        _composeProjectMeta,
        composeProject.isAcceptableOrUnknown(
          data['compose_project']!,
          _composeProjectMeta,
        ),
      );
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    serverId,
    runtime,
    scope,
    containerId,
  };
  @override
  ContainerCacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContainerCacheEntry(
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_id'],
      )!,
      runtime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}runtime'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      containerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}container_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      image: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      composeProject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}compose_project'],
      ),
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $ContainerCacheEntriesTable createAlias(String alias) {
    return $ContainerCacheEntriesTable(attachedDatabase, alias);
  }
}

class ContainerCacheEntry extends DataClass
    implements Insertable<ContainerCacheEntry> {
  final int serverId;
  final String runtime;
  final String scope;
  final String containerId;
  final String name;
  final String image;
  final String state;
  final String status;
  final String? composeProject;
  final DateTime cachedAt;
  const ContainerCacheEntry({
    required this.serverId,
    required this.runtime,
    required this.scope,
    required this.containerId,
    required this.name,
    required this.image,
    required this.state,
    required this.status,
    this.composeProject,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['server_id'] = Variable<int>(serverId);
    map['runtime'] = Variable<String>(runtime);
    map['scope'] = Variable<String>(scope);
    map['container_id'] = Variable<String>(containerId);
    map['name'] = Variable<String>(name);
    map['image'] = Variable<String>(image);
    map['state'] = Variable<String>(state);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || composeProject != null) {
      map['compose_project'] = Variable<String>(composeProject);
    }
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  ContainerCacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return ContainerCacheEntriesCompanion(
      serverId: Value(serverId),
      runtime: Value(runtime),
      scope: Value(scope),
      containerId: Value(containerId),
      name: Value(name),
      image: Value(image),
      state: Value(state),
      status: Value(status),
      composeProject: composeProject == null && nullToAbsent
          ? const Value.absent()
          : Value(composeProject),
      cachedAt: Value(cachedAt),
    );
  }

  factory ContainerCacheEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContainerCacheEntry(
      serverId: serializer.fromJson<int>(json['serverId']),
      runtime: serializer.fromJson<String>(json['runtime']),
      scope: serializer.fromJson<String>(json['scope']),
      containerId: serializer.fromJson<String>(json['containerId']),
      name: serializer.fromJson<String>(json['name']),
      image: serializer.fromJson<String>(json['image']),
      state: serializer.fromJson<String>(json['state']),
      status: serializer.fromJson<String>(json['status']),
      composeProject: serializer.fromJson<String?>(json['composeProject']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'serverId': serializer.toJson<int>(serverId),
      'runtime': serializer.toJson<String>(runtime),
      'scope': serializer.toJson<String>(scope),
      'containerId': serializer.toJson<String>(containerId),
      'name': serializer.toJson<String>(name),
      'image': serializer.toJson<String>(image),
      'state': serializer.toJson<String>(state),
      'status': serializer.toJson<String>(status),
      'composeProject': serializer.toJson<String?>(composeProject),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  ContainerCacheEntry copyWith({
    int? serverId,
    String? runtime,
    String? scope,
    String? containerId,
    String? name,
    String? image,
    String? state,
    String? status,
    Value<String?> composeProject = const Value.absent(),
    DateTime? cachedAt,
  }) => ContainerCacheEntry(
    serverId: serverId ?? this.serverId,
    runtime: runtime ?? this.runtime,
    scope: scope ?? this.scope,
    containerId: containerId ?? this.containerId,
    name: name ?? this.name,
    image: image ?? this.image,
    state: state ?? this.state,
    status: status ?? this.status,
    composeProject: composeProject.present
        ? composeProject.value
        : this.composeProject,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  ContainerCacheEntry copyWithCompanion(ContainerCacheEntriesCompanion data) {
    return ContainerCacheEntry(
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      runtime: data.runtime.present ? data.runtime.value : this.runtime,
      scope: data.scope.present ? data.scope.value : this.scope,
      containerId: data.containerId.present
          ? data.containerId.value
          : this.containerId,
      name: data.name.present ? data.name.value : this.name,
      image: data.image.present ? data.image.value : this.image,
      state: data.state.present ? data.state.value : this.state,
      status: data.status.present ? data.status.value : this.status,
      composeProject: data.composeProject.present
          ? data.composeProject.value
          : this.composeProject,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContainerCacheEntry(')
          ..write('serverId: $serverId, ')
          ..write('runtime: $runtime, ')
          ..write('scope: $scope, ')
          ..write('containerId: $containerId, ')
          ..write('name: $name, ')
          ..write('image: $image, ')
          ..write('state: $state, ')
          ..write('status: $status, ')
          ..write('composeProject: $composeProject, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    serverId,
    runtime,
    scope,
    containerId,
    name,
    image,
    state,
    status,
    composeProject,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContainerCacheEntry &&
          other.serverId == this.serverId &&
          other.runtime == this.runtime &&
          other.scope == this.scope &&
          other.containerId == this.containerId &&
          other.name == this.name &&
          other.image == this.image &&
          other.state == this.state &&
          other.status == this.status &&
          other.composeProject == this.composeProject &&
          other.cachedAt == this.cachedAt);
}

class ContainerCacheEntriesCompanion
    extends UpdateCompanion<ContainerCacheEntry> {
  final Value<int> serverId;
  final Value<String> runtime;
  final Value<String> scope;
  final Value<String> containerId;
  final Value<String> name;
  final Value<String> image;
  final Value<String> state;
  final Value<String> status;
  final Value<String?> composeProject;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const ContainerCacheEntriesCompanion({
    this.serverId = const Value.absent(),
    this.runtime = const Value.absent(),
    this.scope = const Value.absent(),
    this.containerId = const Value.absent(),
    this.name = const Value.absent(),
    this.image = const Value.absent(),
    this.state = const Value.absent(),
    this.status = const Value.absent(),
    this.composeProject = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ContainerCacheEntriesCompanion.insert({
    required int serverId,
    required String runtime,
    required String scope,
    required String containerId,
    required String name,
    required String image,
    required String state,
    required String status,
    this.composeProject = const Value.absent(),
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : serverId = Value(serverId),
       runtime = Value(runtime),
       scope = Value(scope),
       containerId = Value(containerId),
       name = Value(name),
       image = Value(image),
       state = Value(state),
       status = Value(status),
       cachedAt = Value(cachedAt);
  static Insertable<ContainerCacheEntry> custom({
    Expression<int>? serverId,
    Expression<String>? runtime,
    Expression<String>? scope,
    Expression<String>? containerId,
    Expression<String>? name,
    Expression<String>? image,
    Expression<String>? state,
    Expression<String>? status,
    Expression<String>? composeProject,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (serverId != null) 'server_id': serverId,
      if (runtime != null) 'runtime': runtime,
      if (scope != null) 'scope': scope,
      if (containerId != null) 'container_id': containerId,
      if (name != null) 'name': name,
      if (image != null) 'image': image,
      if (state != null) 'state': state,
      if (status != null) 'status': status,
      if (composeProject != null) 'compose_project': composeProject,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ContainerCacheEntriesCompanion copyWith({
    Value<int>? serverId,
    Value<String>? runtime,
    Value<String>? scope,
    Value<String>? containerId,
    Value<String>? name,
    Value<String>? image,
    Value<String>? state,
    Value<String>? status,
    Value<String?>? composeProject,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return ContainerCacheEntriesCompanion(
      serverId: serverId ?? this.serverId,
      runtime: runtime ?? this.runtime,
      scope: scope ?? this.scope,
      containerId: containerId ?? this.containerId,
      name: name ?? this.name,
      image: image ?? this.image,
      state: state ?? this.state,
      status: status ?? this.status,
      composeProject: composeProject ?? this.composeProject,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (runtime.present) {
      map['runtime'] = Variable<String>(runtime.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (containerId.present) {
      map['container_id'] = Variable<String>(containerId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (image.present) {
      map['image'] = Variable<String>(image.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (composeProject.present) {
      map['compose_project'] = Variable<String>(composeProject.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContainerCacheEntriesCompanion(')
          ..write('serverId: $serverId, ')
          ..write('runtime: $runtime, ')
          ..write('scope: $scope, ')
          ..write('containerId: $containerId, ')
          ..write('name: $name, ')
          ..write('image: $image, ')
          ..write('state: $state, ')
          ..write('status: $status, ')
          ..write('composeProject: $composeProject, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DeploymentProjectsTable extends DeploymentProjects
    with TableInfo<$DeploymentProjectsTable, DeploymentProject> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeploymentProjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'deployment_projects';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeploymentProject> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DeploymentProject map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeploymentProject(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DeploymentProjectsTable createAlias(String alias) {
    return $DeploymentProjectsTable(attachedDatabase, alias);
  }
}

class DeploymentProject extends DataClass
    implements Insertable<DeploymentProject> {
  final int id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  const DeploymentProject({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DeploymentProjectsCompanion toCompanion(bool nullToAbsent) {
    return DeploymentProjectsCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory DeploymentProject.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeploymentProject(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  DeploymentProject copyWith({
    int? id,
    String? name,
    Value<String?> description = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => DeploymentProject(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DeploymentProject copyWithCompanion(DeploymentProjectsCompanion data) {
    return DeploymentProject(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeploymentProject(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, description, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeploymentProject &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class DeploymentProjectsCompanion extends UpdateCompanion<DeploymentProject> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const DeploymentProjectsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  DeploymentProjectsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.description = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DeploymentProject> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  DeploymentProjectsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? description,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return DeploymentProjectsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeploymentProjectsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $DeploymentResourcesTable extends DeploymentResources
    with TableInfo<$DeploymentResourcesTable, DeploymentResource> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeploymentResourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<int> projectId = GeneratedColumn<int>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _configurationMeta = const VerificationMeta(
    'configuration',
  );
  @override
  late final GeneratedColumn<String> configuration = GeneratedColumn<String>(
    'configuration',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    projectId,
    kind,
    name,
    serverId,
    configuration,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'deployment_resources';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeploymentResource> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('configuration')) {
      context.handle(
        _configurationMeta,
        configuration.isAcceptableOrUnknown(
          data['configuration']!,
          _configurationMeta,
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DeploymentResource map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeploymentResource(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}project_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_id'],
      ),
      configuration: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}configuration'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DeploymentResourcesTable createAlias(String alias) {
    return $DeploymentResourcesTable(attachedDatabase, alias);
  }
}

class DeploymentResource extends DataClass
    implements Insertable<DeploymentResource> {
  final int id;
  final int projectId;
  final String kind;
  final String name;
  final int? serverId;
  final String configuration;
  final DateTime createdAt;
  final DateTime updatedAt;
  const DeploymentResource({
    required this.id,
    required this.projectId,
    required this.kind,
    required this.name,
    this.serverId,
    required this.configuration,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['project_id'] = Variable<int>(projectId);
    map['kind'] = Variable<String>(kind);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<int>(serverId);
    }
    map['configuration'] = Variable<String>(configuration);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DeploymentResourcesCompanion toCompanion(bool nullToAbsent) {
    return DeploymentResourcesCompanion(
      id: Value(id),
      projectId: Value(projectId),
      kind: Value(kind),
      name: Value(name),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      configuration: Value(configuration),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory DeploymentResource.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeploymentResource(
      id: serializer.fromJson<int>(json['id']),
      projectId: serializer.fromJson<int>(json['projectId']),
      kind: serializer.fromJson<String>(json['kind']),
      name: serializer.fromJson<String>(json['name']),
      serverId: serializer.fromJson<int?>(json['serverId']),
      configuration: serializer.fromJson<String>(json['configuration']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'projectId': serializer.toJson<int>(projectId),
      'kind': serializer.toJson<String>(kind),
      'name': serializer.toJson<String>(name),
      'serverId': serializer.toJson<int?>(serverId),
      'configuration': serializer.toJson<String>(configuration),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  DeploymentResource copyWith({
    int? id,
    int? projectId,
    String? kind,
    String? name,
    Value<int?> serverId = const Value.absent(),
    String? configuration,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => DeploymentResource(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    serverId: serverId.present ? serverId.value : this.serverId,
    configuration: configuration ?? this.configuration,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DeploymentResource copyWithCompanion(DeploymentResourcesCompanion data) {
    return DeploymentResource(
      id: data.id.present ? data.id.value : this.id,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      kind: data.kind.present ? data.kind.value : this.kind,
      name: data.name.present ? data.name.value : this.name,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      configuration: data.configuration.present
          ? data.configuration.value
          : this.configuration,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeploymentResource(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('serverId: $serverId, ')
          ..write('configuration: $configuration, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    projectId,
    kind,
    name,
    serverId,
    configuration,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeploymentResource &&
          other.id == this.id &&
          other.projectId == this.projectId &&
          other.kind == this.kind &&
          other.name == this.name &&
          other.serverId == this.serverId &&
          other.configuration == this.configuration &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class DeploymentResourcesCompanion extends UpdateCompanion<DeploymentResource> {
  final Value<int> id;
  final Value<int> projectId;
  final Value<String> kind;
  final Value<String> name;
  final Value<int?> serverId;
  final Value<String> configuration;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const DeploymentResourcesCompanion({
    this.id = const Value.absent(),
    this.projectId = const Value.absent(),
    this.kind = const Value.absent(),
    this.name = const Value.absent(),
    this.serverId = const Value.absent(),
    this.configuration = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  DeploymentResourcesCompanion.insert({
    this.id = const Value.absent(),
    required int projectId,
    required String kind,
    required String name,
    this.serverId = const Value.absent(),
    this.configuration = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : projectId = Value(projectId),
       kind = Value(kind),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DeploymentResource> custom({
    Expression<int>? id,
    Expression<int>? projectId,
    Expression<String>? kind,
    Expression<String>? name,
    Expression<int>? serverId,
    Expression<String>? configuration,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (kind != null) 'kind': kind,
      if (name != null) 'name': name,
      if (serverId != null) 'server_id': serverId,
      if (configuration != null) 'configuration': configuration,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  DeploymentResourcesCompanion copyWith({
    Value<int>? id,
    Value<int>? projectId,
    Value<String>? kind,
    Value<String>? name,
    Value<int?>? serverId,
    Value<String>? configuration,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return DeploymentResourcesCompanion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      serverId: serverId ?? this.serverId,
      configuration: configuration ?? this.configuration,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<int>(projectId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (configuration.present) {
      map['configuration'] = Variable<String>(configuration.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeploymentResourcesCompanion(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('serverId: $serverId, ')
          ..write('configuration: $configuration, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ScriptSnippetsTable extends ScriptSnippets
    with TableInfo<$ScriptSnippetsTable, ScriptSnippet> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScriptSnippetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scriptMeta = const VerificationMeta('script');
  @override
  late final GeneratedColumn<String> script = GeneratedColumn<String>(
    'script',
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    script,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'script_snippets';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScriptSnippet> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('script')) {
      context.handle(
        _scriptMeta,
        script.isAcceptableOrUnknown(data['script']!, _scriptMeta),
      );
    } else if (isInserting) {
      context.missing(_scriptMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ScriptSnippet map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScriptSnippet(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      script: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}script'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ScriptSnippetsTable createAlias(String alias) {
    return $ScriptSnippetsTable(attachedDatabase, alias);
  }
}

class ScriptSnippet extends DataClass implements Insertable<ScriptSnippet> {
  final int id;
  final String name;
  final String script;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ScriptSnippet({
    required this.id,
    required this.name,
    required this.script,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['script'] = Variable<String>(script);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ScriptSnippetsCompanion toCompanion(bool nullToAbsent) {
    return ScriptSnippetsCompanion(
      id: Value(id),
      name: Value(name),
      script: Value(script),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ScriptSnippet.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScriptSnippet(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      script: serializer.fromJson<String>(json['script']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'script': serializer.toJson<String>(script),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ScriptSnippet copyWith({
    int? id,
    String? name,
    String? script,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ScriptSnippet(
    id: id ?? this.id,
    name: name ?? this.name,
    script: script ?? this.script,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ScriptSnippet copyWithCompanion(ScriptSnippetsCompanion data) {
    return ScriptSnippet(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      script: data.script.present ? data.script.value : this.script,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScriptSnippet(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('script: $script, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, script, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScriptSnippet &&
          other.id == this.id &&
          other.name == this.name &&
          other.script == this.script &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ScriptSnippetsCompanion extends UpdateCompanion<ScriptSnippet> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> script;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const ScriptSnippetsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.script = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ScriptSnippetsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String script,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : name = Value(name),
       script = Value(script),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ScriptSnippet> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? script,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (script != null) 'script': script,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ScriptSnippetsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? script,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return ScriptSnippetsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      script: script ?? this.script,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (script.present) {
      map['script'] = Variable<String>(script.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScriptSnippetsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('script: $script, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $AgentSettingsTable extends AgentSettings
    with TableInfo<$AgentSettingsTable, AgentSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AgentSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _encryptedApiKeyMeta = const VerificationMeta(
    'encryptedApiKey',
  );
  @override
  late final GeneratedColumn<String> encryptedApiKey = GeneratedColumn<String>(
    'encrypted_api_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _apiKeyNonceMeta = const VerificationMeta(
    'apiKeyNonce',
  );
  @override
  late final GeneratedColumn<String> apiKeyNonce = GeneratedColumn<String>(
    'api_key_nonce',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('gpt-4o-mini'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    encryptedApiKey,
    apiKeyNonce,
    model,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'agent_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AgentSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('encrypted_api_key')) {
      context.handle(
        _encryptedApiKeyMeta,
        encryptedApiKey.isAcceptableOrUnknown(
          data['encrypted_api_key']!,
          _encryptedApiKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptedApiKeyMeta);
    }
    if (data.containsKey('api_key_nonce')) {
      context.handle(
        _apiKeyNonceMeta,
        apiKeyNonce.isAcceptableOrUnknown(
          data['api_key_nonce']!,
          _apiKeyNonceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_apiKeyNonceMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AgentSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AgentSetting(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      encryptedApiKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_api_key'],
      )!,
      apiKeyNonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}api_key_nonce'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AgentSettingsTable createAlias(String alias) {
    return $AgentSettingsTable(attachedDatabase, alias);
  }
}

class AgentSetting extends DataClass implements Insertable<AgentSetting> {
  final int id;
  final String encryptedApiKey;
  final String apiKeyNonce;
  final String model;
  final DateTime updatedAt;
  const AgentSetting({
    required this.id,
    required this.encryptedApiKey,
    required this.apiKeyNonce,
    required this.model,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['encrypted_api_key'] = Variable<String>(encryptedApiKey);
    map['api_key_nonce'] = Variable<String>(apiKeyNonce);
    map['model'] = Variable<String>(model);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AgentSettingsCompanion toCompanion(bool nullToAbsent) {
    return AgentSettingsCompanion(
      id: Value(id),
      encryptedApiKey: Value(encryptedApiKey),
      apiKeyNonce: Value(apiKeyNonce),
      model: Value(model),
      updatedAt: Value(updatedAt),
    );
  }

  factory AgentSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AgentSetting(
      id: serializer.fromJson<int>(json['id']),
      encryptedApiKey: serializer.fromJson<String>(json['encryptedApiKey']),
      apiKeyNonce: serializer.fromJson<String>(json['apiKeyNonce']),
      model: serializer.fromJson<String>(json['model']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'encryptedApiKey': serializer.toJson<String>(encryptedApiKey),
      'apiKeyNonce': serializer.toJson<String>(apiKeyNonce),
      'model': serializer.toJson<String>(model),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AgentSetting copyWith({
    int? id,
    String? encryptedApiKey,
    String? apiKeyNonce,
    String? model,
    DateTime? updatedAt,
  }) => AgentSetting(
    id: id ?? this.id,
    encryptedApiKey: encryptedApiKey ?? this.encryptedApiKey,
    apiKeyNonce: apiKeyNonce ?? this.apiKeyNonce,
    model: model ?? this.model,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AgentSetting copyWithCompanion(AgentSettingsCompanion data) {
    return AgentSetting(
      id: data.id.present ? data.id.value : this.id,
      encryptedApiKey: data.encryptedApiKey.present
          ? data.encryptedApiKey.value
          : this.encryptedApiKey,
      apiKeyNonce: data.apiKeyNonce.present
          ? data.apiKeyNonce.value
          : this.apiKeyNonce,
      model: data.model.present ? data.model.value : this.model,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AgentSetting(')
          ..write('id: $id, ')
          ..write('encryptedApiKey: $encryptedApiKey, ')
          ..write('apiKeyNonce: $apiKeyNonce, ')
          ..write('model: $model, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, encryptedApiKey, apiKeyNonce, model, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentSetting &&
          other.id == this.id &&
          other.encryptedApiKey == this.encryptedApiKey &&
          other.apiKeyNonce == this.apiKeyNonce &&
          other.model == this.model &&
          other.updatedAt == this.updatedAt);
}

class AgentSettingsCompanion extends UpdateCompanion<AgentSetting> {
  final Value<int> id;
  final Value<String> encryptedApiKey;
  final Value<String> apiKeyNonce;
  final Value<String> model;
  final Value<DateTime> updatedAt;
  const AgentSettingsCompanion({
    this.id = const Value.absent(),
    this.encryptedApiKey = const Value.absent(),
    this.apiKeyNonce = const Value.absent(),
    this.model = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  AgentSettingsCompanion.insert({
    this.id = const Value.absent(),
    required String encryptedApiKey,
    required String apiKeyNonce,
    this.model = const Value.absent(),
    required DateTime updatedAt,
  }) : encryptedApiKey = Value(encryptedApiKey),
       apiKeyNonce = Value(apiKeyNonce),
       updatedAt = Value(updatedAt);
  static Insertable<AgentSetting> custom({
    Expression<int>? id,
    Expression<String>? encryptedApiKey,
    Expression<String>? apiKeyNonce,
    Expression<String>? model,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (encryptedApiKey != null) 'encrypted_api_key': encryptedApiKey,
      if (apiKeyNonce != null) 'api_key_nonce': apiKeyNonce,
      if (model != null) 'model': model,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  AgentSettingsCompanion copyWith({
    Value<int>? id,
    Value<String>? encryptedApiKey,
    Value<String>? apiKeyNonce,
    Value<String>? model,
    Value<DateTime>? updatedAt,
  }) {
    return AgentSettingsCompanion(
      id: id ?? this.id,
      encryptedApiKey: encryptedApiKey ?? this.encryptedApiKey,
      apiKeyNonce: apiKeyNonce ?? this.apiKeyNonce,
      model: model ?? this.model,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (encryptedApiKey.present) {
      map['encrypted_api_key'] = Variable<String>(encryptedApiKey.value);
    }
    if (apiKeyNonce.present) {
      map['api_key_nonce'] = Variable<String>(apiKeyNonce.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AgentSettingsCompanion(')
          ..write('id: $id, ')
          ..write('encryptedApiKey: $encryptedApiKey, ')
          ..write('apiKeyNonce: $apiKeyNonce, ')
          ..write('model: $model, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $AgentProvidersTable extends AgentProviders
    with TableInfo<$AgentProvidersTable, AgentProvider> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AgentProvidersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _encryptedApiKeyMeta = const VerificationMeta(
    'encryptedApiKey',
  );
  @override
  late final GeneratedColumn<String> encryptedApiKey = GeneratedColumn<String>(
    'encrypted_api_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _apiKeyNonceMeta = const VerificationMeta(
    'apiKeyNonce',
  );
  @override
  late final GeneratedColumn<String> apiKeyNonce = GeneratedColumn<String>(
    'api_key_nonce',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseUrlMeta = const VerificationMeta(
    'baseUrl',
  );
  @override
  late final GeneratedColumn<String> baseUrl = GeneratedColumn<String>(
    'base_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    encryptedApiKey,
    apiKeyNonce,
    baseUrl,
    model,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'agent_providers';
  @override
  VerificationContext validateIntegrity(
    Insertable<AgentProvider> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('encrypted_api_key')) {
      context.handle(
        _encryptedApiKeyMeta,
        encryptedApiKey.isAcceptableOrUnknown(
          data['encrypted_api_key']!,
          _encryptedApiKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptedApiKeyMeta);
    }
    if (data.containsKey('api_key_nonce')) {
      context.handle(
        _apiKeyNonceMeta,
        apiKeyNonce.isAcceptableOrUnknown(
          data['api_key_nonce']!,
          _apiKeyNonceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_apiKeyNonceMeta);
    }
    if (data.containsKey('base_url')) {
      context.handle(
        _baseUrlMeta,
        baseUrl.isAcceptableOrUnknown(data['base_url']!, _baseUrlMeta),
      );
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AgentProvider map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AgentProvider(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      encryptedApiKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_api_key'],
      )!,
      apiKeyNonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}api_key_nonce'],
      )!,
      baseUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_url'],
      ),
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AgentProvidersTable createAlias(String alias) {
    return $AgentProvidersTable(attachedDatabase, alias);
  }
}

class AgentProvider extends DataClass implements Insertable<AgentProvider> {
  final int id;
  final String name;
  final String encryptedApiKey;
  final String apiKeyNonce;
  final String? baseUrl;
  final String model;
  final DateTime updatedAt;
  const AgentProvider({
    required this.id,
    required this.name,
    required this.encryptedApiKey,
    required this.apiKeyNonce,
    this.baseUrl,
    required this.model,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['encrypted_api_key'] = Variable<String>(encryptedApiKey);
    map['api_key_nonce'] = Variable<String>(apiKeyNonce);
    if (!nullToAbsent || baseUrl != null) {
      map['base_url'] = Variable<String>(baseUrl);
    }
    map['model'] = Variable<String>(model);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AgentProvidersCompanion toCompanion(bool nullToAbsent) {
    return AgentProvidersCompanion(
      id: Value(id),
      name: Value(name),
      encryptedApiKey: Value(encryptedApiKey),
      apiKeyNonce: Value(apiKeyNonce),
      baseUrl: baseUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(baseUrl),
      model: Value(model),
      updatedAt: Value(updatedAt),
    );
  }

  factory AgentProvider.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AgentProvider(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      encryptedApiKey: serializer.fromJson<String>(json['encryptedApiKey']),
      apiKeyNonce: serializer.fromJson<String>(json['apiKeyNonce']),
      baseUrl: serializer.fromJson<String?>(json['baseUrl']),
      model: serializer.fromJson<String>(json['model']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'encryptedApiKey': serializer.toJson<String>(encryptedApiKey),
      'apiKeyNonce': serializer.toJson<String>(apiKeyNonce),
      'baseUrl': serializer.toJson<String?>(baseUrl),
      'model': serializer.toJson<String>(model),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AgentProvider copyWith({
    int? id,
    String? name,
    String? encryptedApiKey,
    String? apiKeyNonce,
    Value<String?> baseUrl = const Value.absent(),
    String? model,
    DateTime? updatedAt,
  }) => AgentProvider(
    id: id ?? this.id,
    name: name ?? this.name,
    encryptedApiKey: encryptedApiKey ?? this.encryptedApiKey,
    apiKeyNonce: apiKeyNonce ?? this.apiKeyNonce,
    baseUrl: baseUrl.present ? baseUrl.value : this.baseUrl,
    model: model ?? this.model,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AgentProvider copyWithCompanion(AgentProvidersCompanion data) {
    return AgentProvider(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      encryptedApiKey: data.encryptedApiKey.present
          ? data.encryptedApiKey.value
          : this.encryptedApiKey,
      apiKeyNonce: data.apiKeyNonce.present
          ? data.apiKeyNonce.value
          : this.apiKeyNonce,
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      model: data.model.present ? data.model.value : this.model,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AgentProvider(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('encryptedApiKey: $encryptedApiKey, ')
          ..write('apiKeyNonce: $apiKeyNonce, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('model: $model, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    encryptedApiKey,
    apiKeyNonce,
    baseUrl,
    model,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentProvider &&
          other.id == this.id &&
          other.name == this.name &&
          other.encryptedApiKey == this.encryptedApiKey &&
          other.apiKeyNonce == this.apiKeyNonce &&
          other.baseUrl == this.baseUrl &&
          other.model == this.model &&
          other.updatedAt == this.updatedAt);
}

class AgentProvidersCompanion extends UpdateCompanion<AgentProvider> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> encryptedApiKey;
  final Value<String> apiKeyNonce;
  final Value<String?> baseUrl;
  final Value<String> model;
  final Value<DateTime> updatedAt;
  const AgentProvidersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.encryptedApiKey = const Value.absent(),
    this.apiKeyNonce = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.model = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  AgentProvidersCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String encryptedApiKey,
    required String apiKeyNonce,
    this.baseUrl = const Value.absent(),
    required String model,
    required DateTime updatedAt,
  }) : name = Value(name),
       encryptedApiKey = Value(encryptedApiKey),
       apiKeyNonce = Value(apiKeyNonce),
       model = Value(model),
       updatedAt = Value(updatedAt);
  static Insertable<AgentProvider> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? encryptedApiKey,
    Expression<String>? apiKeyNonce,
    Expression<String>? baseUrl,
    Expression<String>? model,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (encryptedApiKey != null) 'encrypted_api_key': encryptedApiKey,
      if (apiKeyNonce != null) 'api_key_nonce': apiKeyNonce,
      if (baseUrl != null) 'base_url': baseUrl,
      if (model != null) 'model': model,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  AgentProvidersCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? encryptedApiKey,
    Value<String>? apiKeyNonce,
    Value<String?>? baseUrl,
    Value<String>? model,
    Value<DateTime>? updatedAt,
  }) {
    return AgentProvidersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      encryptedApiKey: encryptedApiKey ?? this.encryptedApiKey,
      apiKeyNonce: apiKeyNonce ?? this.apiKeyNonce,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (encryptedApiKey.present) {
      map['encrypted_api_key'] = Variable<String>(encryptedApiKey.value);
    }
    if (apiKeyNonce.present) {
      map['api_key_nonce'] = Variable<String>(apiKeyNonce.value);
    }
    if (baseUrl.present) {
      map['base_url'] = Variable<String>(baseUrl.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AgentProvidersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('encryptedApiKey: $encryptedApiKey, ')
          ..write('apiKeyNonce: $apiKeyNonce, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('model: $model, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $AgentProviderModelsTable extends AgentProviderModels
    with TableInfo<$AgentProviderModelsTable, AgentProviderModel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AgentProviderModelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _providerIdMeta = const VerificationMeta(
    'providerId',
  );
  @override
  late final GeneratedColumn<int> providerId = GeneratedColumn<int>(
    'provider_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
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
  List<GeneratedColumn> get $columns => [id, providerId, model, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'agent_provider_models';
  @override
  VerificationContext validateIntegrity(
    Insertable<AgentProviderModel> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('provider_id')) {
      context.handle(
        _providerIdMeta,
        providerId.isAcceptableOrUnknown(data['provider_id']!, _providerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_providerIdMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
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
  AgentProviderModel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AgentProviderModel(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      providerId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}provider_id'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AgentProviderModelsTable createAlias(String alias) {
    return $AgentProviderModelsTable(attachedDatabase, alias);
  }
}

class AgentProviderModel extends DataClass
    implements Insertable<AgentProviderModel> {
  final int id;
  final int providerId;
  final String model;
  final DateTime createdAt;
  const AgentProviderModel({
    required this.id,
    required this.providerId,
    required this.model,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['provider_id'] = Variable<int>(providerId);
    map['model'] = Variable<String>(model);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AgentProviderModelsCompanion toCompanion(bool nullToAbsent) {
    return AgentProviderModelsCompanion(
      id: Value(id),
      providerId: Value(providerId),
      model: Value(model),
      createdAt: Value(createdAt),
    );
  }

  factory AgentProviderModel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AgentProviderModel(
      id: serializer.fromJson<int>(json['id']),
      providerId: serializer.fromJson<int>(json['providerId']),
      model: serializer.fromJson<String>(json['model']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'providerId': serializer.toJson<int>(providerId),
      'model': serializer.toJson<String>(model),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  AgentProviderModel copyWith({
    int? id,
    int? providerId,
    String? model,
    DateTime? createdAt,
  }) => AgentProviderModel(
    id: id ?? this.id,
    providerId: providerId ?? this.providerId,
    model: model ?? this.model,
    createdAt: createdAt ?? this.createdAt,
  );
  AgentProviderModel copyWithCompanion(AgentProviderModelsCompanion data) {
    return AgentProviderModel(
      id: data.id.present ? data.id.value : this.id,
      providerId: data.providerId.present
          ? data.providerId.value
          : this.providerId,
      model: data.model.present ? data.model.value : this.model,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AgentProviderModel(')
          ..write('id: $id, ')
          ..write('providerId: $providerId, ')
          ..write('model: $model, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, providerId, model, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentProviderModel &&
          other.id == this.id &&
          other.providerId == this.providerId &&
          other.model == this.model &&
          other.createdAt == this.createdAt);
}

class AgentProviderModelsCompanion extends UpdateCompanion<AgentProviderModel> {
  final Value<int> id;
  final Value<int> providerId;
  final Value<String> model;
  final Value<DateTime> createdAt;
  const AgentProviderModelsCompanion({
    this.id = const Value.absent(),
    this.providerId = const Value.absent(),
    this.model = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  AgentProviderModelsCompanion.insert({
    this.id = const Value.absent(),
    required int providerId,
    required String model,
    required DateTime createdAt,
  }) : providerId = Value(providerId),
       model = Value(model),
       createdAt = Value(createdAt);
  static Insertable<AgentProviderModel> custom({
    Expression<int>? id,
    Expression<int>? providerId,
    Expression<String>? model,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (providerId != null) 'provider_id': providerId,
      if (model != null) 'model': model,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  AgentProviderModelsCompanion copyWith({
    Value<int>? id,
    Value<int>? providerId,
    Value<String>? model,
    Value<DateTime>? createdAt,
  }) {
    return AgentProviderModelsCompanion(
      id: id ?? this.id,
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (providerId.present) {
      map['provider_id'] = Variable<int>(providerId.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AgentProviderModelsCompanion(')
          ..write('id: $id, ')
          ..write('providerId: $providerId, ')
          ..write('model: $model, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $McpServersTable extends McpServers
    with TableInfo<$McpServersTable, McpServer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $McpServersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _commandMeta = const VerificationMeta(
    'command',
  );
  @override
  late final GeneratedColumn<String> command = GeneratedColumn<String>(
    'command',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _argumentsMeta = const VerificationMeta(
    'arguments',
  );
  @override
  late final GeneratedColumn<String> arguments = GeneratedColumn<String>(
    'arguments',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _environmentMeta = const VerificationMeta(
    'environment',
  );
  @override
  late final GeneratedColumn<String> environment = GeneratedColumn<String>(
    'environment',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    command,
    arguments,
    environment,
    enabled,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mcp_servers';
  @override
  VerificationContext validateIntegrity(
    Insertable<McpServer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('command')) {
      context.handle(
        _commandMeta,
        command.isAcceptableOrUnknown(data['command']!, _commandMeta),
      );
    } else if (isInserting) {
      context.missing(_commandMeta);
    }
    if (data.containsKey('arguments')) {
      context.handle(
        _argumentsMeta,
        arguments.isAcceptableOrUnknown(data['arguments']!, _argumentsMeta),
      );
    }
    if (data.containsKey('environment')) {
      context.handle(
        _environmentMeta,
        environment.isAcceptableOrUnknown(
          data['environment']!,
          _environmentMeta,
        ),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  McpServer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return McpServer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      command: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command'],
      )!,
      arguments: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}arguments'],
      )!,
      environment: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}environment'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $McpServersTable createAlias(String alias) {
    return $McpServersTable(attachedDatabase, alias);
  }
}

class McpServer extends DataClass implements Insertable<McpServer> {
  final int id;
  final String name;
  final String command;
  final String arguments;
  final String environment;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  const McpServer({
    required this.id,
    required this.name,
    required this.command,
    required this.arguments,
    required this.environment,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['command'] = Variable<String>(command);
    map['arguments'] = Variable<String>(arguments);
    map['environment'] = Variable<String>(environment);
    map['enabled'] = Variable<bool>(enabled);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  McpServersCompanion toCompanion(bool nullToAbsent) {
    return McpServersCompanion(
      id: Value(id),
      name: Value(name),
      command: Value(command),
      arguments: Value(arguments),
      environment: Value(environment),
      enabled: Value(enabled),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory McpServer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return McpServer(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      command: serializer.fromJson<String>(json['command']),
      arguments: serializer.fromJson<String>(json['arguments']),
      environment: serializer.fromJson<String>(json['environment']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'command': serializer.toJson<String>(command),
      'arguments': serializer.toJson<String>(arguments),
      'environment': serializer.toJson<String>(environment),
      'enabled': serializer.toJson<bool>(enabled),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  McpServer copyWith({
    int? id,
    String? name,
    String? command,
    String? arguments,
    String? environment,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => McpServer(
    id: id ?? this.id,
    name: name ?? this.name,
    command: command ?? this.command,
    arguments: arguments ?? this.arguments,
    environment: environment ?? this.environment,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  McpServer copyWithCompanion(McpServersCompanion data) {
    return McpServer(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      command: data.command.present ? data.command.value : this.command,
      arguments: data.arguments.present ? data.arguments.value : this.arguments,
      environment: data.environment.present
          ? data.environment.value
          : this.environment,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('McpServer(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('command: $command, ')
          ..write('arguments: $arguments, ')
          ..write('environment: $environment, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    command,
    arguments,
    environment,
    enabled,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is McpServer &&
          other.id == this.id &&
          other.name == this.name &&
          other.command == this.command &&
          other.arguments == this.arguments &&
          other.environment == this.environment &&
          other.enabled == this.enabled &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class McpServersCompanion extends UpdateCompanion<McpServer> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> command;
  final Value<String> arguments;
  final Value<String> environment;
  final Value<bool> enabled;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const McpServersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.command = const Value.absent(),
    this.arguments = const Value.absent(),
    this.environment = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  McpServersCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String command,
    this.arguments = const Value.absent(),
    this.environment = const Value.absent(),
    this.enabled = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : name = Value(name),
       command = Value(command),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<McpServer> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? command,
    Expression<String>? arguments,
    Expression<String>? environment,
    Expression<bool>? enabled,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (command != null) 'command': command,
      if (arguments != null) 'arguments': arguments,
      if (environment != null) 'environment': environment,
      if (enabled != null) 'enabled': enabled,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  McpServersCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? command,
    Value<String>? arguments,
    Value<String>? environment,
    Value<bool>? enabled,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return McpServersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      command: command ?? this.command,
      arguments: arguments ?? this.arguments,
      environment: environment ?? this.environment,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (command.present) {
      map['command'] = Variable<String>(command.value);
    }
    if (arguments.present) {
      map['arguments'] = Variable<String>(arguments.value);
    }
    if (environment.present) {
      map['environment'] = Variable<String>(environment.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('McpServersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('command: $command, ')
          ..write('arguments: $arguments, ')
          ..write('environment: $environment, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $AgentSkillsTable extends AgentSkills
    with TableInfo<$AgentSkillsTable, AgentSkill> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AgentSkillsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    content,
    enabled,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'agent_skills';
  @override
  VerificationContext validateIntegrity(
    Insertable<AgentSkill> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AgentSkill map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AgentSkill(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AgentSkillsTable createAlias(String alias) {
    return $AgentSkillsTable(attachedDatabase, alias);
  }
}

class AgentSkill extends DataClass implements Insertable<AgentSkill> {
  final int id;
  final String name;
  final String description;
  final String content;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  const AgentSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.content,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['description'] = Variable<String>(description);
    map['content'] = Variable<String>(content);
    map['enabled'] = Variable<bool>(enabled);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AgentSkillsCompanion toCompanion(bool nullToAbsent) {
    return AgentSkillsCompanion(
      id: Value(id),
      name: Value(name),
      description: Value(description),
      content: Value(content),
      enabled: Value(enabled),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AgentSkill.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AgentSkill(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String>(json['description']),
      content: serializer.fromJson<String>(json['content']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String>(description),
      'content': serializer.toJson<String>(content),
      'enabled': serializer.toJson<bool>(enabled),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AgentSkill copyWith({
    int? id,
    String? name,
    String? description,
    String? content,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => AgentSkill(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    content: content ?? this.content,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AgentSkill copyWithCompanion(AgentSkillsCompanion data) {
    return AgentSkill(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      content: data.content.present ? data.content.value : this.content,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AgentSkill(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('content: $content, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    content,
    enabled,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentSkill &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.content == this.content &&
          other.enabled == this.enabled &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AgentSkillsCompanion extends UpdateCompanion<AgentSkill> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> description;
  final Value<String> content;
  final Value<bool> enabled;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const AgentSkillsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.content = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  AgentSkillsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.description = const Value.absent(),
    required String content,
    this.enabled = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : name = Value(name),
       content = Value(content),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AgentSkill> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? content,
    Expression<bool>? enabled,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (content != null) 'content': content,
      if (enabled != null) 'enabled': enabled,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  AgentSkillsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? description,
    Value<String>? content,
    Value<bool>? enabled,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return AgentSkillsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      content: content ?? this.content,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AgentSkillsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('content: $content, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $GitHubConnectionsTable extends GitHubConnections
    with TableInfo<$GitHubConnectionsTable, GitHubConnection> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GitHubConnectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _accountLoginMeta = const VerificationMeta(
    'accountLogin',
  );
  @override
  late final GeneratedColumn<String> accountLogin = GeneratedColumn<String>(
    'account_login',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _accountNameMeta = const VerificationMeta(
    'accountName',
  );
  @override
  late final GeneratedColumn<String> accountName = GeneratedColumn<String>(
    'account_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
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
    accountLogin,
    accountName,
    avatarUrl,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'github_connections';
  @override
  VerificationContext validateIntegrity(
    Insertable<GitHubConnection> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('account_login')) {
      context.handle(
        _accountLoginMeta,
        accountLogin.isAcceptableOrUnknown(
          data['account_login']!,
          _accountLoginMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_accountLoginMeta);
    }
    if (data.containsKey('account_name')) {
      context.handle(
        _accountNameMeta,
        accountName.isAcceptableOrUnknown(
          data['account_name']!,
          _accountNameMeta,
        ),
      );
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GitHubConnection map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GitHubConnection(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      accountLogin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_login'],
      )!,
      accountName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_name'],
      )!,
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $GitHubConnectionsTable createAlias(String alias) {
    return $GitHubConnectionsTable(attachedDatabase, alias);
  }
}

class GitHubConnection extends DataClass
    implements Insertable<GitHubConnection> {
  final int id;
  final String accountLogin;
  final String accountName;
  final String avatarUrl;
  final DateTime createdAt;
  const GitHubConnection({
    required this.id,
    required this.accountLogin,
    required this.accountName,
    required this.avatarUrl,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['account_login'] = Variable<String>(accountLogin);
    map['account_name'] = Variable<String>(accountName);
    map['avatar_url'] = Variable<String>(avatarUrl);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  GitHubConnectionsCompanion toCompanion(bool nullToAbsent) {
    return GitHubConnectionsCompanion(
      id: Value(id),
      accountLogin: Value(accountLogin),
      accountName: Value(accountName),
      avatarUrl: Value(avatarUrl),
      createdAt: Value(createdAt),
    );
  }

  factory GitHubConnection.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GitHubConnection(
      id: serializer.fromJson<int>(json['id']),
      accountLogin: serializer.fromJson<String>(json['accountLogin']),
      accountName: serializer.fromJson<String>(json['accountName']),
      avatarUrl: serializer.fromJson<String>(json['avatarUrl']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'accountLogin': serializer.toJson<String>(accountLogin),
      'accountName': serializer.toJson<String>(accountName),
      'avatarUrl': serializer.toJson<String>(avatarUrl),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  GitHubConnection copyWith({
    int? id,
    String? accountLogin,
    String? accountName,
    String? avatarUrl,
    DateTime? createdAt,
  }) => GitHubConnection(
    id: id ?? this.id,
    accountLogin: accountLogin ?? this.accountLogin,
    accountName: accountName ?? this.accountName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    createdAt: createdAt ?? this.createdAt,
  );
  GitHubConnection copyWithCompanion(GitHubConnectionsCompanion data) {
    return GitHubConnection(
      id: data.id.present ? data.id.value : this.id,
      accountLogin: data.accountLogin.present
          ? data.accountLogin.value
          : this.accountLogin,
      accountName: data.accountName.present
          ? data.accountName.value
          : this.accountName,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GitHubConnection(')
          ..write('id: $id, ')
          ..write('accountLogin: $accountLogin, ')
          ..write('accountName: $accountName, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, accountLogin, accountName, avatarUrl, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GitHubConnection &&
          other.id == this.id &&
          other.accountLogin == this.accountLogin &&
          other.accountName == this.accountName &&
          other.avatarUrl == this.avatarUrl &&
          other.createdAt == this.createdAt);
}

class GitHubConnectionsCompanion extends UpdateCompanion<GitHubConnection> {
  final Value<int> id;
  final Value<String> accountLogin;
  final Value<String> accountName;
  final Value<String> avatarUrl;
  final Value<DateTime> createdAt;
  const GitHubConnectionsCompanion({
    this.id = const Value.absent(),
    this.accountLogin = const Value.absent(),
    this.accountName = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  GitHubConnectionsCompanion.insert({
    this.id = const Value.absent(),
    required String accountLogin,
    this.accountName = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    required DateTime createdAt,
  }) : accountLogin = Value(accountLogin),
       createdAt = Value(createdAt);
  static Insertable<GitHubConnection> custom({
    Expression<int>? id,
    Expression<String>? accountLogin,
    Expression<String>? accountName,
    Expression<String>? avatarUrl,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountLogin != null) 'account_login': accountLogin,
      if (accountName != null) 'account_name': accountName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  GitHubConnectionsCompanion copyWith({
    Value<int>? id,
    Value<String>? accountLogin,
    Value<String>? accountName,
    Value<String>? avatarUrl,
    Value<DateTime>? createdAt,
  }) {
    return GitHubConnectionsCompanion(
      id: id ?? this.id,
      accountLogin: accountLogin ?? this.accountLogin,
      accountName: accountName ?? this.accountName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (accountLogin.present) {
      map['account_login'] = Variable<String>(accountLogin.value);
    }
    if (accountName.present) {
      map['account_name'] = Variable<String>(accountName.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GitHubConnectionsCompanion(')
          ..write('id: $id, ')
          ..write('accountLogin: $accountLogin, ')
          ..write('accountName: $accountName, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $GitHubRepoPinsTable extends GitHubRepoPins
    with TableInfo<$GitHubRepoPinsTable, GitHubRepoPin> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GitHubRepoPinsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _connectionIdMeta = const VerificationMeta(
    'connectionId',
  );
  @override
  late final GeneratedColumn<int> connectionId = GeneratedColumn<int>(
    'connection_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES github_connections (id)',
    ),
  );
  static const VerificationMeta _ownerMeta = const VerificationMeta('owner');
  @override
  late final GeneratedColumn<String> owner = GeneratedColumn<String>(
    'owner',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pinnedAtMeta = const VerificationMeta(
    'pinnedAt',
  );
  @override
  late final GeneratedColumn<DateTime> pinnedAt = GeneratedColumn<DateTime>(
    'pinned_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    connectionId,
    owner,
    name,
    pinnedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'github_repo_pins';
  @override
  VerificationContext validateIntegrity(
    Insertable<GitHubRepoPin> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('connection_id')) {
      context.handle(
        _connectionIdMeta,
        connectionId.isAcceptableOrUnknown(
          data['connection_id']!,
          _connectionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_connectionIdMeta);
    }
    if (data.containsKey('owner')) {
      context.handle(
        _ownerMeta,
        owner.isAcceptableOrUnknown(data['owner']!, _ownerMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('pinned_at')) {
      context.handle(
        _pinnedAtMeta,
        pinnedAt.isAcceptableOrUnknown(data['pinned_at']!, _pinnedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_pinnedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GitHubRepoPin map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GitHubRepoPin(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      connectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}connection_id'],
      )!,
      owner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      pinnedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}pinned_at'],
      )!,
    );
  }

  @override
  $GitHubRepoPinsTable createAlias(String alias) {
    return $GitHubRepoPinsTable(attachedDatabase, alias);
  }
}

class GitHubRepoPin extends DataClass implements Insertable<GitHubRepoPin> {
  final int id;
  final int connectionId;
  final String owner;
  final String name;
  final DateTime pinnedAt;
  const GitHubRepoPin({
    required this.id,
    required this.connectionId,
    required this.owner,
    required this.name,
    required this.pinnedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['connection_id'] = Variable<int>(connectionId);
    map['owner'] = Variable<String>(owner);
    map['name'] = Variable<String>(name);
    map['pinned_at'] = Variable<DateTime>(pinnedAt);
    return map;
  }

  GitHubRepoPinsCompanion toCompanion(bool nullToAbsent) {
    return GitHubRepoPinsCompanion(
      id: Value(id),
      connectionId: Value(connectionId),
      owner: Value(owner),
      name: Value(name),
      pinnedAt: Value(pinnedAt),
    );
  }

  factory GitHubRepoPin.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GitHubRepoPin(
      id: serializer.fromJson<int>(json['id']),
      connectionId: serializer.fromJson<int>(json['connectionId']),
      owner: serializer.fromJson<String>(json['owner']),
      name: serializer.fromJson<String>(json['name']),
      pinnedAt: serializer.fromJson<DateTime>(json['pinnedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'connectionId': serializer.toJson<int>(connectionId),
      'owner': serializer.toJson<String>(owner),
      'name': serializer.toJson<String>(name),
      'pinnedAt': serializer.toJson<DateTime>(pinnedAt),
    };
  }

  GitHubRepoPin copyWith({
    int? id,
    int? connectionId,
    String? owner,
    String? name,
    DateTime? pinnedAt,
  }) => GitHubRepoPin(
    id: id ?? this.id,
    connectionId: connectionId ?? this.connectionId,
    owner: owner ?? this.owner,
    name: name ?? this.name,
    pinnedAt: pinnedAt ?? this.pinnedAt,
  );
  GitHubRepoPin copyWithCompanion(GitHubRepoPinsCompanion data) {
    return GitHubRepoPin(
      id: data.id.present ? data.id.value : this.id,
      connectionId: data.connectionId.present
          ? data.connectionId.value
          : this.connectionId,
      owner: data.owner.present ? data.owner.value : this.owner,
      name: data.name.present ? data.name.value : this.name,
      pinnedAt: data.pinnedAt.present ? data.pinnedAt.value : this.pinnedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GitHubRepoPin(')
          ..write('id: $id, ')
          ..write('connectionId: $connectionId, ')
          ..write('owner: $owner, ')
          ..write('name: $name, ')
          ..write('pinnedAt: $pinnedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, connectionId, owner, name, pinnedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GitHubRepoPin &&
          other.id == this.id &&
          other.connectionId == this.connectionId &&
          other.owner == this.owner &&
          other.name == this.name &&
          other.pinnedAt == this.pinnedAt);
}

class GitHubRepoPinsCompanion extends UpdateCompanion<GitHubRepoPin> {
  final Value<int> id;
  final Value<int> connectionId;
  final Value<String> owner;
  final Value<String> name;
  final Value<DateTime> pinnedAt;
  const GitHubRepoPinsCompanion({
    this.id = const Value.absent(),
    this.connectionId = const Value.absent(),
    this.owner = const Value.absent(),
    this.name = const Value.absent(),
    this.pinnedAt = const Value.absent(),
  });
  GitHubRepoPinsCompanion.insert({
    this.id = const Value.absent(),
    required int connectionId,
    required String owner,
    required String name,
    required DateTime pinnedAt,
  }) : connectionId = Value(connectionId),
       owner = Value(owner),
       name = Value(name),
       pinnedAt = Value(pinnedAt);
  static Insertable<GitHubRepoPin> custom({
    Expression<int>? id,
    Expression<int>? connectionId,
    Expression<String>? owner,
    Expression<String>? name,
    Expression<DateTime>? pinnedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (connectionId != null) 'connection_id': connectionId,
      if (owner != null) 'owner': owner,
      if (name != null) 'name': name,
      if (pinnedAt != null) 'pinned_at': pinnedAt,
    });
  }

  GitHubRepoPinsCompanion copyWith({
    Value<int>? id,
    Value<int>? connectionId,
    Value<String>? owner,
    Value<String>? name,
    Value<DateTime>? pinnedAt,
  }) {
    return GitHubRepoPinsCompanion(
      id: id ?? this.id,
      connectionId: connectionId ?? this.connectionId,
      owner: owner ?? this.owner,
      name: name ?? this.name,
      pinnedAt: pinnedAt ?? this.pinnedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (connectionId.present) {
      map['connection_id'] = Variable<int>(connectionId.value);
    }
    if (owner.present) {
      map['owner'] = Variable<String>(owner.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (pinnedAt.present) {
      map['pinned_at'] = Variable<DateTime>(pinnedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GitHubRepoPinsCompanion(')
          ..write('id: $id, ')
          ..write('connectionId: $connectionId, ')
          ..write('owner: $owner, ')
          ..write('name: $name, ')
          ..write('pinnedAt: $pinnedAt')
          ..write(')'))
        .toString();
  }
}

class $GitHubTokensTable extends GitHubTokens
    with TableInfo<$GitHubTokensTable, GitHubToken> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GitHubTokensTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _accountLoginMeta = const VerificationMeta(
    'accountLogin',
  );
  @override
  late final GeneratedColumn<String> accountLogin = GeneratedColumn<String>(
    'account_login',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _encryptedTokenMeta = const VerificationMeta(
    'encryptedToken',
  );
  @override
  late final GeneratedColumn<String> encryptedToken = GeneratedColumn<String>(
    'encrypted_token',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tokenNonceMeta = const VerificationMeta(
    'tokenNonce',
  );
  @override
  late final GeneratedColumn<String> tokenNonce = GeneratedColumn<String>(
    'token_nonce',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountLogin,
    encryptedToken,
    tokenNonce,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'github_tokens';
  @override
  VerificationContext validateIntegrity(
    Insertable<GitHubToken> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('account_login')) {
      context.handle(
        _accountLoginMeta,
        accountLogin.isAcceptableOrUnknown(
          data['account_login']!,
          _accountLoginMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_accountLoginMeta);
    }
    if (data.containsKey('encrypted_token')) {
      context.handle(
        _encryptedTokenMeta,
        encryptedToken.isAcceptableOrUnknown(
          data['encrypted_token']!,
          _encryptedTokenMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptedTokenMeta);
    }
    if (data.containsKey('token_nonce')) {
      context.handle(
        _tokenNonceMeta,
        tokenNonce.isAcceptableOrUnknown(data['token_nonce']!, _tokenNonceMeta),
      );
    } else if (isInserting) {
      context.missing(_tokenNonceMeta);
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GitHubToken map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GitHubToken(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      accountLogin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_login'],
      )!,
      encryptedToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_token'],
      )!,
      tokenNonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}token_nonce'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $GitHubTokensTable createAlias(String alias) {
    return $GitHubTokensTable(attachedDatabase, alias);
  }
}

class GitHubToken extends DataClass implements Insertable<GitHubToken> {
  final int id;
  final String accountLogin;
  final String encryptedToken;
  final String tokenNonce;
  final DateTime updatedAt;
  const GitHubToken({
    required this.id,
    required this.accountLogin,
    required this.encryptedToken,
    required this.tokenNonce,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['account_login'] = Variable<String>(accountLogin);
    map['encrypted_token'] = Variable<String>(encryptedToken);
    map['token_nonce'] = Variable<String>(tokenNonce);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  GitHubTokensCompanion toCompanion(bool nullToAbsent) {
    return GitHubTokensCompanion(
      id: Value(id),
      accountLogin: Value(accountLogin),
      encryptedToken: Value(encryptedToken),
      tokenNonce: Value(tokenNonce),
      updatedAt: Value(updatedAt),
    );
  }

  factory GitHubToken.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GitHubToken(
      id: serializer.fromJson<int>(json['id']),
      accountLogin: serializer.fromJson<String>(json['accountLogin']),
      encryptedToken: serializer.fromJson<String>(json['encryptedToken']),
      tokenNonce: serializer.fromJson<String>(json['tokenNonce']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'accountLogin': serializer.toJson<String>(accountLogin),
      'encryptedToken': serializer.toJson<String>(encryptedToken),
      'tokenNonce': serializer.toJson<String>(tokenNonce),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  GitHubToken copyWith({
    int? id,
    String? accountLogin,
    String? encryptedToken,
    String? tokenNonce,
    DateTime? updatedAt,
  }) => GitHubToken(
    id: id ?? this.id,
    accountLogin: accountLogin ?? this.accountLogin,
    encryptedToken: encryptedToken ?? this.encryptedToken,
    tokenNonce: tokenNonce ?? this.tokenNonce,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  GitHubToken copyWithCompanion(GitHubTokensCompanion data) {
    return GitHubToken(
      id: data.id.present ? data.id.value : this.id,
      accountLogin: data.accountLogin.present
          ? data.accountLogin.value
          : this.accountLogin,
      encryptedToken: data.encryptedToken.present
          ? data.encryptedToken.value
          : this.encryptedToken,
      tokenNonce: data.tokenNonce.present
          ? data.tokenNonce.value
          : this.tokenNonce,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GitHubToken(')
          ..write('id: $id, ')
          ..write('accountLogin: $accountLogin, ')
          ..write('encryptedToken: $encryptedToken, ')
          ..write('tokenNonce: $tokenNonce, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, accountLogin, encryptedToken, tokenNonce, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GitHubToken &&
          other.id == this.id &&
          other.accountLogin == this.accountLogin &&
          other.encryptedToken == this.encryptedToken &&
          other.tokenNonce == this.tokenNonce &&
          other.updatedAt == this.updatedAt);
}

class GitHubTokensCompanion extends UpdateCompanion<GitHubToken> {
  final Value<int> id;
  final Value<String> accountLogin;
  final Value<String> encryptedToken;
  final Value<String> tokenNonce;
  final Value<DateTime> updatedAt;
  const GitHubTokensCompanion({
    this.id = const Value.absent(),
    this.accountLogin = const Value.absent(),
    this.encryptedToken = const Value.absent(),
    this.tokenNonce = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  GitHubTokensCompanion.insert({
    this.id = const Value.absent(),
    required String accountLogin,
    required String encryptedToken,
    required String tokenNonce,
    required DateTime updatedAt,
  }) : accountLogin = Value(accountLogin),
       encryptedToken = Value(encryptedToken),
       tokenNonce = Value(tokenNonce),
       updatedAt = Value(updatedAt);
  static Insertable<GitHubToken> custom({
    Expression<int>? id,
    Expression<String>? accountLogin,
    Expression<String>? encryptedToken,
    Expression<String>? tokenNonce,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountLogin != null) 'account_login': accountLogin,
      if (encryptedToken != null) 'encrypted_token': encryptedToken,
      if (tokenNonce != null) 'token_nonce': tokenNonce,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  GitHubTokensCompanion copyWith({
    Value<int>? id,
    Value<String>? accountLogin,
    Value<String>? encryptedToken,
    Value<String>? tokenNonce,
    Value<DateTime>? updatedAt,
  }) {
    return GitHubTokensCompanion(
      id: id ?? this.id,
      accountLogin: accountLogin ?? this.accountLogin,
      encryptedToken: encryptedToken ?? this.encryptedToken,
      tokenNonce: tokenNonce ?? this.tokenNonce,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (accountLogin.present) {
      map['account_login'] = Variable<String>(accountLogin.value);
    }
    if (encryptedToken.present) {
      map['encrypted_token'] = Variable<String>(encryptedToken.value);
    }
    if (tokenNonce.present) {
      map['token_nonce'] = Variable<String>(tokenNonce.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GitHubTokensCompanion(')
          ..write('id: $id, ')
          ..write('accountLogin: $accountLogin, ')
          ..write('encryptedToken: $encryptedToken, ')
          ..write('tokenNonce: $tokenNonce, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $PortForwardConfigsTable extends PortForwardConfigs
    with TableInfo<$PortForwardConfigsTable, PortForwardConfig> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PortForwardConfigsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
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
  static const VerificationMeta _bindHostMeta = const VerificationMeta(
    'bindHost',
  );
  @override
  late final GeneratedColumn<String> bindHost = GeneratedColumn<String>(
    'bind_host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bindPortMeta = const VerificationMeta(
    'bindPort',
  );
  @override
  late final GeneratedColumn<int> bindPort = GeneratedColumn<int>(
    'bind_port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetHostMeta = const VerificationMeta(
    'targetHost',
  );
  @override
  late final GeneratedColumn<String> targetHost = GeneratedColumn<String>(
    'target_host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetPortMeta = const VerificationMeta(
    'targetPort',
  );
  @override
  late final GeneratedColumn<int> targetPort = GeneratedColumn<int>(
    'target_port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _autoStartMeta = const VerificationMeta(
    'autoStart',
  );
  @override
  late final GeneratedColumn<bool> autoStart = GeneratedColumn<bool>(
    'auto_start',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_start" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverId,
    direction,
    kind,
    bindHost,
    bindPort,
    targetHost,
    targetPort,
    autoStart,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'port_forward_configs';
  @override
  VerificationContext validateIntegrity(
    Insertable<PortForwardConfig> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('bind_host')) {
      context.handle(
        _bindHostMeta,
        bindHost.isAcceptableOrUnknown(data['bind_host']!, _bindHostMeta),
      );
    } else if (isInserting) {
      context.missing(_bindHostMeta);
    }
    if (data.containsKey('bind_port')) {
      context.handle(
        _bindPortMeta,
        bindPort.isAcceptableOrUnknown(data['bind_port']!, _bindPortMeta),
      );
    } else if (isInserting) {
      context.missing(_bindPortMeta);
    }
    if (data.containsKey('target_host')) {
      context.handle(
        _targetHostMeta,
        targetHost.isAcceptableOrUnknown(data['target_host']!, _targetHostMeta),
      );
    } else if (isInserting) {
      context.missing(_targetHostMeta);
    }
    if (data.containsKey('target_port')) {
      context.handle(
        _targetPortMeta,
        targetPort.isAcceptableOrUnknown(data['target_port']!, _targetPortMeta),
      );
    } else if (isInserting) {
      context.missing(_targetPortMeta);
    }
    if (data.containsKey('auto_start')) {
      context.handle(
        _autoStartMeta,
        autoStart.isAcceptableOrUnknown(data['auto_start']!, _autoStartMeta),
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PortForwardConfig map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PortForwardConfig(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_id'],
      )!,
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      bindHost: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bind_host'],
      )!,
      bindPort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bind_port'],
      )!,
      targetHost: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_host'],
      )!,
      targetPort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_port'],
      )!,
      autoStart: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_start'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PortForwardConfigsTable createAlias(String alias) {
    return $PortForwardConfigsTable(attachedDatabase, alias);
  }
}

class PortForwardConfig extends DataClass
    implements Insertable<PortForwardConfig> {
  final int id;
  final int serverId;
  final String direction;
  final String kind;
  final String bindHost;
  final int bindPort;
  final String targetHost;
  final int targetPort;
  final bool autoStart;
  final DateTime createdAt;
  final DateTime updatedAt;
  const PortForwardConfig({
    required this.id,
    required this.serverId,
    required this.direction,
    required this.kind,
    required this.bindHost,
    required this.bindPort,
    required this.targetHost,
    required this.targetPort,
    required this.autoStart,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['server_id'] = Variable<int>(serverId);
    map['direction'] = Variable<String>(direction);
    map['kind'] = Variable<String>(kind);
    map['bind_host'] = Variable<String>(bindHost);
    map['bind_port'] = Variable<int>(bindPort);
    map['target_host'] = Variable<String>(targetHost);
    map['target_port'] = Variable<int>(targetPort);
    map['auto_start'] = Variable<bool>(autoStart);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PortForwardConfigsCompanion toCompanion(bool nullToAbsent) {
    return PortForwardConfigsCompanion(
      id: Value(id),
      serverId: Value(serverId),
      direction: Value(direction),
      kind: Value(kind),
      bindHost: Value(bindHost),
      bindPort: Value(bindPort),
      targetHost: Value(targetHost),
      targetPort: Value(targetPort),
      autoStart: Value(autoStart),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory PortForwardConfig.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PortForwardConfig(
      id: serializer.fromJson<int>(json['id']),
      serverId: serializer.fromJson<int>(json['serverId']),
      direction: serializer.fromJson<String>(json['direction']),
      kind: serializer.fromJson<String>(json['kind']),
      bindHost: serializer.fromJson<String>(json['bindHost']),
      bindPort: serializer.fromJson<int>(json['bindPort']),
      targetHost: serializer.fromJson<String>(json['targetHost']),
      targetPort: serializer.fromJson<int>(json['targetPort']),
      autoStart: serializer.fromJson<bool>(json['autoStart']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'serverId': serializer.toJson<int>(serverId),
      'direction': serializer.toJson<String>(direction),
      'kind': serializer.toJson<String>(kind),
      'bindHost': serializer.toJson<String>(bindHost),
      'bindPort': serializer.toJson<int>(bindPort),
      'targetHost': serializer.toJson<String>(targetHost),
      'targetPort': serializer.toJson<int>(targetPort),
      'autoStart': serializer.toJson<bool>(autoStart),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PortForwardConfig copyWith({
    int? id,
    int? serverId,
    String? direction,
    String? kind,
    String? bindHost,
    int? bindPort,
    String? targetHost,
    int? targetPort,
    bool? autoStart,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => PortForwardConfig(
    id: id ?? this.id,
    serverId: serverId ?? this.serverId,
    direction: direction ?? this.direction,
    kind: kind ?? this.kind,
    bindHost: bindHost ?? this.bindHost,
    bindPort: bindPort ?? this.bindPort,
    targetHost: targetHost ?? this.targetHost,
    targetPort: targetPort ?? this.targetPort,
    autoStart: autoStart ?? this.autoStart,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PortForwardConfig copyWithCompanion(PortForwardConfigsCompanion data) {
    return PortForwardConfig(
      id: data.id.present ? data.id.value : this.id,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      direction: data.direction.present ? data.direction.value : this.direction,
      kind: data.kind.present ? data.kind.value : this.kind,
      bindHost: data.bindHost.present ? data.bindHost.value : this.bindHost,
      bindPort: data.bindPort.present ? data.bindPort.value : this.bindPort,
      targetHost: data.targetHost.present
          ? data.targetHost.value
          : this.targetHost,
      targetPort: data.targetPort.present
          ? data.targetPort.value
          : this.targetPort,
      autoStart: data.autoStart.present ? data.autoStart.value : this.autoStart,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PortForwardConfig(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('direction: $direction, ')
          ..write('kind: $kind, ')
          ..write('bindHost: $bindHost, ')
          ..write('bindPort: $bindPort, ')
          ..write('targetHost: $targetHost, ')
          ..write('targetPort: $targetPort, ')
          ..write('autoStart: $autoStart, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    serverId,
    direction,
    kind,
    bindHost,
    bindPort,
    targetHost,
    targetPort,
    autoStart,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PortForwardConfig &&
          other.id == this.id &&
          other.serverId == this.serverId &&
          other.direction == this.direction &&
          other.kind == this.kind &&
          other.bindHost == this.bindHost &&
          other.bindPort == this.bindPort &&
          other.targetHost == this.targetHost &&
          other.targetPort == this.targetPort &&
          other.autoStart == this.autoStart &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PortForwardConfigsCompanion extends UpdateCompanion<PortForwardConfig> {
  final Value<int> id;
  final Value<int> serverId;
  final Value<String> direction;
  final Value<String> kind;
  final Value<String> bindHost;
  final Value<int> bindPort;
  final Value<String> targetHost;
  final Value<int> targetPort;
  final Value<bool> autoStart;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const PortForwardConfigsCompanion({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    this.direction = const Value.absent(),
    this.kind = const Value.absent(),
    this.bindHost = const Value.absent(),
    this.bindPort = const Value.absent(),
    this.targetHost = const Value.absent(),
    this.targetPort = const Value.absent(),
    this.autoStart = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  PortForwardConfigsCompanion.insert({
    this.id = const Value.absent(),
    required int serverId,
    required String direction,
    required String kind,
    required String bindHost,
    required int bindPort,
    required String targetHost,
    required int targetPort,
    this.autoStart = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : serverId = Value(serverId),
       direction = Value(direction),
       kind = Value(kind),
       bindHost = Value(bindHost),
       bindPort = Value(bindPort),
       targetHost = Value(targetHost),
       targetPort = Value(targetPort),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<PortForwardConfig> custom({
    Expression<int>? id,
    Expression<int>? serverId,
    Expression<String>? direction,
    Expression<String>? kind,
    Expression<String>? bindHost,
    Expression<int>? bindPort,
    Expression<String>? targetHost,
    Expression<int>? targetPort,
    Expression<bool>? autoStart,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      if (direction != null) 'direction': direction,
      if (kind != null) 'kind': kind,
      if (bindHost != null) 'bind_host': bindHost,
      if (bindPort != null) 'bind_port': bindPort,
      if (targetHost != null) 'target_host': targetHost,
      if (targetPort != null) 'target_port': targetPort,
      if (autoStart != null) 'auto_start': autoStart,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  PortForwardConfigsCompanion copyWith({
    Value<int>? id,
    Value<int>? serverId,
    Value<String>? direction,
    Value<String>? kind,
    Value<String>? bindHost,
    Value<int>? bindPort,
    Value<String>? targetHost,
    Value<int>? targetPort,
    Value<bool>? autoStart,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return PortForwardConfigsCompanion(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      direction: direction ?? this.direction,
      kind: kind ?? this.kind,
      bindHost: bindHost ?? this.bindHost,
      bindPort: bindPort ?? this.bindPort,
      targetHost: targetHost ?? this.targetHost,
      targetPort: targetPort ?? this.targetPort,
      autoStart: autoStart ?? this.autoStart,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (bindHost.present) {
      map['bind_host'] = Variable<String>(bindHost.value);
    }
    if (bindPort.present) {
      map['bind_port'] = Variable<int>(bindPort.value);
    }
    if (targetHost.present) {
      map['target_host'] = Variable<String>(targetHost.value);
    }
    if (targetPort.present) {
      map['target_port'] = Variable<int>(targetPort.value);
    }
    if (autoStart.present) {
      map['auto_start'] = Variable<bool>(autoStart.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PortForwardConfigsCompanion(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('direction: $direction, ')
          ..write('kind: $kind, ')
          ..write('bindHost: $bindHost, ')
          ..write('bindPort: $bindPort, ')
          ..write('targetHost: $targetHost, ')
          ..write('targetPort: $targetPort, ')
          ..write('autoStart: $autoStart, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $RuntimeWatchConfigsTable extends RuntimeWatchConfigs
    with TableInfo<$RuntimeWatchConfigsTable, RuntimeWatchConfig> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RuntimeWatchConfigsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _runtimeMeta = const VerificationMeta(
    'runtime',
  );
  @override
  late final GeneratedColumn<String> runtime = GeneratedColumn<String>(
    'runtime',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [serverId, runtime, enabled, pinned];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'runtime_watch_configs';
  @override
  VerificationContext validateIntegrity(
    Insertable<RuntimeWatchConfig> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('runtime')) {
      context.handle(
        _runtimeMeta,
        runtime.isAcceptableOrUnknown(data['runtime']!, _runtimeMeta),
      );
    } else if (isInserting) {
      context.missing(_runtimeMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {serverId, runtime};
  @override
  RuntimeWatchConfig map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RuntimeWatchConfig(
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_id'],
      )!,
      runtime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}runtime'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
    );
  }

  @override
  $RuntimeWatchConfigsTable createAlias(String alias) {
    return $RuntimeWatchConfigsTable(attachedDatabase, alias);
  }
}

class RuntimeWatchConfig extends DataClass
    implements Insertable<RuntimeWatchConfig> {
  final int serverId;
  final String runtime;
  final bool enabled;
  final bool pinned;
  const RuntimeWatchConfig({
    required this.serverId,
    required this.runtime,
    required this.enabled,
    required this.pinned,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['server_id'] = Variable<int>(serverId);
    map['runtime'] = Variable<String>(runtime);
    map['enabled'] = Variable<bool>(enabled);
    map['pinned'] = Variable<bool>(pinned);
    return map;
  }

  RuntimeWatchConfigsCompanion toCompanion(bool nullToAbsent) {
    return RuntimeWatchConfigsCompanion(
      serverId: Value(serverId),
      runtime: Value(runtime),
      enabled: Value(enabled),
      pinned: Value(pinned),
    );
  }

  factory RuntimeWatchConfig.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RuntimeWatchConfig(
      serverId: serializer.fromJson<int>(json['serverId']),
      runtime: serializer.fromJson<String>(json['runtime']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      pinned: serializer.fromJson<bool>(json['pinned']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'serverId': serializer.toJson<int>(serverId),
      'runtime': serializer.toJson<String>(runtime),
      'enabled': serializer.toJson<bool>(enabled),
      'pinned': serializer.toJson<bool>(pinned),
    };
  }

  RuntimeWatchConfig copyWith({
    int? serverId,
    String? runtime,
    bool? enabled,
    bool? pinned,
  }) => RuntimeWatchConfig(
    serverId: serverId ?? this.serverId,
    runtime: runtime ?? this.runtime,
    enabled: enabled ?? this.enabled,
    pinned: pinned ?? this.pinned,
  );
  RuntimeWatchConfig copyWithCompanion(RuntimeWatchConfigsCompanion data) {
    return RuntimeWatchConfig(
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      runtime: data.runtime.present ? data.runtime.value : this.runtime,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RuntimeWatchConfig(')
          ..write('serverId: $serverId, ')
          ..write('runtime: $runtime, ')
          ..write('enabled: $enabled, ')
          ..write('pinned: $pinned')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(serverId, runtime, enabled, pinned);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RuntimeWatchConfig &&
          other.serverId == this.serverId &&
          other.runtime == this.runtime &&
          other.enabled == this.enabled &&
          other.pinned == this.pinned);
}

class RuntimeWatchConfigsCompanion extends UpdateCompanion<RuntimeWatchConfig> {
  final Value<int> serverId;
  final Value<String> runtime;
  final Value<bool> enabled;
  final Value<bool> pinned;
  final Value<int> rowid;
  const RuntimeWatchConfigsCompanion({
    this.serverId = const Value.absent(),
    this.runtime = const Value.absent(),
    this.enabled = const Value.absent(),
    this.pinned = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RuntimeWatchConfigsCompanion.insert({
    required int serverId,
    required String runtime,
    this.enabled = const Value.absent(),
    this.pinned = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : serverId = Value(serverId),
       runtime = Value(runtime);
  static Insertable<RuntimeWatchConfig> custom({
    Expression<int>? serverId,
    Expression<String>? runtime,
    Expression<bool>? enabled,
    Expression<bool>? pinned,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (serverId != null) 'server_id': serverId,
      if (runtime != null) 'runtime': runtime,
      if (enabled != null) 'enabled': enabled,
      if (pinned != null) 'pinned': pinned,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RuntimeWatchConfigsCompanion copyWith({
    Value<int>? serverId,
    Value<String>? runtime,
    Value<bool>? enabled,
    Value<bool>? pinned,
    Value<int>? rowid,
  }) {
    return RuntimeWatchConfigsCompanion(
      serverId: serverId ?? this.serverId,
      runtime: runtime ?? this.runtime,
      enabled: enabled ?? this.enabled,
      pinned: pinned ?? this.pinned,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (runtime.present) {
      map['runtime'] = Variable<String>(runtime.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RuntimeWatchConfigsCompanion(')
          ..write('serverId: $serverId, ')
          ..write('runtime: $runtime, ')
          ..write('enabled: $enabled, ')
          ..write('pinned: $pinned, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
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
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
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
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  const AppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
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

  AppSetting copyWith({String? key, String? value}) =>
      AppSetting(key: key ?? this.key, value: value ?? this.value);
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
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
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSetting> custom({
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

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
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
    return (StringBuffer('AppSettingsCompanion(')
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
  late final $ServersTable servers = $ServersTable(this);
  late final $SavedCredentialsTable savedCredentials = $SavedCredentialsTable(
    this,
  );
  late final $VaultMetadataTable vaultMetadata = $VaultMetadataTable(this);
  late final $ComposeProjectLinksTable composeProjectLinks =
      $ComposeProjectLinksTable(this);
  late final $ContainerCacheEntriesTable containerCacheEntries =
      $ContainerCacheEntriesTable(this);
  late final $DeploymentProjectsTable deploymentProjects =
      $DeploymentProjectsTable(this);
  late final $DeploymentResourcesTable deploymentResources =
      $DeploymentResourcesTable(this);
  late final $ScriptSnippetsTable scriptSnippets = $ScriptSnippetsTable(this);
  late final $AgentSettingsTable agentSettings = $AgentSettingsTable(this);
  late final $AgentProvidersTable agentProviders = $AgentProvidersTable(this);
  late final $AgentProviderModelsTable agentProviderModels =
      $AgentProviderModelsTable(this);
  late final $McpServersTable mcpServers = $McpServersTable(this);
  late final $AgentSkillsTable agentSkills = $AgentSkillsTable(this);
  late final $GitHubConnectionsTable gitHubConnections =
      $GitHubConnectionsTable(this);
  late final $GitHubRepoPinsTable gitHubRepoPins = $GitHubRepoPinsTable(this);
  late final $GitHubTokensTable gitHubTokens = $GitHubTokensTable(this);
  late final $PortForwardConfigsTable portForwardConfigs =
      $PortForwardConfigsTable(this);
  late final $RuntimeWatchConfigsTable runtimeWatchConfigs =
      $RuntimeWatchConfigsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    servers,
    savedCredentials,
    vaultMetadata,
    composeProjectLinks,
    containerCacheEntries,
    deploymentProjects,
    deploymentResources,
    scriptSnippets,
    agentSettings,
    agentProviders,
    agentProviderModels,
    mcpServers,
    agentSkills,
    gitHubConnections,
    gitHubRepoPins,
    gitHubTokens,
    portForwardConfigs,
    runtimeWatchConfigs,
    appSettings,
  ];
}

typedef $$ServersTableCreateCompanionBuilder =
    ServersCompanion Function({
      Value<int> id,
      required String name,
      required String host,
      Value<int> port,
      required String username,
      Value<DateTime?> lastConnectedAt,
      Value<String?> syncId,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String?> credentialType,
      Value<String?> encryptedCredential,
      Value<String?> credentialNonce,
      Value<int?> credentialId,
      Value<String?> hostKeyAlgorithm,
      Value<String?> hostKeyFingerprint,
      Value<bool> collectStats,
      Value<bool> collectSystemInfo,
      Value<String?> proxyType,
      Value<String?> proxyHost,
      Value<int?> proxyPort,
      Value<String?> proxyUsername,
      Value<String?> encryptedProxyPassword,
      Value<String?> proxyPasswordNonce,
      Value<int?> jumpHostServerId,
      Value<String?> environment,
      Value<String?> initialSnippets,
      Value<String?> tags,
      Value<String> connectionType,
      Value<String?> serialConfig,
      Value<String?> maidCafeDaemonUrl,
      Value<String?> encryptedMaidCafeWebhookSecret,
      Value<String?> maidCafeWebhookSecretNonce,
      Value<String?> encryptedMaidCafeMetricsSecret,
      Value<String?> maidCafeMetricsSecretNonce,
      Value<int?> sortOrder,
      Value<String?> fileManagementInitialPath,
      Value<String?> fileManagementFavorites,
    });
typedef $$ServersTableUpdateCompanionBuilder =
    ServersCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> host,
      Value<int> port,
      Value<String> username,
      Value<DateTime?> lastConnectedAt,
      Value<String?> syncId,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String?> credentialType,
      Value<String?> encryptedCredential,
      Value<String?> credentialNonce,
      Value<int?> credentialId,
      Value<String?> hostKeyAlgorithm,
      Value<String?> hostKeyFingerprint,
      Value<bool> collectStats,
      Value<bool> collectSystemInfo,
      Value<String?> proxyType,
      Value<String?> proxyHost,
      Value<int?> proxyPort,
      Value<String?> proxyUsername,
      Value<String?> encryptedProxyPassword,
      Value<String?> proxyPasswordNonce,
      Value<int?> jumpHostServerId,
      Value<String?> environment,
      Value<String?> initialSnippets,
      Value<String?> tags,
      Value<String> connectionType,
      Value<String?> serialConfig,
      Value<String?> maidCafeDaemonUrl,
      Value<String?> encryptedMaidCafeWebhookSecret,
      Value<String?> maidCafeWebhookSecretNonce,
      Value<String?> encryptedMaidCafeMetricsSecret,
      Value<String?> maidCafeMetricsSecretNonce,
      Value<int?> sortOrder,
      Value<String?> fileManagementInitialPath,
      Value<String?> fileManagementFavorites,
    });

class $$ServersTableFilterComposer
    extends Composer<_$AppDatabase, $ServersTable> {
  $$ServersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get credentialType => $composableBuilder(
    column: $table.credentialType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedCredential => $composableBuilder(
    column: $table.encryptedCredential,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get credentialNonce => $composableBuilder(
    column: $table.credentialNonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get credentialId => $composableBuilder(
    column: $table.credentialId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostKeyAlgorithm => $composableBuilder(
    column: $table.hostKeyAlgorithm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostKeyFingerprint => $composableBuilder(
    column: $table.hostKeyFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get collectStats => $composableBuilder(
    column: $table.collectStats,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get collectSystemInfo => $composableBuilder(
    column: $table.collectSystemInfo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get proxyType => $composableBuilder(
    column: $table.proxyType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get proxyHost => $composableBuilder(
    column: $table.proxyHost,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get proxyPort => $composableBuilder(
    column: $table.proxyPort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get proxyUsername => $composableBuilder(
    column: $table.proxyUsername,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedProxyPassword => $composableBuilder(
    column: $table.encryptedProxyPassword,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get proxyPasswordNonce => $composableBuilder(
    column: $table.proxyPasswordNonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get jumpHostServerId => $composableBuilder(
    column: $table.jumpHostServerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get environment => $composableBuilder(
    column: $table.environment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get initialSnippets => $composableBuilder(
    column: $table.initialSnippets,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get connectionType => $composableBuilder(
    column: $table.connectionType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serialConfig => $composableBuilder(
    column: $table.serialConfig,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get maidCafeDaemonUrl => $composableBuilder(
    column: $table.maidCafeDaemonUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedMaidCafeWebhookSecret =>
      $composableBuilder(
        column: $table.encryptedMaidCafeWebhookSecret,
        builder: (column) => ColumnFilters(column),
      );

  ColumnFilters<String> get maidCafeWebhookSecretNonce => $composableBuilder(
    column: $table.maidCafeWebhookSecretNonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedMaidCafeMetricsSecret =>
      $composableBuilder(
        column: $table.encryptedMaidCafeMetricsSecret,
        builder: (column) => ColumnFilters(column),
      );

  ColumnFilters<String> get maidCafeMetricsSecretNonce => $composableBuilder(
    column: $table.maidCafeMetricsSecretNonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileManagementInitialPath => $composableBuilder(
    column: $table.fileManagementInitialPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileManagementFavorites => $composableBuilder(
    column: $table.fileManagementFavorites,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ServersTableOrderingComposer
    extends Composer<_$AppDatabase, $ServersTable> {
  $$ServersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get credentialType => $composableBuilder(
    column: $table.credentialType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedCredential => $composableBuilder(
    column: $table.encryptedCredential,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get credentialNonce => $composableBuilder(
    column: $table.credentialNonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get credentialId => $composableBuilder(
    column: $table.credentialId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostKeyAlgorithm => $composableBuilder(
    column: $table.hostKeyAlgorithm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostKeyFingerprint => $composableBuilder(
    column: $table.hostKeyFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get collectStats => $composableBuilder(
    column: $table.collectStats,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get collectSystemInfo => $composableBuilder(
    column: $table.collectSystemInfo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get proxyType => $composableBuilder(
    column: $table.proxyType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get proxyHost => $composableBuilder(
    column: $table.proxyHost,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get proxyPort => $composableBuilder(
    column: $table.proxyPort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get proxyUsername => $composableBuilder(
    column: $table.proxyUsername,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedProxyPassword => $composableBuilder(
    column: $table.encryptedProxyPassword,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get proxyPasswordNonce => $composableBuilder(
    column: $table.proxyPasswordNonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get jumpHostServerId => $composableBuilder(
    column: $table.jumpHostServerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get environment => $composableBuilder(
    column: $table.environment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get initialSnippets => $composableBuilder(
    column: $table.initialSnippets,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get connectionType => $composableBuilder(
    column: $table.connectionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serialConfig => $composableBuilder(
    column: $table.serialConfig,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get maidCafeDaemonUrl => $composableBuilder(
    column: $table.maidCafeDaemonUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedMaidCafeWebhookSecret =>
      $composableBuilder(
        column: $table.encryptedMaidCafeWebhookSecret,
        builder: (column) => ColumnOrderings(column),
      );

  ColumnOrderings<String> get maidCafeWebhookSecretNonce => $composableBuilder(
    column: $table.maidCafeWebhookSecretNonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedMaidCafeMetricsSecret =>
      $composableBuilder(
        column: $table.encryptedMaidCafeMetricsSecret,
        builder: (column) => ColumnOrderings(column),
      );

  ColumnOrderings<String> get maidCafeMetricsSecretNonce => $composableBuilder(
    column: $table.maidCafeMetricsSecretNonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileManagementInitialPath => $composableBuilder(
    column: $table.fileManagementInitialPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileManagementFavorites => $composableBuilder(
    column: $table.fileManagementFavorites,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ServersTableAnnotationComposer
    extends Composer<_$AppDatabase, $ServersTable> {
  $$ServersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<DateTime> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get credentialType => $composableBuilder(
    column: $table.credentialType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get encryptedCredential => $composableBuilder(
    column: $table.encryptedCredential,
    builder: (column) => column,
  );

  GeneratedColumn<String> get credentialNonce => $composableBuilder(
    column: $table.credentialNonce,
    builder: (column) => column,
  );

  GeneratedColumn<int> get credentialId => $composableBuilder(
    column: $table.credentialId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hostKeyAlgorithm => $composableBuilder(
    column: $table.hostKeyAlgorithm,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hostKeyFingerprint => $composableBuilder(
    column: $table.hostKeyFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get collectStats => $composableBuilder(
    column: $table.collectStats,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get collectSystemInfo => $composableBuilder(
    column: $table.collectSystemInfo,
    builder: (column) => column,
  );

  GeneratedColumn<String> get proxyType =>
      $composableBuilder(column: $table.proxyType, builder: (column) => column);

  GeneratedColumn<String> get proxyHost =>
      $composableBuilder(column: $table.proxyHost, builder: (column) => column);

  GeneratedColumn<int> get proxyPort =>
      $composableBuilder(column: $table.proxyPort, builder: (column) => column);

  GeneratedColumn<String> get proxyUsername => $composableBuilder(
    column: $table.proxyUsername,
    builder: (column) => column,
  );

  GeneratedColumn<String> get encryptedProxyPassword => $composableBuilder(
    column: $table.encryptedProxyPassword,
    builder: (column) => column,
  );

  GeneratedColumn<String> get proxyPasswordNonce => $composableBuilder(
    column: $table.proxyPasswordNonce,
    builder: (column) => column,
  );

  GeneratedColumn<int> get jumpHostServerId => $composableBuilder(
    column: $table.jumpHostServerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get environment => $composableBuilder(
    column: $table.environment,
    builder: (column) => column,
  );

  GeneratedColumn<String> get initialSnippets => $composableBuilder(
    column: $table.initialSnippets,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<String> get connectionType => $composableBuilder(
    column: $table.connectionType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get serialConfig => $composableBuilder(
    column: $table.serialConfig,
    builder: (column) => column,
  );

  GeneratedColumn<String> get maidCafeDaemonUrl => $composableBuilder(
    column: $table.maidCafeDaemonUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get encryptedMaidCafeWebhookSecret =>
      $composableBuilder(
        column: $table.encryptedMaidCafeWebhookSecret,
        builder: (column) => column,
      );

  GeneratedColumn<String> get maidCafeWebhookSecretNonce => $composableBuilder(
    column: $table.maidCafeWebhookSecretNonce,
    builder: (column) => column,
  );

  GeneratedColumn<String> get encryptedMaidCafeMetricsSecret =>
      $composableBuilder(
        column: $table.encryptedMaidCafeMetricsSecret,
        builder: (column) => column,
      );

  GeneratedColumn<String> get maidCafeMetricsSecretNonce => $composableBuilder(
    column: $table.maidCafeMetricsSecretNonce,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get fileManagementInitialPath => $composableBuilder(
    column: $table.fileManagementInitialPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fileManagementFavorites => $composableBuilder(
    column: $table.fileManagementFavorites,
    builder: (column) => column,
  );
}

class $$ServersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ServersTable,
          Server,
          $$ServersTableFilterComposer,
          $$ServersTableOrderingComposer,
          $$ServersTableAnnotationComposer,
          $$ServersTableCreateCompanionBuilder,
          $$ServersTableUpdateCompanionBuilder,
          (Server, BaseReferences<_$AppDatabase, $ServersTable, Server>),
          Server,
          PrefetchHooks Function()
        > {
  $$ServersTableTableManager(_$AppDatabase db, $ServersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ServersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ServersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ServersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<DateTime?> lastConnectedAt = const Value.absent(),
                Value<String?> syncId = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String?> credentialType = const Value.absent(),
                Value<String?> encryptedCredential = const Value.absent(),
                Value<String?> credentialNonce = const Value.absent(),
                Value<int?> credentialId = const Value.absent(),
                Value<String?> hostKeyAlgorithm = const Value.absent(),
                Value<String?> hostKeyFingerprint = const Value.absent(),
                Value<bool> collectStats = const Value.absent(),
                Value<bool> collectSystemInfo = const Value.absent(),
                Value<String?> proxyType = const Value.absent(),
                Value<String?> proxyHost = const Value.absent(),
                Value<int?> proxyPort = const Value.absent(),
                Value<String?> proxyUsername = const Value.absent(),
                Value<String?> encryptedProxyPassword = const Value.absent(),
                Value<String?> proxyPasswordNonce = const Value.absent(),
                Value<int?> jumpHostServerId = const Value.absent(),
                Value<String?> environment = const Value.absent(),
                Value<String?> initialSnippets = const Value.absent(),
                Value<String?> tags = const Value.absent(),
                Value<String> connectionType = const Value.absent(),
                Value<String?> serialConfig = const Value.absent(),
                Value<String?> maidCafeDaemonUrl = const Value.absent(),
                Value<String?> encryptedMaidCafeWebhookSecret =
                    const Value.absent(),
                Value<String?> maidCafeWebhookSecretNonce =
                    const Value.absent(),
                Value<String?> encryptedMaidCafeMetricsSecret =
                    const Value.absent(),
                Value<String?> maidCafeMetricsSecretNonce =
                    const Value.absent(),
                Value<int?> sortOrder = const Value.absent(),
                Value<String?> fileManagementInitialPath = const Value.absent(),
                Value<String?> fileManagementFavorites = const Value.absent(),
              }) => ServersCompanion(
                id: id,
                name: name,
                host: host,
                port: port,
                username: username,
                lastConnectedAt: lastConnectedAt,
                syncId: syncId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                credentialType: credentialType,
                encryptedCredential: encryptedCredential,
                credentialNonce: credentialNonce,
                credentialId: credentialId,
                hostKeyAlgorithm: hostKeyAlgorithm,
                hostKeyFingerprint: hostKeyFingerprint,
                collectStats: collectStats,
                collectSystemInfo: collectSystemInfo,
                proxyType: proxyType,
                proxyHost: proxyHost,
                proxyPort: proxyPort,
                proxyUsername: proxyUsername,
                encryptedProxyPassword: encryptedProxyPassword,
                proxyPasswordNonce: proxyPasswordNonce,
                jumpHostServerId: jumpHostServerId,
                environment: environment,
                initialSnippets: initialSnippets,
                tags: tags,
                connectionType: connectionType,
                serialConfig: serialConfig,
                maidCafeDaemonUrl: maidCafeDaemonUrl,
                encryptedMaidCafeWebhookSecret: encryptedMaidCafeWebhookSecret,
                maidCafeWebhookSecretNonce: maidCafeWebhookSecretNonce,
                encryptedMaidCafeMetricsSecret: encryptedMaidCafeMetricsSecret,
                maidCafeMetricsSecretNonce: maidCafeMetricsSecretNonce,
                sortOrder: sortOrder,
                fileManagementInitialPath: fileManagementInitialPath,
                fileManagementFavorites: fileManagementFavorites,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String host,
                Value<int> port = const Value.absent(),
                required String username,
                Value<DateTime?> lastConnectedAt = const Value.absent(),
                Value<String?> syncId = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String?> credentialType = const Value.absent(),
                Value<String?> encryptedCredential = const Value.absent(),
                Value<String?> credentialNonce = const Value.absent(),
                Value<int?> credentialId = const Value.absent(),
                Value<String?> hostKeyAlgorithm = const Value.absent(),
                Value<String?> hostKeyFingerprint = const Value.absent(),
                Value<bool> collectStats = const Value.absent(),
                Value<bool> collectSystemInfo = const Value.absent(),
                Value<String?> proxyType = const Value.absent(),
                Value<String?> proxyHost = const Value.absent(),
                Value<int?> proxyPort = const Value.absent(),
                Value<String?> proxyUsername = const Value.absent(),
                Value<String?> encryptedProxyPassword = const Value.absent(),
                Value<String?> proxyPasswordNonce = const Value.absent(),
                Value<int?> jumpHostServerId = const Value.absent(),
                Value<String?> environment = const Value.absent(),
                Value<String?> initialSnippets = const Value.absent(),
                Value<String?> tags = const Value.absent(),
                Value<String> connectionType = const Value.absent(),
                Value<String?> serialConfig = const Value.absent(),
                Value<String?> maidCafeDaemonUrl = const Value.absent(),
                Value<String?> encryptedMaidCafeWebhookSecret =
                    const Value.absent(),
                Value<String?> maidCafeWebhookSecretNonce =
                    const Value.absent(),
                Value<String?> encryptedMaidCafeMetricsSecret =
                    const Value.absent(),
                Value<String?> maidCafeMetricsSecretNonce =
                    const Value.absent(),
                Value<int?> sortOrder = const Value.absent(),
                Value<String?> fileManagementInitialPath = const Value.absent(),
                Value<String?> fileManagementFavorites = const Value.absent(),
              }) => ServersCompanion.insert(
                id: id,
                name: name,
                host: host,
                port: port,
                username: username,
                lastConnectedAt: lastConnectedAt,
                syncId: syncId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                credentialType: credentialType,
                encryptedCredential: encryptedCredential,
                credentialNonce: credentialNonce,
                credentialId: credentialId,
                hostKeyAlgorithm: hostKeyAlgorithm,
                hostKeyFingerprint: hostKeyFingerprint,
                collectStats: collectStats,
                collectSystemInfo: collectSystemInfo,
                proxyType: proxyType,
                proxyHost: proxyHost,
                proxyPort: proxyPort,
                proxyUsername: proxyUsername,
                encryptedProxyPassword: encryptedProxyPassword,
                proxyPasswordNonce: proxyPasswordNonce,
                jumpHostServerId: jumpHostServerId,
                environment: environment,
                initialSnippets: initialSnippets,
                tags: tags,
                connectionType: connectionType,
                serialConfig: serialConfig,
                maidCafeDaemonUrl: maidCafeDaemonUrl,
                encryptedMaidCafeWebhookSecret: encryptedMaidCafeWebhookSecret,
                maidCafeWebhookSecretNonce: maidCafeWebhookSecretNonce,
                encryptedMaidCafeMetricsSecret: encryptedMaidCafeMetricsSecret,
                maidCafeMetricsSecretNonce: maidCafeMetricsSecretNonce,
                sortOrder: sortOrder,
                fileManagementInitialPath: fileManagementInitialPath,
                fileManagementFavorites: fileManagementFavorites,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ServersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ServersTable,
      Server,
      $$ServersTableFilterComposer,
      $$ServersTableOrderingComposer,
      $$ServersTableAnnotationComposer,
      $$ServersTableCreateCompanionBuilder,
      $$ServersTableUpdateCompanionBuilder,
      (Server, BaseReferences<_$AppDatabase, $ServersTable, Server>),
      Server,
      PrefetchHooks Function()
    >;
typedef $$SavedCredentialsTableCreateCompanionBuilder =
    SavedCredentialsCompanion Function({
      Value<int> id,
      required String name,
      required String credentialType,
      required String encryptedCredential,
      required String credentialNonce,
      required DateTime createdAt,
      required DateTime updatedAt,
    });
typedef $$SavedCredentialsTableUpdateCompanionBuilder =
    SavedCredentialsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> credentialType,
      Value<String> encryptedCredential,
      Value<String> credentialNonce,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$SavedCredentialsTableFilterComposer
    extends Composer<_$AppDatabase, $SavedCredentialsTable> {
  $$SavedCredentialsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get credentialType => $composableBuilder(
    column: $table.credentialType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedCredential => $composableBuilder(
    column: $table.encryptedCredential,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get credentialNonce => $composableBuilder(
    column: $table.credentialNonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavedCredentialsTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedCredentialsTable> {
  $$SavedCredentialsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get credentialType => $composableBuilder(
    column: $table.credentialType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedCredential => $composableBuilder(
    column: $table.encryptedCredential,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get credentialNonce => $composableBuilder(
    column: $table.credentialNonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavedCredentialsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedCredentialsTable> {
  $$SavedCredentialsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get credentialType => $composableBuilder(
    column: $table.credentialType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get encryptedCredential => $composableBuilder(
    column: $table.encryptedCredential,
    builder: (column) => column,
  );

  GeneratedColumn<String> get credentialNonce => $composableBuilder(
    column: $table.credentialNonce,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SavedCredentialsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SavedCredentialsTable,
          SavedCredential,
          $$SavedCredentialsTableFilterComposer,
          $$SavedCredentialsTableOrderingComposer,
          $$SavedCredentialsTableAnnotationComposer,
          $$SavedCredentialsTableCreateCompanionBuilder,
          $$SavedCredentialsTableUpdateCompanionBuilder,
          (
            SavedCredential,
            BaseReferences<
              _$AppDatabase,
              $SavedCredentialsTable,
              SavedCredential
            >,
          ),
          SavedCredential,
          PrefetchHooks Function()
        > {
  $$SavedCredentialsTableTableManager(
    _$AppDatabase db,
    $SavedCredentialsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedCredentialsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedCredentialsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedCredentialsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> credentialType = const Value.absent(),
                Value<String> encryptedCredential = const Value.absent(),
                Value<String> credentialNonce = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => SavedCredentialsCompanion(
                id: id,
                name: name,
                credentialType: credentialType,
                encryptedCredential: encryptedCredential,
                credentialNonce: credentialNonce,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String credentialType,
                required String encryptedCredential,
                required String credentialNonce,
                required DateTime createdAt,
                required DateTime updatedAt,
              }) => SavedCredentialsCompanion.insert(
                id: id,
                name: name,
                credentialType: credentialType,
                encryptedCredential: encryptedCredential,
                credentialNonce: credentialNonce,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavedCredentialsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SavedCredentialsTable,
      SavedCredential,
      $$SavedCredentialsTableFilterComposer,
      $$SavedCredentialsTableOrderingComposer,
      $$SavedCredentialsTableAnnotationComposer,
      $$SavedCredentialsTableCreateCompanionBuilder,
      $$SavedCredentialsTableUpdateCompanionBuilder,
      (
        SavedCredential,
        BaseReferences<_$AppDatabase, $SavedCredentialsTable, SavedCredential>,
      ),
      SavedCredential,
      PrefetchHooks Function()
    >;
typedef $$VaultMetadataTableCreateCompanionBuilder =
    VaultMetadataCompanion Function({
      Value<int> id,
      required int formatVersion,
      required String salt,
      required String wrappedDataKey,
      required String wrappedDataKeyNonce,
      required String verifier,
      required String verifierNonce,
      Value<String?> syncPassphraseCiphertext,
      Value<String?> syncPassphraseNonce,
      Value<String?> encryptedTailscaleAuthKey,
      Value<String?> tailscaleAuthKeyNonce,
      required DateTime createdAt,
    });
typedef $$VaultMetadataTableUpdateCompanionBuilder =
    VaultMetadataCompanion Function({
      Value<int> id,
      Value<int> formatVersion,
      Value<String> salt,
      Value<String> wrappedDataKey,
      Value<String> wrappedDataKeyNonce,
      Value<String> verifier,
      Value<String> verifierNonce,
      Value<String?> syncPassphraseCiphertext,
      Value<String?> syncPassphraseNonce,
      Value<String?> encryptedTailscaleAuthKey,
      Value<String?> tailscaleAuthKeyNonce,
      Value<DateTime> createdAt,
    });

class $$VaultMetadataTableFilterComposer
    extends Composer<_$AppDatabase, $VaultMetadataTable> {
  $$VaultMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get formatVersion => $composableBuilder(
    column: $table.formatVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get salt => $composableBuilder(
    column: $table.salt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wrappedDataKey => $composableBuilder(
    column: $table.wrappedDataKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wrappedDataKeyNonce => $composableBuilder(
    column: $table.wrappedDataKeyNonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get verifier => $composableBuilder(
    column: $table.verifier,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get verifierNonce => $composableBuilder(
    column: $table.verifierNonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncPassphraseCiphertext => $composableBuilder(
    column: $table.syncPassphraseCiphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncPassphraseNonce => $composableBuilder(
    column: $table.syncPassphraseNonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedTailscaleAuthKey => $composableBuilder(
    column: $table.encryptedTailscaleAuthKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tailscaleAuthKeyNonce => $composableBuilder(
    column: $table.tailscaleAuthKeyNonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VaultMetadataTableOrderingComposer
    extends Composer<_$AppDatabase, $VaultMetadataTable> {
  $$VaultMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get formatVersion => $composableBuilder(
    column: $table.formatVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get salt => $composableBuilder(
    column: $table.salt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wrappedDataKey => $composableBuilder(
    column: $table.wrappedDataKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wrappedDataKeyNonce => $composableBuilder(
    column: $table.wrappedDataKeyNonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get verifier => $composableBuilder(
    column: $table.verifier,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get verifierNonce => $composableBuilder(
    column: $table.verifierNonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncPassphraseCiphertext => $composableBuilder(
    column: $table.syncPassphraseCiphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncPassphraseNonce => $composableBuilder(
    column: $table.syncPassphraseNonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedTailscaleAuthKey => $composableBuilder(
    column: $table.encryptedTailscaleAuthKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tailscaleAuthKeyNonce => $composableBuilder(
    column: $table.tailscaleAuthKeyNonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VaultMetadataTableAnnotationComposer
    extends Composer<_$AppDatabase, $VaultMetadataTable> {
  $$VaultMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get formatVersion => $composableBuilder(
    column: $table.formatVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get salt =>
      $composableBuilder(column: $table.salt, builder: (column) => column);

  GeneratedColumn<String> get wrappedDataKey => $composableBuilder(
    column: $table.wrappedDataKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get wrappedDataKeyNonce => $composableBuilder(
    column: $table.wrappedDataKeyNonce,
    builder: (column) => column,
  );

  GeneratedColumn<String> get verifier =>
      $composableBuilder(column: $table.verifier, builder: (column) => column);

  GeneratedColumn<String> get verifierNonce => $composableBuilder(
    column: $table.verifierNonce,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncPassphraseCiphertext => $composableBuilder(
    column: $table.syncPassphraseCiphertext,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncPassphraseNonce => $composableBuilder(
    column: $table.syncPassphraseNonce,
    builder: (column) => column,
  );

  GeneratedColumn<String> get encryptedTailscaleAuthKey => $composableBuilder(
    column: $table.encryptedTailscaleAuthKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tailscaleAuthKeyNonce => $composableBuilder(
    column: $table.tailscaleAuthKeyNonce,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$VaultMetadataTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VaultMetadataTable,
          VaultMetadataData,
          $$VaultMetadataTableFilterComposer,
          $$VaultMetadataTableOrderingComposer,
          $$VaultMetadataTableAnnotationComposer,
          $$VaultMetadataTableCreateCompanionBuilder,
          $$VaultMetadataTableUpdateCompanionBuilder,
          (
            VaultMetadataData,
            BaseReferences<
              _$AppDatabase,
              $VaultMetadataTable,
              VaultMetadataData
            >,
          ),
          VaultMetadataData,
          PrefetchHooks Function()
        > {
  $$VaultMetadataTableTableManager(_$AppDatabase db, $VaultMetadataTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VaultMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VaultMetadataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VaultMetadataTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> formatVersion = const Value.absent(),
                Value<String> salt = const Value.absent(),
                Value<String> wrappedDataKey = const Value.absent(),
                Value<String> wrappedDataKeyNonce = const Value.absent(),
                Value<String> verifier = const Value.absent(),
                Value<String> verifierNonce = const Value.absent(),
                Value<String?> syncPassphraseCiphertext = const Value.absent(),
                Value<String?> syncPassphraseNonce = const Value.absent(),
                Value<String?> encryptedTailscaleAuthKey = const Value.absent(),
                Value<String?> tailscaleAuthKeyNonce = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => VaultMetadataCompanion(
                id: id,
                formatVersion: formatVersion,
                salt: salt,
                wrappedDataKey: wrappedDataKey,
                wrappedDataKeyNonce: wrappedDataKeyNonce,
                verifier: verifier,
                verifierNonce: verifierNonce,
                syncPassphraseCiphertext: syncPassphraseCiphertext,
                syncPassphraseNonce: syncPassphraseNonce,
                encryptedTailscaleAuthKey: encryptedTailscaleAuthKey,
                tailscaleAuthKeyNonce: tailscaleAuthKeyNonce,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int formatVersion,
                required String salt,
                required String wrappedDataKey,
                required String wrappedDataKeyNonce,
                required String verifier,
                required String verifierNonce,
                Value<String?> syncPassphraseCiphertext = const Value.absent(),
                Value<String?> syncPassphraseNonce = const Value.absent(),
                Value<String?> encryptedTailscaleAuthKey = const Value.absent(),
                Value<String?> tailscaleAuthKeyNonce = const Value.absent(),
                required DateTime createdAt,
              }) => VaultMetadataCompanion.insert(
                id: id,
                formatVersion: formatVersion,
                salt: salt,
                wrappedDataKey: wrappedDataKey,
                wrappedDataKeyNonce: wrappedDataKeyNonce,
                verifier: verifier,
                verifierNonce: verifierNonce,
                syncPassphraseCiphertext: syncPassphraseCiphertext,
                syncPassphraseNonce: syncPassphraseNonce,
                encryptedTailscaleAuthKey: encryptedTailscaleAuthKey,
                tailscaleAuthKeyNonce: tailscaleAuthKeyNonce,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VaultMetadataTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VaultMetadataTable,
      VaultMetadataData,
      $$VaultMetadataTableFilterComposer,
      $$VaultMetadataTableOrderingComposer,
      $$VaultMetadataTableAnnotationComposer,
      $$VaultMetadataTableCreateCompanionBuilder,
      $$VaultMetadataTableUpdateCompanionBuilder,
      (
        VaultMetadataData,
        BaseReferences<_$AppDatabase, $VaultMetadataTable, VaultMetadataData>,
      ),
      VaultMetadataData,
      PrefetchHooks Function()
    >;
typedef $$ComposeProjectLinksTableCreateCompanionBuilder =
    ComposeProjectLinksCompanion Function({
      Value<int> id,
      required int serverId,
      required String name,
      required String directory,
      required String runtime,
      required String scope,
      required DateTime linkedAt,
    });
typedef $$ComposeProjectLinksTableUpdateCompanionBuilder =
    ComposeProjectLinksCompanion Function({
      Value<int> id,
      Value<int> serverId,
      Value<String> name,
      Value<String> directory,
      Value<String> runtime,
      Value<String> scope,
      Value<DateTime> linkedAt,
    });

class $$ComposeProjectLinksTableFilterComposer
    extends Composer<_$AppDatabase, $ComposeProjectLinksTable> {
  $$ComposeProjectLinksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get directory => $composableBuilder(
    column: $table.directory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get runtime => $composableBuilder(
    column: $table.runtime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get linkedAt => $composableBuilder(
    column: $table.linkedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ComposeProjectLinksTableOrderingComposer
    extends Composer<_$AppDatabase, $ComposeProjectLinksTable> {
  $$ComposeProjectLinksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get directory => $composableBuilder(
    column: $table.directory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get runtime => $composableBuilder(
    column: $table.runtime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get linkedAt => $composableBuilder(
    column: $table.linkedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ComposeProjectLinksTableAnnotationComposer
    extends Composer<_$AppDatabase, $ComposeProjectLinksTable> {
  $$ComposeProjectLinksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get directory =>
      $composableBuilder(column: $table.directory, builder: (column) => column);

  GeneratedColumn<String> get runtime =>
      $composableBuilder(column: $table.runtime, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<DateTime> get linkedAt =>
      $composableBuilder(column: $table.linkedAt, builder: (column) => column);
}

class $$ComposeProjectLinksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ComposeProjectLinksTable,
          ComposeProjectLink,
          $$ComposeProjectLinksTableFilterComposer,
          $$ComposeProjectLinksTableOrderingComposer,
          $$ComposeProjectLinksTableAnnotationComposer,
          $$ComposeProjectLinksTableCreateCompanionBuilder,
          $$ComposeProjectLinksTableUpdateCompanionBuilder,
          (
            ComposeProjectLink,
            BaseReferences<
              _$AppDatabase,
              $ComposeProjectLinksTable,
              ComposeProjectLink
            >,
          ),
          ComposeProjectLink,
          PrefetchHooks Function()
        > {
  $$ComposeProjectLinksTableTableManager(
    _$AppDatabase db,
    $ComposeProjectLinksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ComposeProjectLinksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ComposeProjectLinksTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ComposeProjectLinksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> serverId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> directory = const Value.absent(),
                Value<String> runtime = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<DateTime> linkedAt = const Value.absent(),
              }) => ComposeProjectLinksCompanion(
                id: id,
                serverId: serverId,
                name: name,
                directory: directory,
                runtime: runtime,
                scope: scope,
                linkedAt: linkedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int serverId,
                required String name,
                required String directory,
                required String runtime,
                required String scope,
                required DateTime linkedAt,
              }) => ComposeProjectLinksCompanion.insert(
                id: id,
                serverId: serverId,
                name: name,
                directory: directory,
                runtime: runtime,
                scope: scope,
                linkedAt: linkedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ComposeProjectLinksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ComposeProjectLinksTable,
      ComposeProjectLink,
      $$ComposeProjectLinksTableFilterComposer,
      $$ComposeProjectLinksTableOrderingComposer,
      $$ComposeProjectLinksTableAnnotationComposer,
      $$ComposeProjectLinksTableCreateCompanionBuilder,
      $$ComposeProjectLinksTableUpdateCompanionBuilder,
      (
        ComposeProjectLink,
        BaseReferences<
          _$AppDatabase,
          $ComposeProjectLinksTable,
          ComposeProjectLink
        >,
      ),
      ComposeProjectLink,
      PrefetchHooks Function()
    >;
typedef $$ContainerCacheEntriesTableCreateCompanionBuilder =
    ContainerCacheEntriesCompanion Function({
      required int serverId,
      required String runtime,
      required String scope,
      required String containerId,
      required String name,
      required String image,
      required String state,
      required String status,
      Value<String?> composeProject,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$ContainerCacheEntriesTableUpdateCompanionBuilder =
    ContainerCacheEntriesCompanion Function({
      Value<int> serverId,
      Value<String> runtime,
      Value<String> scope,
      Value<String> containerId,
      Value<String> name,
      Value<String> image,
      Value<String> state,
      Value<String> status,
      Value<String?> composeProject,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$ContainerCacheEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $ContainerCacheEntriesTable> {
  $$ContainerCacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get runtime => $composableBuilder(
    column: $table.runtime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get containerId => $composableBuilder(
    column: $table.containerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get image => $composableBuilder(
    column: $table.image,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get composeProject => $composableBuilder(
    column: $table.composeProject,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ContainerCacheEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $ContainerCacheEntriesTable> {
  $$ContainerCacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get runtime => $composableBuilder(
    column: $table.runtime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get containerId => $composableBuilder(
    column: $table.containerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get image => $composableBuilder(
    column: $table.image,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get composeProject => $composableBuilder(
    column: $table.composeProject,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ContainerCacheEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ContainerCacheEntriesTable> {
  $$ContainerCacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get runtime =>
      $composableBuilder(column: $table.runtime, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get containerId => $composableBuilder(
    column: $table.containerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get image =>
      $composableBuilder(column: $table.image, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get composeProject => $composableBuilder(
    column: $table.composeProject,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$ContainerCacheEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ContainerCacheEntriesTable,
          ContainerCacheEntry,
          $$ContainerCacheEntriesTableFilterComposer,
          $$ContainerCacheEntriesTableOrderingComposer,
          $$ContainerCacheEntriesTableAnnotationComposer,
          $$ContainerCacheEntriesTableCreateCompanionBuilder,
          $$ContainerCacheEntriesTableUpdateCompanionBuilder,
          (
            ContainerCacheEntry,
            BaseReferences<
              _$AppDatabase,
              $ContainerCacheEntriesTable,
              ContainerCacheEntry
            >,
          ),
          ContainerCacheEntry,
          PrefetchHooks Function()
        > {
  $$ContainerCacheEntriesTableTableManager(
    _$AppDatabase db,
    $ContainerCacheEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContainerCacheEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ContainerCacheEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ContainerCacheEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> serverId = const Value.absent(),
                Value<String> runtime = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<String> containerId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> image = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> composeProject = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContainerCacheEntriesCompanion(
                serverId: serverId,
                runtime: runtime,
                scope: scope,
                containerId: containerId,
                name: name,
                image: image,
                state: state,
                status: status,
                composeProject: composeProject,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int serverId,
                required String runtime,
                required String scope,
                required String containerId,
                required String name,
                required String image,
                required String state,
                required String status,
                Value<String?> composeProject = const Value.absent(),
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => ContainerCacheEntriesCompanion.insert(
                serverId: serverId,
                runtime: runtime,
                scope: scope,
                containerId: containerId,
                name: name,
                image: image,
                state: state,
                status: status,
                composeProject: composeProject,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ContainerCacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ContainerCacheEntriesTable,
      ContainerCacheEntry,
      $$ContainerCacheEntriesTableFilterComposer,
      $$ContainerCacheEntriesTableOrderingComposer,
      $$ContainerCacheEntriesTableAnnotationComposer,
      $$ContainerCacheEntriesTableCreateCompanionBuilder,
      $$ContainerCacheEntriesTableUpdateCompanionBuilder,
      (
        ContainerCacheEntry,
        BaseReferences<
          _$AppDatabase,
          $ContainerCacheEntriesTable,
          ContainerCacheEntry
        >,
      ),
      ContainerCacheEntry,
      PrefetchHooks Function()
    >;
typedef $$DeploymentProjectsTableCreateCompanionBuilder =
    DeploymentProjectsCompanion Function({
      Value<int> id,
      required String name,
      Value<String?> description,
      required DateTime createdAt,
      required DateTime updatedAt,
    });
typedef $$DeploymentProjectsTableUpdateCompanionBuilder =
    DeploymentProjectsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> description,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$DeploymentProjectsTableFilterComposer
    extends Composer<_$AppDatabase, $DeploymentProjectsTable> {
  $$DeploymentProjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DeploymentProjectsTableOrderingComposer
    extends Composer<_$AppDatabase, $DeploymentProjectsTable> {
  $$DeploymentProjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DeploymentProjectsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DeploymentProjectsTable> {
  $$DeploymentProjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DeploymentProjectsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DeploymentProjectsTable,
          DeploymentProject,
          $$DeploymentProjectsTableFilterComposer,
          $$DeploymentProjectsTableOrderingComposer,
          $$DeploymentProjectsTableAnnotationComposer,
          $$DeploymentProjectsTableCreateCompanionBuilder,
          $$DeploymentProjectsTableUpdateCompanionBuilder,
          (
            DeploymentProject,
            BaseReferences<
              _$AppDatabase,
              $DeploymentProjectsTable,
              DeploymentProject
            >,
          ),
          DeploymentProject,
          PrefetchHooks Function()
        > {
  $$DeploymentProjectsTableTableManager(
    _$AppDatabase db,
    $DeploymentProjectsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeploymentProjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DeploymentProjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DeploymentProjectsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => DeploymentProjectsCompanion(
                id: id,
                name: name,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String?> description = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
              }) => DeploymentProjectsCompanion.insert(
                id: id,
                name: name,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DeploymentProjectsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DeploymentProjectsTable,
      DeploymentProject,
      $$DeploymentProjectsTableFilterComposer,
      $$DeploymentProjectsTableOrderingComposer,
      $$DeploymentProjectsTableAnnotationComposer,
      $$DeploymentProjectsTableCreateCompanionBuilder,
      $$DeploymentProjectsTableUpdateCompanionBuilder,
      (
        DeploymentProject,
        BaseReferences<
          _$AppDatabase,
          $DeploymentProjectsTable,
          DeploymentProject
        >,
      ),
      DeploymentProject,
      PrefetchHooks Function()
    >;
typedef $$DeploymentResourcesTableCreateCompanionBuilder =
    DeploymentResourcesCompanion Function({
      Value<int> id,
      required int projectId,
      required String kind,
      required String name,
      Value<int?> serverId,
      Value<String> configuration,
      required DateTime createdAt,
      required DateTime updatedAt,
    });
typedef $$DeploymentResourcesTableUpdateCompanionBuilder =
    DeploymentResourcesCompanion Function({
      Value<int> id,
      Value<int> projectId,
      Value<String> kind,
      Value<String> name,
      Value<int?> serverId,
      Value<String> configuration,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$DeploymentResourcesTableFilterComposer
    extends Composer<_$AppDatabase, $DeploymentResourcesTable> {
  $$DeploymentResourcesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configuration => $composableBuilder(
    column: $table.configuration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DeploymentResourcesTableOrderingComposer
    extends Composer<_$AppDatabase, $DeploymentResourcesTable> {
  $$DeploymentResourcesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get configuration => $composableBuilder(
    column: $table.configuration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DeploymentResourcesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DeploymentResourcesTable> {
  $$DeploymentResourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get configuration => $composableBuilder(
    column: $table.configuration,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DeploymentResourcesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DeploymentResourcesTable,
          DeploymentResource,
          $$DeploymentResourcesTableFilterComposer,
          $$DeploymentResourcesTableOrderingComposer,
          $$DeploymentResourcesTableAnnotationComposer,
          $$DeploymentResourcesTableCreateCompanionBuilder,
          $$DeploymentResourcesTableUpdateCompanionBuilder,
          (
            DeploymentResource,
            BaseReferences<
              _$AppDatabase,
              $DeploymentResourcesTable,
              DeploymentResource
            >,
          ),
          DeploymentResource,
          PrefetchHooks Function()
        > {
  $$DeploymentResourcesTableTableManager(
    _$AppDatabase db,
    $DeploymentResourcesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeploymentResourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DeploymentResourcesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DeploymentResourcesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> projectId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int?> serverId = const Value.absent(),
                Value<String> configuration = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => DeploymentResourcesCompanion(
                id: id,
                projectId: projectId,
                kind: kind,
                name: name,
                serverId: serverId,
                configuration: configuration,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int projectId,
                required String kind,
                required String name,
                Value<int?> serverId = const Value.absent(),
                Value<String> configuration = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
              }) => DeploymentResourcesCompanion.insert(
                id: id,
                projectId: projectId,
                kind: kind,
                name: name,
                serverId: serverId,
                configuration: configuration,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DeploymentResourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DeploymentResourcesTable,
      DeploymentResource,
      $$DeploymentResourcesTableFilterComposer,
      $$DeploymentResourcesTableOrderingComposer,
      $$DeploymentResourcesTableAnnotationComposer,
      $$DeploymentResourcesTableCreateCompanionBuilder,
      $$DeploymentResourcesTableUpdateCompanionBuilder,
      (
        DeploymentResource,
        BaseReferences<
          _$AppDatabase,
          $DeploymentResourcesTable,
          DeploymentResource
        >,
      ),
      DeploymentResource,
      PrefetchHooks Function()
    >;
typedef $$ScriptSnippetsTableCreateCompanionBuilder =
    ScriptSnippetsCompanion Function({
      Value<int> id,
      required String name,
      required String script,
      required DateTime createdAt,
      required DateTime updatedAt,
    });
typedef $$ScriptSnippetsTableUpdateCompanionBuilder =
    ScriptSnippetsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> script,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$ScriptSnippetsTableFilterComposer
    extends Composer<_$AppDatabase, $ScriptSnippetsTable> {
  $$ScriptSnippetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get script => $composableBuilder(
    column: $table.script,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ScriptSnippetsTableOrderingComposer
    extends Composer<_$AppDatabase, $ScriptSnippetsTable> {
  $$ScriptSnippetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get script => $composableBuilder(
    column: $table.script,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ScriptSnippetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScriptSnippetsTable> {
  $$ScriptSnippetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get script =>
      $composableBuilder(column: $table.script, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ScriptSnippetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScriptSnippetsTable,
          ScriptSnippet,
          $$ScriptSnippetsTableFilterComposer,
          $$ScriptSnippetsTableOrderingComposer,
          $$ScriptSnippetsTableAnnotationComposer,
          $$ScriptSnippetsTableCreateCompanionBuilder,
          $$ScriptSnippetsTableUpdateCompanionBuilder,
          (
            ScriptSnippet,
            BaseReferences<_$AppDatabase, $ScriptSnippetsTable, ScriptSnippet>,
          ),
          ScriptSnippet,
          PrefetchHooks Function()
        > {
  $$ScriptSnippetsTableTableManager(
    _$AppDatabase db,
    $ScriptSnippetsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScriptSnippetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScriptSnippetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScriptSnippetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> script = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ScriptSnippetsCompanion(
                id: id,
                name: name,
                script: script,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String script,
                required DateTime createdAt,
                required DateTime updatedAt,
              }) => ScriptSnippetsCompanion.insert(
                id: id,
                name: name,
                script: script,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ScriptSnippetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScriptSnippetsTable,
      ScriptSnippet,
      $$ScriptSnippetsTableFilterComposer,
      $$ScriptSnippetsTableOrderingComposer,
      $$ScriptSnippetsTableAnnotationComposer,
      $$ScriptSnippetsTableCreateCompanionBuilder,
      $$ScriptSnippetsTableUpdateCompanionBuilder,
      (
        ScriptSnippet,
        BaseReferences<_$AppDatabase, $ScriptSnippetsTable, ScriptSnippet>,
      ),
      ScriptSnippet,
      PrefetchHooks Function()
    >;
typedef $$AgentSettingsTableCreateCompanionBuilder =
    AgentSettingsCompanion Function({
      Value<int> id,
      required String encryptedApiKey,
      required String apiKeyNonce,
      Value<String> model,
      required DateTime updatedAt,
    });
typedef $$AgentSettingsTableUpdateCompanionBuilder =
    AgentSettingsCompanion Function({
      Value<int> id,
      Value<String> encryptedApiKey,
      Value<String> apiKeyNonce,
      Value<String> model,
      Value<DateTime> updatedAt,
    });

class $$AgentSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AgentSettingsTable> {
  $$AgentSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedApiKey => $composableBuilder(
    column: $table.encryptedApiKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get apiKeyNonce => $composableBuilder(
    column: $table.apiKeyNonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AgentSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AgentSettingsTable> {
  $$AgentSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedApiKey => $composableBuilder(
    column: $table.encryptedApiKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get apiKeyNonce => $composableBuilder(
    column: $table.apiKeyNonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AgentSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AgentSettingsTable> {
  $$AgentSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get encryptedApiKey => $composableBuilder(
    column: $table.encryptedApiKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get apiKeyNonce => $composableBuilder(
    column: $table.apiKeyNonce,
    builder: (column) => column,
  );

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AgentSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AgentSettingsTable,
          AgentSetting,
          $$AgentSettingsTableFilterComposer,
          $$AgentSettingsTableOrderingComposer,
          $$AgentSettingsTableAnnotationComposer,
          $$AgentSettingsTableCreateCompanionBuilder,
          $$AgentSettingsTableUpdateCompanionBuilder,
          (
            AgentSetting,
            BaseReferences<_$AppDatabase, $AgentSettingsTable, AgentSetting>,
          ),
          AgentSetting,
          PrefetchHooks Function()
        > {
  $$AgentSettingsTableTableManager(_$AppDatabase db, $AgentSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AgentSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AgentSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AgentSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> encryptedApiKey = const Value.absent(),
                Value<String> apiKeyNonce = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => AgentSettingsCompanion(
                id: id,
                encryptedApiKey: encryptedApiKey,
                apiKeyNonce: apiKeyNonce,
                model: model,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String encryptedApiKey,
                required String apiKeyNonce,
                Value<String> model = const Value.absent(),
                required DateTime updatedAt,
              }) => AgentSettingsCompanion.insert(
                id: id,
                encryptedApiKey: encryptedApiKey,
                apiKeyNonce: apiKeyNonce,
                model: model,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AgentSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AgentSettingsTable,
      AgentSetting,
      $$AgentSettingsTableFilterComposer,
      $$AgentSettingsTableOrderingComposer,
      $$AgentSettingsTableAnnotationComposer,
      $$AgentSettingsTableCreateCompanionBuilder,
      $$AgentSettingsTableUpdateCompanionBuilder,
      (
        AgentSetting,
        BaseReferences<_$AppDatabase, $AgentSettingsTable, AgentSetting>,
      ),
      AgentSetting,
      PrefetchHooks Function()
    >;
typedef $$AgentProvidersTableCreateCompanionBuilder =
    AgentProvidersCompanion Function({
      Value<int> id,
      required String name,
      required String encryptedApiKey,
      required String apiKeyNonce,
      Value<String?> baseUrl,
      required String model,
      required DateTime updatedAt,
    });
typedef $$AgentProvidersTableUpdateCompanionBuilder =
    AgentProvidersCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> encryptedApiKey,
      Value<String> apiKeyNonce,
      Value<String?> baseUrl,
      Value<String> model,
      Value<DateTime> updatedAt,
    });

class $$AgentProvidersTableFilterComposer
    extends Composer<_$AppDatabase, $AgentProvidersTable> {
  $$AgentProvidersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedApiKey => $composableBuilder(
    column: $table.encryptedApiKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get apiKeyNonce => $composableBuilder(
    column: $table.apiKeyNonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AgentProvidersTableOrderingComposer
    extends Composer<_$AppDatabase, $AgentProvidersTable> {
  $$AgentProvidersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedApiKey => $composableBuilder(
    column: $table.encryptedApiKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get apiKeyNonce => $composableBuilder(
    column: $table.apiKeyNonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AgentProvidersTableAnnotationComposer
    extends Composer<_$AppDatabase, $AgentProvidersTable> {
  $$AgentProvidersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get encryptedApiKey => $composableBuilder(
    column: $table.encryptedApiKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get apiKeyNonce => $composableBuilder(
    column: $table.apiKeyNonce,
    builder: (column) => column,
  );

  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AgentProvidersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AgentProvidersTable,
          AgentProvider,
          $$AgentProvidersTableFilterComposer,
          $$AgentProvidersTableOrderingComposer,
          $$AgentProvidersTableAnnotationComposer,
          $$AgentProvidersTableCreateCompanionBuilder,
          $$AgentProvidersTableUpdateCompanionBuilder,
          (
            AgentProvider,
            BaseReferences<_$AppDatabase, $AgentProvidersTable, AgentProvider>,
          ),
          AgentProvider,
          PrefetchHooks Function()
        > {
  $$AgentProvidersTableTableManager(
    _$AppDatabase db,
    $AgentProvidersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AgentProvidersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AgentProvidersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AgentProvidersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> encryptedApiKey = const Value.absent(),
                Value<String> apiKeyNonce = const Value.absent(),
                Value<String?> baseUrl = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => AgentProvidersCompanion(
                id: id,
                name: name,
                encryptedApiKey: encryptedApiKey,
                apiKeyNonce: apiKeyNonce,
                baseUrl: baseUrl,
                model: model,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String encryptedApiKey,
                required String apiKeyNonce,
                Value<String?> baseUrl = const Value.absent(),
                required String model,
                required DateTime updatedAt,
              }) => AgentProvidersCompanion.insert(
                id: id,
                name: name,
                encryptedApiKey: encryptedApiKey,
                apiKeyNonce: apiKeyNonce,
                baseUrl: baseUrl,
                model: model,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AgentProvidersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AgentProvidersTable,
      AgentProvider,
      $$AgentProvidersTableFilterComposer,
      $$AgentProvidersTableOrderingComposer,
      $$AgentProvidersTableAnnotationComposer,
      $$AgentProvidersTableCreateCompanionBuilder,
      $$AgentProvidersTableUpdateCompanionBuilder,
      (
        AgentProvider,
        BaseReferences<_$AppDatabase, $AgentProvidersTable, AgentProvider>,
      ),
      AgentProvider,
      PrefetchHooks Function()
    >;
typedef $$AgentProviderModelsTableCreateCompanionBuilder =
    AgentProviderModelsCompanion Function({
      Value<int> id,
      required int providerId,
      required String model,
      required DateTime createdAt,
    });
typedef $$AgentProviderModelsTableUpdateCompanionBuilder =
    AgentProviderModelsCompanion Function({
      Value<int> id,
      Value<int> providerId,
      Value<String> model,
      Value<DateTime> createdAt,
    });

class $$AgentProviderModelsTableFilterComposer
    extends Composer<_$AppDatabase, $AgentProviderModelsTable> {
  $$AgentProviderModelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AgentProviderModelsTableOrderingComposer
    extends Composer<_$AppDatabase, $AgentProviderModelsTable> {
  $$AgentProviderModelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AgentProviderModelsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AgentProviderModelsTable> {
  $$AgentProviderModelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$AgentProviderModelsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AgentProviderModelsTable,
          AgentProviderModel,
          $$AgentProviderModelsTableFilterComposer,
          $$AgentProviderModelsTableOrderingComposer,
          $$AgentProviderModelsTableAnnotationComposer,
          $$AgentProviderModelsTableCreateCompanionBuilder,
          $$AgentProviderModelsTableUpdateCompanionBuilder,
          (
            AgentProviderModel,
            BaseReferences<
              _$AppDatabase,
              $AgentProviderModelsTable,
              AgentProviderModel
            >,
          ),
          AgentProviderModel,
          PrefetchHooks Function()
        > {
  $$AgentProviderModelsTableTableManager(
    _$AppDatabase db,
    $AgentProviderModelsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AgentProviderModelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AgentProviderModelsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AgentProviderModelsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> providerId = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => AgentProviderModelsCompanion(
                id: id,
                providerId: providerId,
                model: model,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int providerId,
                required String model,
                required DateTime createdAt,
              }) => AgentProviderModelsCompanion.insert(
                id: id,
                providerId: providerId,
                model: model,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AgentProviderModelsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AgentProviderModelsTable,
      AgentProviderModel,
      $$AgentProviderModelsTableFilterComposer,
      $$AgentProviderModelsTableOrderingComposer,
      $$AgentProviderModelsTableAnnotationComposer,
      $$AgentProviderModelsTableCreateCompanionBuilder,
      $$AgentProviderModelsTableUpdateCompanionBuilder,
      (
        AgentProviderModel,
        BaseReferences<
          _$AppDatabase,
          $AgentProviderModelsTable,
          AgentProviderModel
        >,
      ),
      AgentProviderModel,
      PrefetchHooks Function()
    >;
typedef $$McpServersTableCreateCompanionBuilder =
    McpServersCompanion Function({
      Value<int> id,
      required String name,
      required String command,
      Value<String> arguments,
      Value<String> environment,
      Value<bool> enabled,
      required DateTime createdAt,
      required DateTime updatedAt,
    });
typedef $$McpServersTableUpdateCompanionBuilder =
    McpServersCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> command,
      Value<String> arguments,
      Value<String> environment,
      Value<bool> enabled,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$McpServersTableFilterComposer
    extends Composer<_$AppDatabase, $McpServersTable> {
  $$McpServersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get command => $composableBuilder(
    column: $table.command,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get arguments => $composableBuilder(
    column: $table.arguments,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get environment => $composableBuilder(
    column: $table.environment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$McpServersTableOrderingComposer
    extends Composer<_$AppDatabase, $McpServersTable> {
  $$McpServersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get command => $composableBuilder(
    column: $table.command,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get arguments => $composableBuilder(
    column: $table.arguments,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get environment => $composableBuilder(
    column: $table.environment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$McpServersTableAnnotationComposer
    extends Composer<_$AppDatabase, $McpServersTable> {
  $$McpServersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get command =>
      $composableBuilder(column: $table.command, builder: (column) => column);

  GeneratedColumn<String> get arguments =>
      $composableBuilder(column: $table.arguments, builder: (column) => column);

  GeneratedColumn<String> get environment => $composableBuilder(
    column: $table.environment,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$McpServersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $McpServersTable,
          McpServer,
          $$McpServersTableFilterComposer,
          $$McpServersTableOrderingComposer,
          $$McpServersTableAnnotationComposer,
          $$McpServersTableCreateCompanionBuilder,
          $$McpServersTableUpdateCompanionBuilder,
          (
            McpServer,
            BaseReferences<_$AppDatabase, $McpServersTable, McpServer>,
          ),
          McpServer,
          PrefetchHooks Function()
        > {
  $$McpServersTableTableManager(_$AppDatabase db, $McpServersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$McpServersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$McpServersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$McpServersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> command = const Value.absent(),
                Value<String> arguments = const Value.absent(),
                Value<String> environment = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => McpServersCompanion(
                id: id,
                name: name,
                command: command,
                arguments: arguments,
                environment: environment,
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String command,
                Value<String> arguments = const Value.absent(),
                Value<String> environment = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
              }) => McpServersCompanion.insert(
                id: id,
                name: name,
                command: command,
                arguments: arguments,
                environment: environment,
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$McpServersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $McpServersTable,
      McpServer,
      $$McpServersTableFilterComposer,
      $$McpServersTableOrderingComposer,
      $$McpServersTableAnnotationComposer,
      $$McpServersTableCreateCompanionBuilder,
      $$McpServersTableUpdateCompanionBuilder,
      (McpServer, BaseReferences<_$AppDatabase, $McpServersTable, McpServer>),
      McpServer,
      PrefetchHooks Function()
    >;
typedef $$AgentSkillsTableCreateCompanionBuilder =
    AgentSkillsCompanion Function({
      Value<int> id,
      required String name,
      Value<String> description,
      required String content,
      Value<bool> enabled,
      required DateTime createdAt,
      required DateTime updatedAt,
    });
typedef $$AgentSkillsTableUpdateCompanionBuilder =
    AgentSkillsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> description,
      Value<String> content,
      Value<bool> enabled,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$AgentSkillsTableFilterComposer
    extends Composer<_$AppDatabase, $AgentSkillsTable> {
  $$AgentSkillsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AgentSkillsTableOrderingComposer
    extends Composer<_$AppDatabase, $AgentSkillsTable> {
  $$AgentSkillsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AgentSkillsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AgentSkillsTable> {
  $$AgentSkillsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AgentSkillsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AgentSkillsTable,
          AgentSkill,
          $$AgentSkillsTableFilterComposer,
          $$AgentSkillsTableOrderingComposer,
          $$AgentSkillsTableAnnotationComposer,
          $$AgentSkillsTableCreateCompanionBuilder,
          $$AgentSkillsTableUpdateCompanionBuilder,
          (
            AgentSkill,
            BaseReferences<_$AppDatabase, $AgentSkillsTable, AgentSkill>,
          ),
          AgentSkill,
          PrefetchHooks Function()
        > {
  $$AgentSkillsTableTableManager(_$AppDatabase db, $AgentSkillsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AgentSkillsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AgentSkillsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AgentSkillsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => AgentSkillsCompanion(
                id: id,
                name: name,
                description: description,
                content: content,
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String> description = const Value.absent(),
                required String content,
                Value<bool> enabled = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
              }) => AgentSkillsCompanion.insert(
                id: id,
                name: name,
                description: description,
                content: content,
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AgentSkillsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AgentSkillsTable,
      AgentSkill,
      $$AgentSkillsTableFilterComposer,
      $$AgentSkillsTableOrderingComposer,
      $$AgentSkillsTableAnnotationComposer,
      $$AgentSkillsTableCreateCompanionBuilder,
      $$AgentSkillsTableUpdateCompanionBuilder,
      (
        AgentSkill,
        BaseReferences<_$AppDatabase, $AgentSkillsTable, AgentSkill>,
      ),
      AgentSkill,
      PrefetchHooks Function()
    >;
typedef $$GitHubConnectionsTableCreateCompanionBuilder =
    GitHubConnectionsCompanion Function({
      Value<int> id,
      required String accountLogin,
      Value<String> accountName,
      Value<String> avatarUrl,
      required DateTime createdAt,
    });
typedef $$GitHubConnectionsTableUpdateCompanionBuilder =
    GitHubConnectionsCompanion Function({
      Value<int> id,
      Value<String> accountLogin,
      Value<String> accountName,
      Value<String> avatarUrl,
      Value<DateTime> createdAt,
    });

final class $$GitHubConnectionsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $GitHubConnectionsTable,
          GitHubConnection
        > {
  $$GitHubConnectionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$GitHubRepoPinsTable, List<GitHubRepoPin>>
  _gitHubRepoPinsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.gitHubRepoPins,
    aliasName: 'github_connections__id__github_repo_pins__connection_id',
  );

  $$GitHubRepoPinsTableProcessedTableManager get gitHubRepoPinsRefs {
    final manager = $$GitHubRepoPinsTableTableManager(
      $_db,
      $_db.gitHubRepoPins,
    ).filter((f) => f.connectionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_gitHubRepoPinsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$GitHubConnectionsTableFilterComposer
    extends Composer<_$AppDatabase, $GitHubConnectionsTable> {
  $$GitHubConnectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountLogin => $composableBuilder(
    column: $table.accountLogin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountName => $composableBuilder(
    column: $table.accountName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> gitHubRepoPinsRefs(
    Expression<bool> Function($$GitHubRepoPinsTableFilterComposer f) f,
  ) {
    final $$GitHubRepoPinsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.gitHubRepoPins,
      getReferencedColumn: (t) => t.connectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GitHubRepoPinsTableFilterComposer(
            $db: $db,
            $table: $db.gitHubRepoPins,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GitHubConnectionsTableOrderingComposer
    extends Composer<_$AppDatabase, $GitHubConnectionsTable> {
  $$GitHubConnectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountLogin => $composableBuilder(
    column: $table.accountLogin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountName => $composableBuilder(
    column: $table.accountName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GitHubConnectionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GitHubConnectionsTable> {
  $$GitHubConnectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get accountLogin => $composableBuilder(
    column: $table.accountLogin,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accountName => $composableBuilder(
    column: $table.accountName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> gitHubRepoPinsRefs<T extends Object>(
    Expression<T> Function($$GitHubRepoPinsTableAnnotationComposer a) f,
  ) {
    final $$GitHubRepoPinsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.gitHubRepoPins,
      getReferencedColumn: (t) => t.connectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GitHubRepoPinsTableAnnotationComposer(
            $db: $db,
            $table: $db.gitHubRepoPins,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GitHubConnectionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GitHubConnectionsTable,
          GitHubConnection,
          $$GitHubConnectionsTableFilterComposer,
          $$GitHubConnectionsTableOrderingComposer,
          $$GitHubConnectionsTableAnnotationComposer,
          $$GitHubConnectionsTableCreateCompanionBuilder,
          $$GitHubConnectionsTableUpdateCompanionBuilder,
          (GitHubConnection, $$GitHubConnectionsTableReferences),
          GitHubConnection,
          PrefetchHooks Function({bool gitHubRepoPinsRefs})
        > {
  $$GitHubConnectionsTableTableManager(
    _$AppDatabase db,
    $GitHubConnectionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GitHubConnectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GitHubConnectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GitHubConnectionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> accountLogin = const Value.absent(),
                Value<String> accountName = const Value.absent(),
                Value<String> avatarUrl = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => GitHubConnectionsCompanion(
                id: id,
                accountLogin: accountLogin,
                accountName: accountName,
                avatarUrl: avatarUrl,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String accountLogin,
                Value<String> accountName = const Value.absent(),
                Value<String> avatarUrl = const Value.absent(),
                required DateTime createdAt,
              }) => GitHubConnectionsCompanion.insert(
                id: id,
                accountLogin: accountLogin,
                accountName: accountName,
                avatarUrl: avatarUrl,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$GitHubConnectionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({gitHubRepoPinsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (gitHubRepoPinsRefs) db.gitHubRepoPins,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (gitHubRepoPinsRefs)
                    await $_getPrefetchedData<
                      GitHubConnection,
                      $GitHubConnectionsTable,
                      GitHubRepoPin
                    >(
                      currentTable: table,
                      referencedTable: $$GitHubConnectionsTableReferences
                          ._gitHubRepoPinsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$GitHubConnectionsTableReferences(
                            db,
                            table,
                            p0,
                          ).gitHubRepoPinsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.connectionId == item.id,
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

typedef $$GitHubConnectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GitHubConnectionsTable,
      GitHubConnection,
      $$GitHubConnectionsTableFilterComposer,
      $$GitHubConnectionsTableOrderingComposer,
      $$GitHubConnectionsTableAnnotationComposer,
      $$GitHubConnectionsTableCreateCompanionBuilder,
      $$GitHubConnectionsTableUpdateCompanionBuilder,
      (GitHubConnection, $$GitHubConnectionsTableReferences),
      GitHubConnection,
      PrefetchHooks Function({bool gitHubRepoPinsRefs})
    >;
typedef $$GitHubRepoPinsTableCreateCompanionBuilder =
    GitHubRepoPinsCompanion Function({
      Value<int> id,
      required int connectionId,
      required String owner,
      required String name,
      required DateTime pinnedAt,
    });
typedef $$GitHubRepoPinsTableUpdateCompanionBuilder =
    GitHubRepoPinsCompanion Function({
      Value<int> id,
      Value<int> connectionId,
      Value<String> owner,
      Value<String> name,
      Value<DateTime> pinnedAt,
    });

final class $$GitHubRepoPinsTableReferences
    extends BaseReferences<_$AppDatabase, $GitHubRepoPinsTable, GitHubRepoPin> {
  $$GitHubRepoPinsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $GitHubConnectionsTable _connectionIdTable(_$AppDatabase db) => db
      .gitHubConnections
      .createAlias('github_repo_pins__connection_id__github_connections__id');

  $$GitHubConnectionsTableProcessedTableManager get connectionId {
    final $_column = $_itemColumn<int>('connection_id')!;

    final manager = $$GitHubConnectionsTableTableManager(
      $_db,
      $_db.gitHubConnections,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_connectionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$GitHubRepoPinsTableFilterComposer
    extends Composer<_$AppDatabase, $GitHubRepoPinsTable> {
  $$GitHubRepoPinsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get pinnedAt => $composableBuilder(
    column: $table.pinnedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$GitHubConnectionsTableFilterComposer get connectionId {
    final $$GitHubConnectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.connectionId,
      referencedTable: $db.gitHubConnections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GitHubConnectionsTableFilterComposer(
            $db: $db,
            $table: $db.gitHubConnections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GitHubRepoPinsTableOrderingComposer
    extends Composer<_$AppDatabase, $GitHubRepoPinsTable> {
  $$GitHubRepoPinsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get pinnedAt => $composableBuilder(
    column: $table.pinnedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$GitHubConnectionsTableOrderingComposer get connectionId {
    final $$GitHubConnectionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.connectionId,
      referencedTable: $db.gitHubConnections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GitHubConnectionsTableOrderingComposer(
            $db: $db,
            $table: $db.gitHubConnections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GitHubRepoPinsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GitHubRepoPinsTable> {
  $$GitHubRepoPinsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get owner =>
      $composableBuilder(column: $table.owner, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get pinnedAt =>
      $composableBuilder(column: $table.pinnedAt, builder: (column) => column);

  $$GitHubConnectionsTableAnnotationComposer get connectionId {
    final $$GitHubConnectionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.connectionId,
          referencedTable: $db.gitHubConnections,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$GitHubConnectionsTableAnnotationComposer(
                $db: $db,
                $table: $db.gitHubConnections,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$GitHubRepoPinsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GitHubRepoPinsTable,
          GitHubRepoPin,
          $$GitHubRepoPinsTableFilterComposer,
          $$GitHubRepoPinsTableOrderingComposer,
          $$GitHubRepoPinsTableAnnotationComposer,
          $$GitHubRepoPinsTableCreateCompanionBuilder,
          $$GitHubRepoPinsTableUpdateCompanionBuilder,
          (GitHubRepoPin, $$GitHubRepoPinsTableReferences),
          GitHubRepoPin,
          PrefetchHooks Function({bool connectionId})
        > {
  $$GitHubRepoPinsTableTableManager(
    _$AppDatabase db,
    $GitHubRepoPinsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GitHubRepoPinsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GitHubRepoPinsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GitHubRepoPinsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> connectionId = const Value.absent(),
                Value<String> owner = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> pinnedAt = const Value.absent(),
              }) => GitHubRepoPinsCompanion(
                id: id,
                connectionId: connectionId,
                owner: owner,
                name: name,
                pinnedAt: pinnedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int connectionId,
                required String owner,
                required String name,
                required DateTime pinnedAt,
              }) => GitHubRepoPinsCompanion.insert(
                id: id,
                connectionId: connectionId,
                owner: owner,
                name: name,
                pinnedAt: pinnedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$GitHubRepoPinsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({connectionId = false}) {
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
                    if (connectionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.connectionId,
                                referencedTable: $$GitHubRepoPinsTableReferences
                                    ._connectionIdTable(db),
                                referencedColumn:
                                    $$GitHubRepoPinsTableReferences
                                        ._connectionIdTable(db)
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

typedef $$GitHubRepoPinsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GitHubRepoPinsTable,
      GitHubRepoPin,
      $$GitHubRepoPinsTableFilterComposer,
      $$GitHubRepoPinsTableOrderingComposer,
      $$GitHubRepoPinsTableAnnotationComposer,
      $$GitHubRepoPinsTableCreateCompanionBuilder,
      $$GitHubRepoPinsTableUpdateCompanionBuilder,
      (GitHubRepoPin, $$GitHubRepoPinsTableReferences),
      GitHubRepoPin,
      PrefetchHooks Function({bool connectionId})
    >;
typedef $$GitHubTokensTableCreateCompanionBuilder =
    GitHubTokensCompanion Function({
      Value<int> id,
      required String accountLogin,
      required String encryptedToken,
      required String tokenNonce,
      required DateTime updatedAt,
    });
typedef $$GitHubTokensTableUpdateCompanionBuilder =
    GitHubTokensCompanion Function({
      Value<int> id,
      Value<String> accountLogin,
      Value<String> encryptedToken,
      Value<String> tokenNonce,
      Value<DateTime> updatedAt,
    });

class $$GitHubTokensTableFilterComposer
    extends Composer<_$AppDatabase, $GitHubTokensTable> {
  $$GitHubTokensTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountLogin => $composableBuilder(
    column: $table.accountLogin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedToken => $composableBuilder(
    column: $table.encryptedToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tokenNonce => $composableBuilder(
    column: $table.tokenNonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GitHubTokensTableOrderingComposer
    extends Composer<_$AppDatabase, $GitHubTokensTable> {
  $$GitHubTokensTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountLogin => $composableBuilder(
    column: $table.accountLogin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedToken => $composableBuilder(
    column: $table.encryptedToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tokenNonce => $composableBuilder(
    column: $table.tokenNonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GitHubTokensTableAnnotationComposer
    extends Composer<_$AppDatabase, $GitHubTokensTable> {
  $$GitHubTokensTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get accountLogin => $composableBuilder(
    column: $table.accountLogin,
    builder: (column) => column,
  );

  GeneratedColumn<String> get encryptedToken => $composableBuilder(
    column: $table.encryptedToken,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tokenNonce => $composableBuilder(
    column: $table.tokenNonce,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$GitHubTokensTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GitHubTokensTable,
          GitHubToken,
          $$GitHubTokensTableFilterComposer,
          $$GitHubTokensTableOrderingComposer,
          $$GitHubTokensTableAnnotationComposer,
          $$GitHubTokensTableCreateCompanionBuilder,
          $$GitHubTokensTableUpdateCompanionBuilder,
          (
            GitHubToken,
            BaseReferences<_$AppDatabase, $GitHubTokensTable, GitHubToken>,
          ),
          GitHubToken,
          PrefetchHooks Function()
        > {
  $$GitHubTokensTableTableManager(_$AppDatabase db, $GitHubTokensTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GitHubTokensTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GitHubTokensTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GitHubTokensTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> accountLogin = const Value.absent(),
                Value<String> encryptedToken = const Value.absent(),
                Value<String> tokenNonce = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => GitHubTokensCompanion(
                id: id,
                accountLogin: accountLogin,
                encryptedToken: encryptedToken,
                tokenNonce: tokenNonce,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String accountLogin,
                required String encryptedToken,
                required String tokenNonce,
                required DateTime updatedAt,
              }) => GitHubTokensCompanion.insert(
                id: id,
                accountLogin: accountLogin,
                encryptedToken: encryptedToken,
                tokenNonce: tokenNonce,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GitHubTokensTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GitHubTokensTable,
      GitHubToken,
      $$GitHubTokensTableFilterComposer,
      $$GitHubTokensTableOrderingComposer,
      $$GitHubTokensTableAnnotationComposer,
      $$GitHubTokensTableCreateCompanionBuilder,
      $$GitHubTokensTableUpdateCompanionBuilder,
      (
        GitHubToken,
        BaseReferences<_$AppDatabase, $GitHubTokensTable, GitHubToken>,
      ),
      GitHubToken,
      PrefetchHooks Function()
    >;
typedef $$PortForwardConfigsTableCreateCompanionBuilder =
    PortForwardConfigsCompanion Function({
      Value<int> id,
      required int serverId,
      required String direction,
      required String kind,
      required String bindHost,
      required int bindPort,
      required String targetHost,
      required int targetPort,
      Value<bool> autoStart,
      required DateTime createdAt,
      required DateTime updatedAt,
    });
typedef $$PortForwardConfigsTableUpdateCompanionBuilder =
    PortForwardConfigsCompanion Function({
      Value<int> id,
      Value<int> serverId,
      Value<String> direction,
      Value<String> kind,
      Value<String> bindHost,
      Value<int> bindPort,
      Value<String> targetHost,
      Value<int> targetPort,
      Value<bool> autoStart,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$PortForwardConfigsTableFilterComposer
    extends Composer<_$AppDatabase, $PortForwardConfigsTable> {
  $$PortForwardConfigsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bindHost => $composableBuilder(
    column: $table.bindHost,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bindPort => $composableBuilder(
    column: $table.bindPort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetHost => $composableBuilder(
    column: $table.targetHost,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetPort => $composableBuilder(
    column: $table.targetPort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoStart => $composableBuilder(
    column: $table.autoStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PortForwardConfigsTableOrderingComposer
    extends Composer<_$AppDatabase, $PortForwardConfigsTable> {
  $$PortForwardConfigsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bindHost => $composableBuilder(
    column: $table.bindHost,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bindPort => $composableBuilder(
    column: $table.bindPort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetHost => $composableBuilder(
    column: $table.targetHost,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetPort => $composableBuilder(
    column: $table.targetPort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoStart => $composableBuilder(
    column: $table.autoStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PortForwardConfigsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PortForwardConfigsTable> {
  $$PortForwardConfigsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get bindHost =>
      $composableBuilder(column: $table.bindHost, builder: (column) => column);

  GeneratedColumn<int> get bindPort =>
      $composableBuilder(column: $table.bindPort, builder: (column) => column);

  GeneratedColumn<String> get targetHost => $composableBuilder(
    column: $table.targetHost,
    builder: (column) => column,
  );

  GeneratedColumn<int> get targetPort => $composableBuilder(
    column: $table.targetPort,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get autoStart =>
      $composableBuilder(column: $table.autoStart, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PortForwardConfigsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PortForwardConfigsTable,
          PortForwardConfig,
          $$PortForwardConfigsTableFilterComposer,
          $$PortForwardConfigsTableOrderingComposer,
          $$PortForwardConfigsTableAnnotationComposer,
          $$PortForwardConfigsTableCreateCompanionBuilder,
          $$PortForwardConfigsTableUpdateCompanionBuilder,
          (
            PortForwardConfig,
            BaseReferences<
              _$AppDatabase,
              $PortForwardConfigsTable,
              PortForwardConfig
            >,
          ),
          PortForwardConfig,
          PrefetchHooks Function()
        > {
  $$PortForwardConfigsTableTableManager(
    _$AppDatabase db,
    $PortForwardConfigsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PortForwardConfigsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PortForwardConfigsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PortForwardConfigsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> serverId = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> bindHost = const Value.absent(),
                Value<int> bindPort = const Value.absent(),
                Value<String> targetHost = const Value.absent(),
                Value<int> targetPort = const Value.absent(),
                Value<bool> autoStart = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => PortForwardConfigsCompanion(
                id: id,
                serverId: serverId,
                direction: direction,
                kind: kind,
                bindHost: bindHost,
                bindPort: bindPort,
                targetHost: targetHost,
                targetPort: targetPort,
                autoStart: autoStart,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int serverId,
                required String direction,
                required String kind,
                required String bindHost,
                required int bindPort,
                required String targetHost,
                required int targetPort,
                Value<bool> autoStart = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
              }) => PortForwardConfigsCompanion.insert(
                id: id,
                serverId: serverId,
                direction: direction,
                kind: kind,
                bindHost: bindHost,
                bindPort: bindPort,
                targetHost: targetHost,
                targetPort: targetPort,
                autoStart: autoStart,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PortForwardConfigsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PortForwardConfigsTable,
      PortForwardConfig,
      $$PortForwardConfigsTableFilterComposer,
      $$PortForwardConfigsTableOrderingComposer,
      $$PortForwardConfigsTableAnnotationComposer,
      $$PortForwardConfigsTableCreateCompanionBuilder,
      $$PortForwardConfigsTableUpdateCompanionBuilder,
      (
        PortForwardConfig,
        BaseReferences<
          _$AppDatabase,
          $PortForwardConfigsTable,
          PortForwardConfig
        >,
      ),
      PortForwardConfig,
      PrefetchHooks Function()
    >;
typedef $$RuntimeWatchConfigsTableCreateCompanionBuilder =
    RuntimeWatchConfigsCompanion Function({
      required int serverId,
      required String runtime,
      Value<bool> enabled,
      Value<bool> pinned,
      Value<int> rowid,
    });
typedef $$RuntimeWatchConfigsTableUpdateCompanionBuilder =
    RuntimeWatchConfigsCompanion Function({
      Value<int> serverId,
      Value<String> runtime,
      Value<bool> enabled,
      Value<bool> pinned,
      Value<int> rowid,
    });

class $$RuntimeWatchConfigsTableFilterComposer
    extends Composer<_$AppDatabase, $RuntimeWatchConfigsTable> {
  $$RuntimeWatchConfigsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get runtime => $composableBuilder(
    column: $table.runtime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RuntimeWatchConfigsTableOrderingComposer
    extends Composer<_$AppDatabase, $RuntimeWatchConfigsTable> {
  $$RuntimeWatchConfigsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get runtime => $composableBuilder(
    column: $table.runtime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RuntimeWatchConfigsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RuntimeWatchConfigsTable> {
  $$RuntimeWatchConfigsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get runtime =>
      $composableBuilder(column: $table.runtime, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);
}

class $$RuntimeWatchConfigsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RuntimeWatchConfigsTable,
          RuntimeWatchConfig,
          $$RuntimeWatchConfigsTableFilterComposer,
          $$RuntimeWatchConfigsTableOrderingComposer,
          $$RuntimeWatchConfigsTableAnnotationComposer,
          $$RuntimeWatchConfigsTableCreateCompanionBuilder,
          $$RuntimeWatchConfigsTableUpdateCompanionBuilder,
          (
            RuntimeWatchConfig,
            BaseReferences<
              _$AppDatabase,
              $RuntimeWatchConfigsTable,
              RuntimeWatchConfig
            >,
          ),
          RuntimeWatchConfig,
          PrefetchHooks Function()
        > {
  $$RuntimeWatchConfigsTableTableManager(
    _$AppDatabase db,
    $RuntimeWatchConfigsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RuntimeWatchConfigsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RuntimeWatchConfigsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RuntimeWatchConfigsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> serverId = const Value.absent(),
                Value<String> runtime = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RuntimeWatchConfigsCompanion(
                serverId: serverId,
                runtime: runtime,
                enabled: enabled,
                pinned: pinned,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int serverId,
                required String runtime,
                Value<bool> enabled = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RuntimeWatchConfigsCompanion.insert(
                serverId: serverId,
                runtime: runtime,
                enabled: enabled,
                pinned: pinned,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RuntimeWatchConfigsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RuntimeWatchConfigsTable,
      RuntimeWatchConfig,
      $$RuntimeWatchConfigsTableFilterComposer,
      $$RuntimeWatchConfigsTableOrderingComposer,
      $$RuntimeWatchConfigsTableAnnotationComposer,
      $$RuntimeWatchConfigsTableCreateCompanionBuilder,
      $$RuntimeWatchConfigsTableUpdateCompanionBuilder,
      (
        RuntimeWatchConfig,
        BaseReferences<
          _$AppDatabase,
          $RuntimeWatchConfigsTable,
          RuntimeWatchConfig
        >,
      ),
      RuntimeWatchConfig,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
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

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
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

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
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

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
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

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ServersTableTableManager get servers =>
      $$ServersTableTableManager(_db, _db.servers);
  $$SavedCredentialsTableTableManager get savedCredentials =>
      $$SavedCredentialsTableTableManager(_db, _db.savedCredentials);
  $$VaultMetadataTableTableManager get vaultMetadata =>
      $$VaultMetadataTableTableManager(_db, _db.vaultMetadata);
  $$ComposeProjectLinksTableTableManager get composeProjectLinks =>
      $$ComposeProjectLinksTableTableManager(_db, _db.composeProjectLinks);
  $$ContainerCacheEntriesTableTableManager get containerCacheEntries =>
      $$ContainerCacheEntriesTableTableManager(_db, _db.containerCacheEntries);
  $$DeploymentProjectsTableTableManager get deploymentProjects =>
      $$DeploymentProjectsTableTableManager(_db, _db.deploymentProjects);
  $$DeploymentResourcesTableTableManager get deploymentResources =>
      $$DeploymentResourcesTableTableManager(_db, _db.deploymentResources);
  $$ScriptSnippetsTableTableManager get scriptSnippets =>
      $$ScriptSnippetsTableTableManager(_db, _db.scriptSnippets);
  $$AgentSettingsTableTableManager get agentSettings =>
      $$AgentSettingsTableTableManager(_db, _db.agentSettings);
  $$AgentProvidersTableTableManager get agentProviders =>
      $$AgentProvidersTableTableManager(_db, _db.agentProviders);
  $$AgentProviderModelsTableTableManager get agentProviderModels =>
      $$AgentProviderModelsTableTableManager(_db, _db.agentProviderModels);
  $$McpServersTableTableManager get mcpServers =>
      $$McpServersTableTableManager(_db, _db.mcpServers);
  $$AgentSkillsTableTableManager get agentSkills =>
      $$AgentSkillsTableTableManager(_db, _db.agentSkills);
  $$GitHubConnectionsTableTableManager get gitHubConnections =>
      $$GitHubConnectionsTableTableManager(_db, _db.gitHubConnections);
  $$GitHubRepoPinsTableTableManager get gitHubRepoPins =>
      $$GitHubRepoPinsTableTableManager(_db, _db.gitHubRepoPins);
  $$GitHubTokensTableTableManager get gitHubTokens =>
      $$GitHubTokensTableTableManager(_db, _db.gitHubTokens);
  $$PortForwardConfigsTableTableManager get portForwardConfigs =>
      $$PortForwardConfigsTableTableManager(_db, _db.portForwardConfigs);
  $$RuntimeWatchConfigsTableTableManager get runtimeWatchConfigs =>
      $$RuntimeWatchConfigsTableTableManager(_db, _db.runtimeWatchConfigs);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
}
