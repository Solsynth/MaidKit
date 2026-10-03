/// A container runtime available on a managed server.
enum ContainerRuntime { docker, podman }

/// Containers can belong either to the connected user or to the host root
/// environment. Root operations require passwordless sudo on the server.
enum ContainerScope { user, root }

/// The interactive command run in a container terminal.
String buildContainerExecCommand({
  required ContainerRuntime runtime,
  required String containerId,
  required String command,
}) {
  final flags = '-it';
  return '${runtime.name} exec $flags ${_shellQuote(containerId)} '
      'sh -c ${_shellQuote(command)}';
}

/// The interactive command that attaches to a running container's main
/// process.
String buildContainerAttachCommand({
  required ContainerRuntime runtime,
  required String containerId,
}) => '${runtime.name} attach ${_shellQuote(containerId)}';

/// Wraps an interactive container command in the remote shell's privilege
/// boundary.
String buildContainerTerminalScript({
  required ContainerScope scope,
  required String command,
}) => switch (scope) {
  ContainerScope.user => 'exec $command',
  // `-S` keeps the password prompt on the terminal's stdin, so interactive
  // sessions can use either passwordless sudo or the configured user password
  // without embedding a credential in the initial command script.
  ContainerScope.root => 'exec sudo -S $command',
};

String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

/// Lifecycle actions for a single container (`docker|podman <verb> <id>`).
///
/// [remove] maps to `rm`. When the container is still running, callers should
/// pass `force: true` to `runContainerAction` so the runtime uses `rm -f`.
enum ContainerAction { start, stop, restart, pause, unpause, kill, remove }

extension ContainerActionX on ContainerAction {
  /// Short label for menus and confirmation buttons.
  String get label => switch (this) {
    ContainerAction.start => 'Start',
    ContainerAction.stop => 'Stop',
    ContainerAction.restart => 'Restart',
    ContainerAction.pause => 'Pause',
    ContainerAction.unpause => 'Unpause',
    ContainerAction.kill => 'Kill',
    ContainerAction.remove => 'Delete',
  };

  /// Past-tense snackbar title fragment, e.g. "Container stopped".
  String get pastLabel => switch (this) {
    ContainerAction.start => 'started',
    ContainerAction.stop => 'stopped',
    ContainerAction.restart => 'restarted',
    ContainerAction.pause => 'paused',
    ContainerAction.unpause => 'unpaused',
    ContainerAction.kill => 'killed',
    ContainerAction.remove => 'deleted',
  };

  /// Subcommand verb passed to the runtime CLI (not always [name]).
  String get cliVerb => switch (this) {
    ContainerAction.remove => 'rm',
    _ => name,
  };

  /// Whether the action can interrupt or destroy a running workload.
  bool get isDestructive => switch (this) {
    ContainerAction.stop ||
    ContainerAction.kill ||
    ContainerAction.remove => true,
    _ => false,
  };

  /// Whether the UI should prompt before running the action.
  bool get requiresConfirmation =>
      isDestructive || this == ContainerAction.restart;
}

/// Actions available for a local container image.
enum ImageAction { remove }

/// Lifecycle / maintenance actions for a linked compose project.
///
/// Labels are short menu titles; [composeArgs] is the `compose` subcommand
/// string appended after `docker|podman compose -p <name>`.
enum ComposeProjectAction {
  /// `compose pull` — fetch service images without starting containers.
  pull,

  /// `compose up -d` — create/start services in the background.
  up,

  /// `compose stop` — stop running services; leave containers in place.
  stop,

  /// `compose restart` — restart existing containers.
  restart,

  /// `compose up -d --force-recreate` — recreate containers even if config is unchanged.
  recreate;

  /// Short label for menus and snackbars.
  String get label => switch (this) {
    ComposeProjectAction.pull => 'Pull images',
    ComposeProjectAction.up => 'Start',
    ComposeProjectAction.stop => 'Stop',
    ComposeProjectAction.restart => 'Restart',
    ComposeProjectAction.recreate => 'Force recreate',
  };

  /// Present-participle used in loading / terminal titles.
  String get progressLabel => switch (this) {
    ComposeProjectAction.pull => 'Pulling images',
    ComposeProjectAction.up => 'Starting',
    ComposeProjectAction.stop => 'Stopping',
    ComposeProjectAction.restart => 'Restarting',
    ComposeProjectAction.recreate => 'Force recreating',
  };

  /// Arguments after `compose -p <project>`.
  String get composeArgs => switch (this) {
    ComposeProjectAction.pull => 'pull',
    ComposeProjectAction.up => 'up -d',
    ComposeProjectAction.stop => 'stop',
    ComposeProjectAction.restart => 'restart',
    ComposeProjectAction.recreate => 'up -d --force-recreate',
  };
}

class ServerContainer {
  const ServerContainer({
    required this.id,
    required this.name,
    required this.image,
    required this.state,
    required this.status,
    this.composeProject,
  });

  final String id;
  final String name;
  final String image;
  final String state;
  final String status;

  /// The Docker or Podman Compose project label assigned to this container.
  final String? composeProject;
}

/// Live resource sample from `docker stats` / `podman stats`.
class ContainerStats {
  const ContainerStats({
    required this.id,
    required this.name,
    this.cpuPercent,
    this.memUsage = '',
    this.memPercent,
    this.memUsedBytes,
    this.memLimitBytes,
    this.netIO = '',
    this.netRxBytes,
    this.netTxBytes,
    this.blockIO = '',
    this.blockReadBytes,
    this.blockWriteBytes,
    this.pids,
  });

  final String id;
  final String name;
  final double? cpuPercent;
  final String memUsage;
  final double? memPercent;
  final int? memUsedBytes;
  final int? memLimitBytes;
  final String netIO;
  final int? netRxBytes;
  final int? netTxBytes;
  final String blockIO;
  final int? blockReadBytes;
  final int? blockWriteBytes;
  final int? pids;

  /// Reads the daemon's normalized stats payload
  /// (`GET /api/v1/containers/:id/stats`).
  ///
  /// The daemon has already reconciled the two runtimes' shapes and answers
  /// null for a measurement it could not take — a rootless runtime reports
  /// `--` for what it cannot see. The composite strings the SSH path gets from
  /// the runtime's own formatting are rebuilt here so both paths feed the same
  /// widgets.
  factory ContainerStats.fromDaemonJson(Map<String, dynamic> json) {
    final name = json['name']?.toString() ?? '';
    final memoryUsed = _intOrNull(json['memory_usage_bytes']);
    final memoryLimit = _intOrNull(json['memory_limit_bytes']);
    final networkIn = _intOrNull(json['network_input_bytes']);
    final networkOut = _intOrNull(json['network_output_bytes']);
    final blockIn = _intOrNull(json['block_input_bytes']);
    final blockOut = _intOrNull(json['block_output_bytes']);
    return ContainerStats(
      id: json['container']?.toString() ?? '',
      name: name.startsWith('/') ? name.substring(1) : name,
      cpuPercent: _doubleOrNull(json['cpu_percent']),
      memUsage: memoryUsed == null && memoryLimit == null
          ? ''
          : '${formatBytes(memoryUsed)} / ${formatBytes(memoryLimit)}',
      memPercent: _doubleOrNull(json['memory_percent']),
      memUsedBytes: memoryUsed,
      memLimitBytes: memoryLimit,
      netIO: networkIn == null && networkOut == null
          ? ''
          : '${formatBytes(networkIn)} / ${formatBytes(networkOut)}',
      netRxBytes: networkIn,
      netTxBytes: networkOut,
      blockIO: blockIn == null && blockOut == null
          ? ''
          : '${formatBytes(blockIn)} / ${formatBytes(blockOut)}',
      blockReadBytes: blockIn,
      blockWriteBytes: blockOut,
      pids: _intOrNull(json['pids']),
    );
  }
}

/// One container's published-image comparison, as reported by
/// `GET /api/v1/updates` and `GET /api/v1/containers/:id/update-check`.
class ContainerUpdateStatus {
  const ContainerUpdateStatus({
    required this.container,
    required this.name,
    required this.runtime,
    required this.image,
    this.checkedAt,
    this.outdated,
    this.pinned = false,
    this.restartRequired = false,
    this.localDigest = '',
    this.remoteDigest = '',
    this.error,
  });

  /// The container id the daemon's list reports.
  final String container;
  final String name;
  final String runtime;

  /// The image reference the container was created from.
  final String image;
  final DateTime? checkedAt;

  /// True when the registry publishes an image the container is not running,
  /// false when it is current, and null when the question could not be
  /// answered — [error] then says why.
  final bool? outdated;

  /// The container was created from a digest-pinned reference, which is never
  /// outdated: the digest is what the operator asked for.
  final bool pinned;

  /// The local image store already holds a newer image than this container is
  /// running, so a recreate applies it without downloading anything.
  final bool restartRequired;
  final String localDigest;
  final String remoteDigest;
  final String? error;

  /// Whether the daemon has an update to act on: the registry has moved on, or
  /// a newer image is already on the host.
  bool get hasUpdate => outdated == true || restartRequired;

  static ContainerUpdateStatus fromDaemonJson(Map<String, dynamic> json) {
    final checked = json['checked_at']?.toString();
    return ContainerUpdateStatus(
      container: json['container']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      runtime: json['runtime']?.toString() ?? '',
      image: json['image']?.toString() ?? '',
      checkedAt: checked == null || checked.isEmpty
          ? null
          : DateTime.tryParse(checked)?.toLocal(),
      outdated: json['outdated'] is bool ? json['outdated'] as bool : null,
      pinned: json['pinned'] == true,
      restartRequired: json['restart_required'] == true,
      localDigest: json['local_digest']?.toString() ?? '',
      remoteDigest: json['remote_digest']?.toString() ?? '',
      error: json['error']?.toString(),
    );
  }
}

/// Every cached update status the daemon holds, plus the cadence it refreshes
/// them on.
class ContainerUpdates {
  const ContainerUpdates({
    this.intervalSeconds = 0,
    this.containers = const [],
  });

  /// How often the daemon re-checks, so a client can tell how old the answers
  /// are and when they will move.
  final int intervalSeconds;
  final List<ContainerUpdateStatus> containers;

  /// The status for one container, matched by the id the daemon's list reports
  /// (either way may be a prefix of the other, since the two surfaces that
  /// paint badges hold different identifiers) and then by name.
  ContainerUpdateStatus? forContainer(String id, {String? name}) {
    if (id.isNotEmpty) {
      for (final status in containers) {
        final key = status.container;
        if (key.isEmpty) continue;
        if (key == id || key.startsWith(id) || id.startsWith(key)) {
          return status;
        }
      }
    }
    if (name == null) return null;
    final clean = name.startsWith('/') ? name.substring(1) : name;
    for (final status in containers) {
      final statusName = status.name.startsWith('/')
          ? status.name.substring(1)
          : status.name;
      if (statusName == clean) return status;
    }
    return null;
  }
}

/// Tolerant parse of an update payload, for both the batch and single-container
/// endpoints (the latter nests the status under `container`).
ContainerUpdates parseContainerUpdates(
  Map<String, dynamic> json, {
  bool single = false,
}) {
  if (single) {
    final nested = json['container'];
    if (nested is Map) {
      return ContainerUpdates(
        containers: [
          ContainerUpdateStatus.fromDaemonJson(
            nested.map((key, value) => MapEntry(key.toString(), value)),
          ),
        ],
      );
    }
    return ContainerUpdates(
      containers: [ContainerUpdateStatus.fromDaemonJson(json)],
    );
  }
  final entries = json['containers'];
  return ContainerUpdates(
    intervalSeconds: _intOrNull(json['interval_seconds']) ?? 0,
    containers: [
      if (entries is List)
        for (final entry in entries)
          if (entry is Map)
            ContainerUpdateStatus.fromDaemonJson(
              entry.map((key, value) => MapEntry(key.toString(), value)),
            ),
    ],
  );
}

/// One captured log line from the daemon's tail.
class ContainerLogLine {
  const ContainerLogLine({required this.timestamp, required this.line});

  final DateTime? timestamp;
  final String line;
}

/// Reads the `lines` array of a daemon log payload, from either the one-shot
/// `/logs` endpoint or a `logs` SSE frame.
List<ContainerLogLine> parseContainerLogLines(Map<String, dynamic> json) {
  final entries = json['lines'];
  if (entries is! List) return const [];
  return [
    for (final entry in entries)
      if (entry is Map)
        ContainerLogLine(
          timestamp: DateTime.tryParse(
            entry['ts']?.toString() ?? '',
          )?.toLocal(),
          line: entry['line']?.toString() ?? '',
        ),
  ];
}

/// Formats [bytes] the way the container tiles render a runtime's own
/// numbers; null stays a placeholder rather than becoming `0 B`.
String formatBytes(int? bytes) {
  if (bytes == null) return '—';
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(1)} KB';
  return '$bytes B';
}

int? _intOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? _doubleOrNull(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

class ContainerEnvironment {
  const ContainerEnvironment({
    required this.runtime,
    required this.scope,
    this.containers = const [],
    this.error,
  });

  final ContainerRuntime runtime;
  final ContainerScope scope;
  final List<ServerContainer> containers;
  final String? error;

  bool get isAvailable => error == null;
}

/// A local image from `docker images` / `podman images`.
class ServerContainerImage {
  const ServerContainerImage({
    required this.id,
    required this.repository,
    required this.tag,
    required this.size,
    required this.created,
    this.unused = false,
  });

  final String id;
  final String repository;
  final String tag;

  /// Human-readable size from the runtime (e.g. `128MB`).
  final String size;

  /// Relative created age from the runtime (e.g. `2 weeks ago`).
  final String created;

  /// True when no container references this image (includes dangling images).
  final bool unused;

  /// `repository:tag`, or the short id when the image is dangling.
  String get reference {
    final repo = repository.trim();
    final imageTag = tag.trim();
    if (repo.isEmpty || repo == '<none>') {
      return id;
    }
    if (imageTag.isEmpty || imageTag == '<none>') {
      return repo;
    }
    return '$repo:$imageTag';
  }

  bool get isDangling {
    final repo = repository.trim();
    final imageTag = tag.trim();
    return repo.isEmpty ||
        repo == '<none>' ||
        imageTag.isEmpty ||
        imageTag == '<none>';
  }

  ServerContainerImage copyWith({bool? unused}) => ServerContainerImage(
    id: id,
    repository: repository,
    tag: tag,
    size: size,
    created: created,
    unused: unused ?? this.unused,
  );
}

/// Images listed for one runtime + scope combination on a server.
class ImageEnvironment {
  const ImageEnvironment({
    required this.runtime,
    required this.scope,
    this.images = const [],
    this.error,
  });

  final ContainerRuntime runtime;
  final ContainerScope scope;
  final List<ServerContainerImage> images;
  final String? error;

  bool get isAvailable => error == null;

  int get unusedCount => images.where((image) => image.unused).length;
}

/// Structured result of `docker|podman inspect` for a single container.
class ContainerInspectDetail {
  const ContainerInspectDetail({
    required this.id,
    required this.name,
    required this.image,
    required this.state,
    required this.status,
    required this.created,
    required this.startedAt,
    required this.finishedAt,
    required this.exitCode,
    required this.platform,
    required this.restartPolicy,
    required this.networkMode,
    required this.workingDir,
    required this.user,
    required this.entrypoint,
    required this.command,
    required this.env,
    required this.ports,
    required this.binds,
    required this.mounts,
    required this.labels,
    required this.networks,
    required this.rawJson,
  });

  final String id;
  final String name;
  final String image;
  final String state;
  final String status;
  final String? created;
  final String? startedAt;
  final String? finishedAt;
  final int? exitCode;
  final String? platform;
  final String restartPolicy;
  final String networkMode;
  final String? workingDir;
  final String? user;
  final List<String> entrypoint;
  final List<String> command;
  final List<String> env;
  final List<String> ports;
  final List<String> binds;
  final List<String> mounts;
  final Map<String, String> labels;
  final List<String> networks;
  final String rawJson;

  /// Reads a runtime's own inspect object.
  ///
  /// Both paths answer with the same document — `docker|podman inspect
  /// --format '{{json .}}'` over SSH and the daemon's `/containers/:id/inspect`
  /// pass the runtime's object through unmodified — so one parser serves them.
  /// [rawJson] is that object as the runtime rendered it, kept for the raw
  /// payload view.
  factory ContainerInspectDetail.fromInspectJson(
    Map<String, dynamic> json, {
    required String rawJson,
  }) {
    final state = _asMap(json['State']);
    final config = _asMap(json['Config']);
    final hostConfig = _asMap(json['HostConfig']);
    final networkSettings = _asMap(json['NetworkSettings']);
    final restart = _asMap(hostConfig['RestartPolicy']);
    final nameRaw = json['Name']?.toString() ?? '';
    final name = nameRaw.startsWith('/') ? nameRaw.substring(1) : nameRaw;

    final env = <String>[
      for (final item in _asList(config['Env']))
        if (item.toString().isNotEmpty) item.toString(),
    ];
    final entrypoint = <String>[
      for (final item in _asList(config['Entrypoint'])) item.toString(),
    ];
    final command = <String>[
      for (final item in _asList(config['Cmd'])) item.toString(),
    ];
    final binds = <String>[
      for (final item in _asList(hostConfig['Binds'])) item.toString(),
    ];
    final mounts = <String>[];
    for (final item in _asList(json['Mounts'])) {
      final mount = _asMap(item);
      final source = mount['Source']?.toString() ?? '';
      final destination = mount['Destination']?.toString() ?? '';
      if (source.isEmpty || destination.isEmpty) continue;
      final mode = mount['Mode']?.toString() ?? '';
      mounts.add(
        mode.isEmpty ? '$source:$destination' : '$source:$destination:$mode',
      );
    }
    final ports = <String>[];
    final portBindings = _asMap(hostConfig['PortBindings']);
    for (final entry in portBindings.entries) {
      final containerPort = entry.key.toString(); // e.g. 80/tcp
      final bindings = _asList(entry.value);
      if (bindings.isEmpty) {
        ports.add(containerPort.replaceAll('/tcp', '').replaceAll('/udp', ''));
        continue;
      }
      for (final binding in bindings) {
        final map = _asMap(binding);
        final hostIp = map['HostIp']?.toString() ?? '';
        final hostPort = map['HostPort']?.toString() ?? '';
        final containerOnly = containerPort.split('/').first;
        if (hostPort.isEmpty) {
          ports.add(containerOnly);
        } else if (hostIp.isEmpty || hostIp == '0.0.0.0' || hostIp == '::') {
          ports.add('$hostPort:$containerOnly');
        } else {
          ports.add('$hostIp:$hostPort:$containerOnly');
        }
      }
    }
    final labels = <String, String>{};
    final labelMap = _asMap(config['Labels']);
    for (final entry in labelMap.entries) {
      labels[entry.key.toString()] = entry.value?.toString() ?? '';
    }
    final networks = <String>[];
    final networksMap = _asMap(networkSettings['Networks']);
    networks.addAll(networksMap.keys.map((key) => key.toString()));

    final stateName =
        state['Status']?.toString() ?? state['status']?.toString() ?? '';
    final status = [
      if (stateName.isNotEmpty) stateName,
      if (state['Error']?.toString().isNotEmpty == true) state['Error'],
      if (state['ExitCode'] != null && stateName != 'running')
        'exit ${state['ExitCode']}',
    ].join(' · ');

    return ContainerInspectDetail(
      id: json['Id']?.toString() ?? '',
      name: name,
      image: config['Image']?.toString() ?? json['Image']?.toString() ?? '',
      state: stateName,
      status: status.isEmpty ? stateName : status,
      created: json['Created']?.toString(),
      startedAt: state['StartedAt']?.toString(),
      finishedAt: state['FinishedAt']?.toString(),
      exitCode: int.tryParse(state['ExitCode']?.toString() ?? ''),
      platform: json['Platform']?.toString() ?? config['Platform']?.toString(),
      restartPolicy: restart['Name']?.toString() ?? 'no',
      networkMode: hostConfig['NetworkMode']?.toString() ?? 'default',
      workingDir: config['WorkingDir']?.toString(),
      user: config['User']?.toString(),
      entrypoint: entrypoint,
      command: command,
      env: env,
      ports: ports,
      binds: binds.isNotEmpty ? binds : mounts,
      mounts: mounts,
      labels: labels,
      networks: networks,
      rawJson: rawJson,
    );
  }

  bool get isRunning {
    final value = state.toLowerCase();
    return value.contains('running') ||
        value == 'up' ||
        value.contains('paused');
  }

  bool get isPaused => state.toLowerCase().contains('paused');

  /// Best-effort `run` command reconstructed from inspect data.
  ///
  /// Not every HostConfig flag is preserved; this covers the options MaidKit
  /// exposes in the run form and common production mounts/ports/env.
  String rerunCommand(ContainerRuntime runtime) {
    final parts = <String>[runtime.name, 'run', '-d'];
    final cleanName = name.startsWith('/') ? name.substring(1) : name;
    if (cleanName.isNotEmpty) {
      parts.addAll(['--name', cleanName]);
    }
    if (restartPolicy.isNotEmpty && restartPolicy != 'no') {
      parts.addAll(['--restart', restartPolicy]);
    }
    if (networkMode.isNotEmpty &&
        networkMode != 'default' &&
        networkMode != 'bridge') {
      parts.addAll(['--network', networkMode]);
    }
    if (user != null && user!.isNotEmpty) {
      parts.addAll(['--user', user!]);
    }
    if (workingDir != null && workingDir!.isNotEmpty) {
      parts.addAll(['-w', workingDir!]);
    }
    for (final port in ports) {
      parts.addAll(['-p', port]);
    }
    for (final bind in binds) {
      parts.addAll(['-v', bind]);
    }
    for (final variable in env) {
      // Skip PATH-like image defaults that make re-run noisy when empty-ish.
      if (variable.startsWith('PATH=')) continue;
      parts.addAll(['-e', variable]);
    }
    for (final entry in labels.entries) {
      // Compose labels are noisy in re-run copies.
      if (entry.key.startsWith('com.docker.compose.') ||
          entry.key.startsWith('io.podman.compose.')) {
        continue;
      }
      parts.addAll(['--label', '${entry.key}=${entry.value}']);
    }
    parts.add(image.isEmpty ? '<image>' : image);
    if (command.isNotEmpty) {
      parts.addAll(command);
    }
    return parts.map(_shellToken).join(' ');
  }

  static String _shellToken(String value) {
    if (RegExp(r'^[a-zA-Z0-9_./:@%+=,-]+$').hasMatch(value)) return value;
    return "'${value.replaceAll("'", "'\\''")}'";
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

List<dynamic> _asList(Object? value) => value is List ? value : const [];
