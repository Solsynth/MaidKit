import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_ping/dart_ping.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:maid_kit/containers/container_models.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'activity_models.dart';
import 'crontab_models.dart';
import 'firewall_models.dart';
import 'package_models.dart';
import 'port_forwarding_models.dart';
import 'runtime_metrics_collector.dart';
import 'server_metrics_collector.dart';
import 'server_models.dart';
import 'ssh_proxy_connect.dart';
import 'socks5_protocol.dart';
import 'systemd_models.dart';
import 'tailscale_ssh_socket.dart';
import 'tailscale_service.dart';
import 'terminal_session_adapter.dart';
import 'web_server_adapter.dart';
import 'web_server_adapters.dart';
import 'web_server_models.dart';

typedef HostKeyApproval = Future<bool> Function(HostKeyPrompt prompt);

class SshConnectionManager {
  SshConnectionManager(
    this._terminalAdapterFactory, {
    bool Function()? brandingEnvironmentEnabled,
    ServerMetricsCollector? metricsCollector,
    this.onConnected,
  }) : _brandingEnvironmentEnabled = brandingEnvironmentEnabled ?? (() => true),
       _metricsCollector = metricsCollector ?? AutoServerMetricsCollector();

  final TerminalSessionAdapterFactory Function() _terminalAdapterFactory;
  final bool Function() _brandingEnvironmentEnabled;
  final ServerMetricsCollector _metricsCollector;

  /// Fired after a server's SSH session becomes connected. Used to start
  /// saved port-forwarding presets that opted into auto-start. Failures are
  /// handled by the caller; the connection itself is unaffected.
  final void Function(Server server)? onConnected;

  /// These clients are used exclusively for collecting server information.
  /// Terminal shells keep their own clients so reconnecting statistics never
  /// interrupts an interactive session.
  final _sessions = <int, SSHClient>{};

  /// Immediate jump-host relationships for retained SSH sessions. Keeping
  /// these relationships lets a disconnected parent tear down its children.
  final _sessionJumpHosts = <int, int?>{};
  final _terminals = <String, _TerminalConnection>{};

  /// Non-interactive SSH commands do not source the user's shell profile.
  /// Include common Homebrew and Docker Desktop locations explicitly so
  /// user-installed tools are discoverable on macOS and Linuxbrew hosts.
  static const _remoteToolPath =
      '/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:'
      '/Applications/Docker.app/Contents/Resources/bin';
  final _controller = StreamController<List<SshSessionInfo>>.broadcast();
  final _portForwardController =
      StreamController<List<ActivePortForward>>.broadcast();
  final _states = <int, SshSessionInfo>{};
  final _portForwards = <String, _PortForwardingConnection>{};
  var _nextTerminalId = 0;
  var _nextPortForwardId = 0;

  Stream<List<SshSessionInfo>> get sessions => _controller.stream;
  List<SshSessionInfo> get current => _states.values.toList();
  Stream<List<ActivePortForward>> get portForwards =>
      _portForwardController.stream;
  List<ActivePortForward> get currentPortForwards =>
      _portForwards.values.map((forward) => forward.info).toList();

  Future<ActivePortForward> startPortForward({
    required Server server,
    required PortForwardDirection direction,
    required PortForwardKind kind,
    required String bindHost,
    required int bindPort,
    String targetHost = '',
    int targetPort = 0,
    PortForwardOwner owner = PortForwardOwner.user,
  }) async {
    final client = clientFor(server.id);
    if (client == null) throw const ServerConnectionRequiredException();
    if (kind == PortForwardKind.socks5 &&
        direction == PortForwardDirection.remote) {
      throw ArgumentError(
        'SOCKS5 forwarding is only available in the local direction.',
      );
    }
    final id = 'forward-${_nextPortForwardId++}';
    var info = ActivePortForward(
      id: id,
      serverId: server.id,
      serverName: server.name,
      direction: direction,
      kind: kind,
      bindHost: bindHost,
      bindPort: bindPort,
      targetHost: targetHost,
      targetPort: targetPort,
      owner: owner,
    );

    late final _PortForwardingConnection connection;
    if (direction == PortForwardDirection.local) {
      final listener = await ServerSocket.bind(bindHost, bindPort);
      info = info.copyWith(bindPort: listener.port);
      connection = _PortForwardingConnection.local(info, listener);
      connection.subscription = listener.listen(
        (socket) {
          unawaited(
            kind == PortForwardKind.socks5
                ? _pipeSocks5Connection(client, socket)
                : _pipeLocalConnection(client, socket, targetHost, targetPort),
          );
        },
        onError: (_, _) => unawaited(_stopPortForward(id, allowManaged: true)),
      );
    } else {
      final remote = await client.forwardRemote(host: bindHost, port: bindPort);
      if (remote == null) {
        throw StateError(
          'The SSH server refused to listen on $bindHost:$bindPort.',
        );
      }
      connection = _PortForwardingConnection.remote(info, remote);
      connection.subscription = remote.connections.listen(
        (channel) {
          unawaited(_pipeRemoteConnection(channel, targetHost, targetPort));
        },
        onError: (_, _) => unawaited(_stopPortForward(id, allowManaged: true)),
      );
    }
    _portForwards[id] = connection;
    _emitPortForwards();
    return info;
  }

  Future<void> stopPortForward(String id) => _stopPortForward(id);

  /// Stops a MaidCafe-owned forward during its owner session cleanup.
  Future<void> stopManagedPortForward(String id) =>
      _stopPortForward(id, allowManaged: true);

  Future<void> _stopPortForward(String id, {bool allowManaged = false}) async {
    final forward = _portForwards[id];
    if (forward == null || (forward.info.isManaged && !allowManaged)) {
      return;
    }
    _portForwards.remove(id);
    await forward.close();
    _emitPortForwards();
  }

  Future<void> _pipeLocalConnection(
    SSHClient client,
    Socket socket,
    String targetHost,
    int targetPort,
  ) async {
    try {
      final channel = await client.forwardLocal(
        targetHost,
        targetPort,
        localHost: socket.remoteAddress.address,
        localPort: socket.remotePort,
      );
      unawaited(channel.stream.cast<List<int>>().pipe(socket));
      unawaited(socket.cast<List<int>>().pipe(channel.sink));
    } catch (_) {
      await socket.close();
    }
  }

  /// Runs a SOCKS5 server handshake on a locally accepted [socket], then
  /// tunnels the client's traffic to the destination it chose over an SSH
  /// direct-tcpip channel. DNS for domain destinations happens on the SSH
  /// server, matching plain TCP forwarding.
  Future<void> _pipeSocks5Connection(SSHClient client, Socket socket) async {
    final handshake = Socks5ServerHandshake(socket, socket);
    try {
      final destination = await handshake.negotiate();
      final channel = await client.forwardLocal(
        destination.host,
        destination.port,
        localHost: socket.remoteAddress.address,
        localPort: socket.remotePort,
      );
      handshake.startPump();
      unawaited(handshake.stream.cast<List<int>>().pipe(channel.sink));
      unawaited(channel.stream.cast<List<int>>().pipe(socket));
    } on Socks5ProtocolException {
      // The failure reply was already sent (or none applies); just close.
      await handshake.dispose();
      await socket.close();
    } catch (_) {
      // The handshake succeeded but the tunnel could not be opened.
      try {
        socket.add(const [0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
      } catch (_) {}
      await handshake.dispose();
      await socket.close();
    }
  }

  Future<void> _pipeRemoteConnection(
    SSHForwardChannel channel,
    String targetHost,
    int targetPort,
  ) async {
    try {
      final socket = await Socket.connect(targetHost, targetPort);
      unawaited(channel.stream.cast<List<int>>().pipe(socket));
      unawaited(socket.cast<List<int>>().pipe(channel.sink));
    } catch (_) {
      await channel.sink.close();
    }
  }

  void _emitPortForwards() => _portForwardController.add(currentPortForwards);

  /// Returns the retained authenticated client for [serverId], if available.
  ///
  /// Feature code should reuse this client for remote operations instead of
  /// opening a second transport connection.
  SSHClient? clientFor(int serverId) {
    final client = _sessions[serverId];
    return client == null || client.isClosed ? null : client;
  }

  Future<T> withClient<T>(
    int serverId,
    Future<T> Function(SSHClient client) run,
  ) {
    final client = clientFor(serverId);
    if (client == null) throw const ServerConnectionRequiredException();
    return run(client);
  }

  Future<TerminalSessionHandle> openTerminal(
    Server server,
    ServerCredential credential,
    HostKeyApproval approve, {
    String? knownHostKeyFingerprint,
    String? initialDirectory,
    ServerProxy? proxy,
    Map<String, String>? environment,
    List<String>? initialScripts,
  }) async {
    final client = await _createClient(
      server,
      credential,
      approve,
      knownHostKeyFingerprint: knownHostKeyFingerprint,
      proxy: proxy,
    );
    late SSHSession shell;
    try {
      shell = await client.shell(
        pty: const SSHPtyConfig(type: 'xterm-256color', width: 120, height: 36),
        environment: environment,
      );
    } catch (_) {
      client.close();
      rethrow;
    }
    final terminal = _terminalAdapterFactory().create();
    final terminalId = 'terminal-${_nextTerminalId++}';
    final binding = TerminalSessionBinding(
      adapter: terminal,
      stdout: shell.stdout,
      stderr: shell.stderr,
      send: shell.write,
      resize: (event) => shell.resizeTerminal(
        event.columns,
        event.rows,
        event.pixelWidth,
        event.pixelHeight,
      ),
    );
    _terminals[terminalId] = _TerminalConnection(
      serverId: server.id,
      jumpHostServerId: server.jumpHostServerId,
      client: client,
      shell: shell,
      binding: binding,
    );
    // A remote shell ending is normal (`exit`, a logout, or a network drop).
    // Do not use `whenComplete` here: its returned future re-emits an SSH
    // channel error and, because this is fire-and-forget cleanup, would become
    // an unhandled application error.
    shell.done.then<void>(
      (_) => _closeTerminalAfterShellEnds(terminalId, shell),
      onError: (_, _) => _closeTerminalAfterShellEnds(terminalId, shell),
    );
    if (_brandingEnvironmentEnabled()) {
      // Neofetch prioritizes SSH_CONNECTION/SSH_TTY over TERM_PROGRAM. Keep
      // this scoped to the interactive shell so it can identify MaidKit
      // instead of displaying the server's allocated /dev/pts/* path.
      shell.write(
        utf8.encode(
          'export TERM_PROGRAM=MaidKit; unset SSH_CONNECTION SSH_TTY\n',
        ),
      );
    }
    final directory = initialDirectory?.trim();
    if (directory != null && directory.isNotEmpty) {
      // Move into the requested remote folder after the shell starts. Quote the
      // path so spaces and special characters remain literal.
      shell.write(utf8.encode('cd ${_shellSingleQuote(directory)}\n'));
    }
    // Configured initial snippets run once the shell is ready, after any
    // requested directory change. They are written as typed commands so the
    // user sees and can interrupt them.
    for (final script in initialScripts ?? const <String>[]) {
      if (script.trim().isEmpty) continue;
      shell.write(utf8.encode('$script\n'));
    }
    return TerminalSessionHandle(
      id: terminalId,
      adapter: terminal,
      done: shell.done,
    );
  }

  /// POSIX-safe single-quoted string for remote shell commands.
  String _shellSingleQuote(String value) =>
      "'${value.replaceAll("'", "'\\''")}'";

  Future<void> closeTerminal(String terminalId) async {
    final terminal = _terminals.remove(terminalId);
    if (terminal == null) return;
    // The remote shell may already have closed its channel by the time this
    // runs. Treat those close races as successful cleanup rather than letting
    // an `exit` command escape as an unhandled error.
    try {
      await terminal.shell.stdin.close();
    } catch (_) {}
    try {
      await terminal.binding.close();
    } catch (_) {}
    terminal.client.close();
  }

  /// Measures an SSH command round trip for an open terminal connection.
  ///
  /// Using the existing authenticated transport makes this work when ICMP is
  /// unavailable and avoids opening an additional socket just for the status
  /// bar.
  Future<Duration?> measureTerminalLatency(String terminalId) async {
    final terminal = _terminals[terminalId];
    if (terminal == null || terminal.client.isClosed) return null;

    final latency = await _probeLatency(terminal.client);
    return latency != null && identical(_terminals[terminalId], terminal)
        ? latency
        : null;
  }

  void _closeTerminalAfterShellEnds(String terminalId, SSHSession shell) {
    if (!identical(_terminals[terminalId]?.shell, shell)) return;
    unawaited(closeTerminal(terminalId).catchError((_) {}));
  }

  Future<void> refreshServerInfo(Server server) async {
    final client = clientFor(server.id);
    final state = _states[server.id];
    if (client == null || client.isClosed || state == null) return;
    await _refreshNetworkLatency(server, state);
    if (server.collectStats) {
      await _refreshStats(client, _states[server.id] ?? state);
    }
    if (server.collectSystemInfo) {
      await _refreshSystemInfo(client, _states[server.id] ?? state);
    }
  }

  /// Refreshes only the dynamic, low-cost metrics used by server lists and
  /// background connections. Detail pages call [refreshServerInfo] instead.
  Future<void> refreshBasicServerInfo(Server server) async {
    final client = clientFor(server.id);
    final state = _states[server.id];
    if (client == null || client.isClosed || state == null) return;
    await _refreshNetworkLatency(server, state);
    if (server.collectStats) {
      await _refreshStats(client, _states[server.id] ?? state);
    }
  }

  Future<void> _refreshNetworkLatency(
    Server server,
    SshSessionInfo state,
  ) async {
    if (!_supportsDirectNetworkPing(server)) return;
    final client = _sessions[server.id];
    if (client == null || client.isClosed) return;
    final latency = await _probeNetworkLatency(server.host);
    if (latency == null || !identical(_sessions[server.id], client)) return;
    _set((_states[server.id] ?? state).copyWith(networkLatency: latency));
  }

  bool _supportsDirectNetworkPing(Server server) =>
      server.jumpHostServerId == null &&
      (server.proxyType == null ||
          server.proxyType == ServerProxyType.none.name);

  Future<Duration?> _probeNetworkLatency(String host) async {
    try {
      final event = await Ping(
        host,
        count: 1,
        timeout: 2,
      ).stream.first.timeout(const Duration(seconds: 4));
      return event is PingResponse ? event.time : null;
    } catch (_) {
      return null;
    }
  }

  /// Measures one SSH command round trip on [client], or returns `null` if
  /// the probe fails.
  Future<Duration?> _probeLatency(SSHClient client) async {
    final stopwatch = Stopwatch()..start();
    try {
      final session = await client.execute(':');
      await session.done;
      return stopwatch.elapsed;
    } catch (_) {
      return null;
    }
  }

  static const processListLimit = 250;

  Future<List<ServerProcess>> listProcesses(int serverId) async {
    return withClient(serverId, (client) async {
      // Sort once on the host so head keeps top CPU/RSS-relevant rows without
      // shipping the entire process table. Avoid polling this every few seconds
      // when the Processes tab is not visible.
      final windowsResult = await _execute(
        client,
        _windowsProcessCommand(processListLimit),
      );
      if (windowsResult.exitCode == 0 &&
          windowsResult.stdout.contains('--WINDOWS--')) {
        return windowsResult.stdout
            .split('\n')
            .where((line) => !line.startsWith('--WINDOWS--'))
            .map(_parseProcess)
            .whereType<ServerProcess>()
            .toList();
      }
      final session = await client.execute('''sh -c '
if ps -eo pid=,user=,%cpu=,%mem=,rss=,comm= --sort=-%cpu >/dev/null 2>&1; then
  ps -eo pid=,user=,%cpu=,%mem=,rss=,comm= --sort=-%cpu | head -n $processListLimit
else
  ps -Ao pid=,user=,%cpu=,%mem=,rss=,comm= -r | head -n $processListLimit
fi
' ''');
      final output = await utf8.decoder.bind(session.stdout).join();
      await session.done;
      return output
          .split('\n')
          .map(_parseProcess)
          .whereType<ServerProcess>()
          .toList();
    });
  }

  /// Collects a per-runtime snapshot (java/dotnet/python) over direct SSH,
  /// mirroring the daemon's `runtimes` payload. Returns null when the SSH
  /// ps commands fail entirely (caller falls back to the daemon channel).
  Future<RuntimeSnapshot?> refreshRuntimeMetrics(int serverId) {
    return withClient(
      serverId,
      (client) => collectRuntimeMetricsOverSsh(client),
    );
  }

  /// Sends SIGKILL to [pid] on the remote host.
  ///
  /// Tries as the SSH user first; if that fails and elevation is available
  /// (root session or sudo), retries with privileges so other users' processes
  /// can be killed from a normal admin login.
  Future<void> killProcess(
    int serverId, {
    required int pid,
    bool sshUserIsRoot = false,
    String? sudoPassword,
  }) async {
    if (pid <= 1) {
      throw StateError('Refusing to send SIGKILL to pid $pid.');
    }
    await withClient(serverId, (client) async {
      final command = 'kill -s KILL -- $pid';
      var result = await _execute(client, command);
      if (result.exitCode == 0) return;

      if (!sshUserIsRoot) {
        final elevated = await _execute(
          client,
          '${_rootPrefix(false, sudoPassword)}$command',
          stdin: _rootStdin(false, sudoPassword),
        );
        if (elevated.exitCode == 0) return;
        result = elevated;
      }

      throw Exception(_commandError(result));
    });
  }

  /// Detects package tools available on the remote host and reads its pending
  /// update list with the preferred tool. No package indexes are changed.
  Future<PackageManagerStatus> getPackageManagerStatus(
    int serverId, {
    PackageManager? preferredManager,
  }) async {
    return withClient(serverId, (client) async {
      const managers = PackageManager.values;
      final detected = <PackageManager>[];
      for (final manager in managers) {
        final executable = _packageExecutable(manager);
        final result = await _execute(client, 'command -v $executable');
        if (result.exitCode == 0) detected.add(manager);
      }
      if (detected.isEmpty) {
        return const PackageManagerStatus(
          available: [],
          manager: null,
          installedPackageCount: null,
          outdatedPackages: [],
        );
      }
      final manager = detected.contains(preferredManager)
          ? preferredManager!
          : detected.first;
      final installed = await _execute(
        client,
        _installedPackageCountCommand(manager),
      );
      final updates = await _execute(client, _packageOutdatedCommand(manager));
      // Each package manager uses a non-zero exit status to describe an empty
      // update list in at least some releases, so parse stdout regardless.
      return PackageManagerStatus(
        available: detected,
        manager: manager,
        installedPackageCount: int.tryParse(installed.stdout.trim()),
        outdatedPackages: _parsePackageNames(updates.stdout),
      );
    });
  }

  Future<List<PackageSearchResult>> searchPackages(
    int serverId, {
    required PackageManager manager,
    required String query,
  }) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    if (!_safePackageName(term)) {
      throw ArgumentError.value(
        query,
        'query',
        'Use a package name or prefix.',
      );
    }
    return withClient(serverId, (client) async {
      final result = await _execute(
        client,
        _packageSearchCommand(manager, term),
      );
      if (result.exitCode != 0 && result.stdout.trim().isEmpty) {
        throw StateError(_commandError(result));
      }
      final packages = _parsePackageSearch(result.stdout);
      if (packages.isEmpty) return packages;
      final installed = await _execute(
        client,
        _packageInstallationStatusCommand(manager, packages.map((p) => p.name)),
      );
      final installedNames = _parseInstalledPackageNames(installed.stdout);
      return [
        for (final package in packages)
          PackageSearchResult(
            name: package.name,
            version: package.version,
            description: package.description,
            installed: installedNames.contains(package.name),
          ),
      ];
    });
  }

  Future<void> runPackageAction(
    int serverId, {
    required PackageManager manager,
    required PackageAction action,
    String? packageName,
    required bool sshUserIsRoot,
    String? sudoPassword,
    void Function(String chunk)? onOutput,
  }) async {
    final name = packageName?.trim();
    if ((action == PackageAction.install || action == PackageAction.remove) &&
        (name == null || !_safePackageName(name))) {
      throw ArgumentError.value(
        packageName,
        'packageName',
        'Invalid package name.',
      );
    }
    final display = _packageActionCommand(manager, action, name);
    await withClient(serverId, (client) async {
      onOutput?.call('\$ $display\n');
      final requiresElevation = manager.requiresElevation && !sshUserIsRoot;
      final prefix = !requiresElevation
          ? ''
          : (sudoPassword == null ? 'sudo -n ' : 'sudo -S -p "" ');
      final result = await _executeStreaming(
        client,
        '$prefix$display',
        stdin: requiresElevation ? sudoPassword : null,
        onOutput: onOutput,
      );
      if (result.exitCode != 0) {
        throw StateError(_commandError(result));
      }
    });
  }

  /// Runs a user-authored POSIX shell script through an existing SSH session.
  /// Output is streamed so callers can show the operation in the shared task
  /// terminal. The script is supplied on stdin, avoiding interpolation into a
  /// remote command string.
  Future<void> runScriptSnippet(
    int serverId, {
    required String script,
    void Function(String chunk)? onOutput,
    void Function(void Function())? onCancelReady,
  }) => _runScriptSnippet(
    serverId,
    command: 'sh -s',
    stdin: script,
    displayCommand: r'$ sh -s',
    onOutput: onOutput,
    onCancelReady: onCancelReady,
  );

  /// Runs a root-owned POSIX shell script through an existing SSH session.
  ///
  /// When the SSH user is not root, [sudoPassword] is sent only through the
  /// SSH channel to sudo's stdin; it is never interpolated into the command.
  Future<void> runPrivilegedScriptSnippet(
    int serverId, {
    required String script,
    required bool sshUserIsRoot,
    String? sudoPassword,
    void Function(String chunk)? onOutput,
    void Function(void Function())? onCancelReady,
  }) {
    final prefix = _rootPrefix(sshUserIsRoot, sudoPassword);
    final stdin = sshUserIsRoot || sudoPassword == null
        ? script
        : '$sudoPassword\n$script';
    return _runScriptSnippet(
      serverId,
      command: '${prefix}sh -s',
      stdin: stdin,
      displayCommand: r'$ sudo sh -s',
      onOutput: onOutput,
      onCancelReady: onCancelReady,
    );
  }

  Future<void> _runScriptSnippet(
    int serverId, {
    required String command,
    required String stdin,
    required String displayCommand,
    void Function(String chunk)? onOutput,
    void Function(void Function())? onCancelReady,
  }) async {
    if (stdin.trim().isEmpty) {
      throw ArgumentError.value(stdin, 'script', 'The script cannot be empty.');
    }
    await withClient(serverId, (client) async {
      onOutput?.call('$displayCommand\n');
      final result = await _executeStreaming(
        client,
        command,
        stdin: stdin,
        onOutput: onOutput,
        onSession: (session) => onCancelReady?.call(() {
          session.kill(SSHSignal.TERM);
          session.close();
        }),
        // A PTY is useful for interactive CLI progress, but it can keep a
        // shell open after its script input reaches EOF. Snippets need the
        // remote exit status to complete their task deterministically.
        usePty: false,
      );
      if (result.exitCode != 0) throw StateError(_commandError(result));
    });
  }

  /// Collects raw host counters for the Activity tab in a single SSH
  /// round-trip.
  Future<ActivityCounters> collectActivityCounters(int serverId) async {
    return withClient(serverId, (client) async {
      final result = await _execute(client, r'''
sh -c '
if [ -r /proc/stat ]; then
  echo --STAT--
  head -n 1 /proc/stat 2>/dev/null || true
  echo --LOAD--
  cat /proc/loadavg 2>/dev/null || true
  echo --CPU--
  getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1
  echo --MEM--
  cat /proc/meminfo 2>/dev/null || true
  echo --DISK--
  df -Pk / 2>/dev/null | tail -n 1 || true
  echo --NET--
  cat /proc/net/dev 2>/dev/null || true
  echo --UPTIME--
  cut -d. -f1 /proc/uptime 2>/dev/null || true
else
  echo --STAT--
  sysctl -n kern.cp_time 2>/dev/null || true
  echo --LOAD--
  sysctl -n vm.loadavg 2>/dev/null || true
  echo --CPU--
  sysctl -n hw.ncpu 2>/dev/null || true
  echo --MEM--
  sysctl -n hw.memsize 2>/dev/null || true
  echo --VMSTAT--
  vm_stat 2>/dev/null || true
  echo --SWAP--
  sysctl -n vm.swapusage 2>/dev/null || true
  echo --DISK--
  df -Pk / 2>/dev/null || true
  echo --NET--
  netstat -ib 2>/dev/null || true
  echo --UPTIME--
  sysctl -n kern.boottime 2>/dev/null || true
fi
'
''');
      final counters = _parseActivityCounters(result.stdout);
      if (result.exitCode == 0 && _hasActivityData(counters)) {
        return counters;
      }
      final windowsResult = await _execute(client, _windowsActivityCommand());
      if (windowsResult.exitCode == 0 &&
          windowsResult.stdout.contains('--WINDOWS--')) {
        return _parseActivityCounters(windowsResult.stdout);
      }
      if (result.exitCode != 0 && result.stdout.trim().isEmpty) {
        throw StateError(_commandError(result));
      }
      return counters;
    });
  }

  bool _hasActivityData(ActivityCounters counters) =>
      counters.load1 != null ||
      counters.cpuCount != null ||
      counters.memoryTotalKb != null ||
      counters.diskTotalKb != null ||
      counters.netRxBytes != null ||
      counters.uptime != null;

  ActivityCounters _parseActivityCounters(String output) {
    String section(String name) {
      final start = output.indexOf('--$name--');
      if (start < 0) return '';
      final after = start + name.length + 4;
      final next = output.indexOf('--', after);
      return (next < 0
              ? output.substring(after)
              : output.substring(after, next))
          .trim();
    }

    final statLine = section('STAT');
    final rawStatFields = statLine.split(RegExp(r'\s+'));
    final statFields = statLine.startsWith('cpu')
        ? rawStatFields.skip(1).map(int.tryParse).whereType<int>().toList()
        : rawStatFields.map(int.tryParse).whereType<int>().toList();
    int? cpuIdle;
    int? cpuTotal;
    if (statFields.length >= 4) {
      // Linux: user nice system idle iowait irq softirq steal …
      // macOS: user nice system interrupt idle.
      final idleIndex = statLine.startsWith('cpu') ? 3 : statFields.length - 1;
      final idle =
          statFields[idleIndex] +
          (statLine.startsWith('cpu') && statFields.length > 4
              ? statFields[4]
              : 0);
      cpuIdle = idle;
      cpuTotal = statFields.fold<int>(0, (sum, value) => sum + value);
    }

    final loads = RegExp(r'[0-9]+(?:\.[0-9]+)?')
        .allMatches(section('LOAD'))
        .map((match) => double.tryParse(match.group(0)!))
        .whereType<double>()
        .toList();
    final directCpuPercent = double.tryParse(section('CPUUSAGE'));
    final memSection = section('MEM');
    int? memValue(String label) {
      final match = RegExp('$label:\\s+(\\d+)').firstMatch(memSection);
      return match == null ? null : int.tryParse(match.group(1)!);
    }

    final macTotalBytes = int.tryParse(memSection);
    int? macAvailableBytes() {
      final vmStat = section('VMSTAT');
      final pageSize = int.tryParse(
        RegExp(r'page size of (\d+) bytes').firstMatch(vmStat)?.group(1) ?? '',
      );
      if (pageSize == null) return null;
      int? pages(String label) => int.tryParse(
        RegExp('$label:\\s+(\\d+)').firstMatch(vmStat)?.group(1) ?? '',
      );
      final values = [
        pages('Pages free'),
        pages('Pages inactive'),
        pages('Pages speculative'),
      ].whereType<int>().toList();
      if (values.isEmpty) return null;
      return values.fold<int>(0, (sum, value) => sum + value) * pageSize;
    }

    int? macSwapValue(String label) {
      final match = RegExp(
        '$label\\s*=\\s*([0-9]+(?:\\.[0-9]+)?)([KMGT])',
        caseSensitive: false,
      ).firstMatch(section('SWAP'));
      if (match == null) return null;
      final amount = double.tryParse(match.group(1)!);
      if (amount == null) return null;
      final multiplier = switch (match.group(2)!.toUpperCase()) {
        'K' => 1,
        'M' => 1024,
        'G' => 1024 * 1024,
        'T' => 1024 * 1024 * 1024,
        _ => 1,
      };
      return (amount * multiplier).round();
    }

    final diskLines = section('DISK')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final diskFields = diskLines.isEmpty
        ? const <String>[]
        : diskLines.last.split(RegExp(r'\s+'));
    var netRx = 0;
    var netTx = 0;
    var hasNet = false;
    for (final line in section('NET').split('\n')) {
      final trimmed = line.trim();
      if (trimmed.contains(':')) {
        final parts = trimmed.split(':');
        if (parts.length < 2 || parts[0].trim() == 'lo') continue;
        final cols = parts[1].trim().split(RegExp(r'\s+'));
        if (cols.length < 9) continue;
        final rx = int.tryParse(cols[0]);
        final tx = int.tryParse(cols[8]);
        if (rx == null || tx == null) continue;
        netRx += rx;
        netTx += tx;
        hasNet = true;
        continue;
      }
      final fields = trimmed.split(RegExp(r'\s+'));
      if (fields.length < 10 ||
          fields[0] == 'Name' ||
          fields[0] == 'lo0' ||
          !fields[2].startsWith('<Link#')) {
        continue;
      }
      final rx = int.tryParse(fields[6]);
      final tx = int.tryParse(fields[9]);
      if (rx == null || tx == null) continue;
      netRx += rx;
      netTx += tx;
      hasNet = true;
    }
    final windowsRx = int.tryParse(
      RegExp(
            r'^RxBytes:\s*(\d+)',
            multiLine: true,
          ).firstMatch(section('NET'))?.group(1) ??
          '',
    );
    final windowsTx = int.tryParse(
      RegExp(
            r'^TxBytes:\s*(\d+)',
            multiLine: true,
          ).firstMatch(section('NET'))?.group(1) ??
          '',
    );
    if (windowsRx != null && windowsTx != null) {
      netRx = windowsRx;
      netTx = windowsTx;
      hasNet = true;
    }

    final windowsDiskTotal = int.tryParse(
      RegExp(
            r'^DiskTotal:\s*(\d+)',
            multiLine: true,
          ).firstMatch(section('DISK'))?.group(1) ??
          '',
    );
    final windowsDiskAvailable = int.tryParse(
      RegExp(
            r'^DiskAvailable:\s*(\d+)',
            multiLine: true,
          ).firstMatch(section('DISK'))?.group(1) ??
          '',
    );
    final uptimeText = section('UPTIME');
    var uptimeSeconds = int.tryParse(uptimeText);
    if (uptimeSeconds == null) {
      final boot = int.tryParse(
        RegExp(r'sec\s*=\s*(\d+)').firstMatch(uptimeText)?.group(1) ?? '',
      );
      if (boot != null) {
        uptimeSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000 - boot;
      }
    }
    return ActivityCounters(
      at: DateTime.now(),
      cpuIdle: cpuIdle,
      cpuTotal: cpuTotal,
      cpuPercent: directCpuPercent,
      load1: loads.isNotEmpty ? loads[0] : null,
      load5: loads.length > 1 ? loads[1] : null,
      load15: loads.length > 2 ? loads[2] : null,
      cpuCount: int.tryParse(section('CPU')),
      memoryTotalKb:
          memValue('MemTotal') ??
          (macTotalBytes == null ? null : macTotalBytes ~/ 1024),
      memoryAvailableKb:
          memValue('MemAvailable') ??
          (macAvailableBytes() == null ? null : macAvailableBytes()! ~/ 1024),
      swapTotalKb: memValue('SwapTotal') ?? macSwapValue('total'),
      swapFreeKb: memValue('SwapFree') ?? macSwapValue('free'),
      diskTotalKb:
          windowsDiskTotal ??
          (diskFields.length > 1 ? int.tryParse(diskFields[1]) : null),
      diskAvailableKb:
          windowsDiskAvailable ??
          (diskFields.length > 3 ? int.tryParse(diskFields[3]) : null),
      netRxBytes: hasNet ? netRx : null,
      netTxBytes: hasNet ? netTx : null,
      uptime: uptimeSeconds == null || uptimeSeconds < 0
          ? null
          : Duration(seconds: uptimeSeconds),
    );
  }

  /// Reads the current user's crontab (`crontab -l`).
  Future<CrontabDocument> listCrontab(int serverId) async {
    return withClient(serverId, (client) async {
      final result = await _execute(client, 'crontab -l');
      final combined = '${result.stderr}\n${result.stdout}'.toLowerCase();
      if (result.exitCode != 0) {
        if (combined.contains('no crontab')) {
          return const CrontabDocument(entries: [], exists: false);
        }
        throw StateError(_commandError(result));
      }
      return parseCrontab(result.stdout);
    });
  }

  /// Replaces the current user's crontab with [document].
  Future<void> installCrontab(int serverId, CrontabDocument document) async {
    await withClient(serverId, (client) async {
      final text = document.toCrontabText();
      // Empty crontab: remove it rather than installing a blank file.
      if (text.trim().isEmpty) {
        final result = await _execute(client, 'crontab -r');
        // "no crontab" is fine when removing.
        if (result.exitCode != 0) {
          final message = _commandError(result).toLowerCase();
          if (!message.contains('no crontab')) {
            throw StateError(_commandError(result));
          }
        }
        return;
      }
      final encoded = base64.encode(
        utf8.encode(text.endsWith('\n') ? text : '$text\n'),
      );
      final result = await _execute(
        client,
        "echo $encoded | base64 -d | crontab -",
      );
      if (result.exitCode != 0) throw StateError(_commandError(result));
    });
  }

  /// Lists system-level systemd service units (active state + enablement).
  ///
  /// Listing is unprivileged; [sshUserIsRoot] / [sudoPassword] are accepted for
  /// API symmetry with mutating calls but are not required for the probe.
  Future<SystemdUnitsSnapshot> listSystemdUnits(
    int serverId, {
    bool sshUserIsRoot = false,
    String? sudoPassword,
  }) async {
    return withClient(serverId, (client) async {
      // Unprivileged systemctl list-* works for normal SSH users. Avoid sudo
      // here so key-only sessions without passwordless sudo can still browse.
      const script =
          r'''sh -c 'if ! command -v systemctl >/dev/null 2>&1; then echo --NOSYSTEMD--; exit 0; fi; echo --UNITS--; systemctl list-units --type=service --all --no-pager --plain --no-legend 2>/dev/null || true; echo --FILES--; systemctl list-unit-files --type=service --no-pager --plain --no-legend 2>/dev/null || true' ''';
      final result = await _execute(client, script);
      if (result.exitCode != 0 &&
          !result.stdout.contains('--NOSYSTEMD--') &&
          result.stdout.trim().isEmpty) {
        throw StateError(_commandError(result));
      }
      return parseSystemdProbeOutput(result.stdout);
    });
  }

  /// Runs start/stop/restart/enable/disable for a system unit.
  Future<void> runSystemdUnitAction(
    int serverId, {
    required String unit,
    required SystemdUnitAction action,
    bool sshUserIsRoot = false,
    String? sudoPassword,
  }) async {
    final name = normalizeSystemdUnitName(unit);
    if (!isValidSystemdUnitName(name)) {
      throw ArgumentError.value(unit, 'unit', 'Invalid systemd unit name.');
    }
    await withClient(serverId, (client) async {
      final prefix = _rootPrefix(sshUserIsRoot, sudoPassword);
      final stdin = _rootStdin(sshUserIsRoot, sudoPassword);
      final quoted = _shellSingleQuote(name);
      final result = await _execute(
        client,
        '${prefix}systemctl ${action.systemctlVerb} $quoted',
        stdin: stdin,
      );
      if (result.exitCode != 0) throw StateError(_commandError(result));
    });
  }

  /// Returns `systemctl status` text for [unit].
  Future<String> getSystemdUnitStatus(
    int serverId, {
    required String unit,
    bool sshUserIsRoot = false,
    String? sudoPassword,
  }) async {
    final name = normalizeSystemdUnitName(unit);
    if (!isValidSystemdUnitName(name)) {
      throw ArgumentError.value(unit, 'unit', 'Invalid systemd unit name.');
    }
    return withClient(serverId, (client) async {
      final prefix = _rootPrefix(sshUserIsRoot, sudoPassword);
      final stdin = _rootStdin(sshUserIsRoot, sudoPassword);
      final quoted = _shellSingleQuote(name);
      // status exits non-zero for inactive/failed units; still return stdout.
      final result = await _execute(
        client,
        '${prefix}systemctl status $quoted --no-pager -l -n 30',
        stdin: stdin,
      );
      final text = result.stdout.trim().isNotEmpty
          ? result.stdout
          : result.stderr;
      if (text.trim().isEmpty) {
        throw StateError(_commandError(result));
      }
      return text;
    });
  }

  /// Returns recent journal lines for [unit] via `journalctl -u`.
  Future<String> getSystemdUnitLogs(
    int serverId, {
    required String unit,
    int lines = 200,
    bool sshUserIsRoot = false,
    String? sudoPassword,
  }) async {
    final name = normalizeSystemdUnitName(unit);
    if (!isValidSystemdUnitName(name)) {
      throw ArgumentError.value(unit, 'unit', 'Invalid systemd unit name.');
    }
    final n = lines.clamp(1, 2000);
    return withClient(serverId, (client) async {
      final prefix = _rootPrefix(sshUserIsRoot, sudoPassword);
      final stdin = _rootStdin(sshUserIsRoot, sudoPassword);
      final quoted = _shellSingleQuote(name);
      final result = await _execute(
        client,
        '${prefix}journalctl -u $quoted -n $n --no-pager -o short-iso',
        stdin: stdin,
      );
      if (result.exitCode != 0 && result.stdout.trim().isEmpty) {
        throw StateError(_commandError(result));
      }
      final text = result.stdout.trim().isNotEmpty
          ? result.stdout
          : result.stderr;
      return text.trim().isEmpty ? 'No journal entries for $name.' : text;
    });
  }

  /// Detects and reads the host firewall status (UFW, firewalld, nft, iptables).
  Future<FirewallStatus> getFirewallStatus(
    int serverId, {
    bool sshUserIsRoot = false,
    String? sudoPassword,
  }) async {
    return withClient(serverId, (client) async {
      final prefix = _rootPrefix(sshUserIsRoot, sudoPassword);
      final stdin = _rootStdin(sshUserIsRoot, sudoPassword);

      Future<_CommandResult> run(String command) =>
          _execute(client, '$prefix$command', stdin: stdin);

      // Prefer the friendliest management CLIs first.
      final ufwPath = await _execute(client, 'command -v ufw');
      if (ufwPath.exitCode == 0 && ufwPath.stdout.trim().isNotEmpty) {
        final numbered = await run('ufw status numbered');
        final verbose = await run('ufw status verbose');
        return _parseUfwStatus(numbered, verbose: verbose);
      }

      final firewallCmd = await _execute(client, 'command -v firewall-cmd');
      if (firewallCmd.exitCode == 0 && firewallCmd.stdout.trim().isNotEmpty) {
        return _parseFirewalldStatus(
          await run('firewall-cmd --state'),
          await run('firewall-cmd --list-all'),
        );
      }

      final nft = await _execute(client, 'command -v nft');
      if (nft.exitCode == 0 && nft.stdout.trim().isNotEmpty) {
        final ruleset = await run('nft list ruleset');
        return _parseNftStatus(ruleset);
      }

      final iptables = await _execute(client, 'command -v iptables');
      if (iptables.exitCode == 0 && iptables.stdout.trim().isNotEmpty) {
        final rules = await run('iptables -L -n -v --line-numbers');
        return _parseIptablesStatus(rules);
      }

      return const FirewallStatus(
        backend: FirewallBackend.none,
        active: false,
        error:
            'No supported firewall tool was found (ufw, firewalld, nft, iptables).',
      );
    });
  }

  Future<void> setFirewallEnabled(
    int serverId, {
    required bool enabled,
    bool sshUserIsRoot = false,
    String? sudoPassword,
  }) async {
    await withClient(serverId, (client) async {
      final status = await getFirewallStatus(
        serverId,
        sshUserIsRoot: sshUserIsRoot,
        sudoPassword: sudoPassword,
      );
      final prefix = _rootPrefix(sshUserIsRoot, sudoPassword);
      final stdin = _rootStdin(sshUserIsRoot, sudoPassword);
      final command = switch (status.backend) {
        FirewallBackend.ufw => enabled ? 'ufw --force enable' : 'ufw disable',
        FirewallBackend.firewalld =>
          enabled ? 'systemctl start firewalld' : 'systemctl stop firewalld',
        FirewallBackend.nftables ||
        FirewallBackend.iptables ||
        FirewallBackend.none => throw StateError(
          'Enabling/disabling is only supported for UFW and firewalld.',
        ),
      };
      final result = await _execute(client, '$prefix$command', stdin: stdin);
      if (result.exitCode != 0) throw StateError(_commandError(result));
    });
  }

  Future<void> addFirewallRule(
    int serverId, {
    required FirewallRuleDraft draft,
    bool sshUserIsRoot = false,
    String? sudoPassword,
  }) async {
    final port = draft.port.trim();
    if (!RegExp(r'^[0-9]{1,5}(:[0-9]{1,5})?$').hasMatch(port) &&
        !RegExp(r'^[a-zA-Z0-9/_-]+$').hasMatch(port)) {
      throw ArgumentError.value(port, 'port', 'Invalid port or service name.');
    }
    final protocol = draft.protocol.trim().toLowerCase();
    if (protocol.isNotEmpty &&
        !const {'tcp', 'udp', 'any', ''}.contains(protocol)) {
      throw ArgumentError.value(protocol, 'protocol', 'Use tcp, udp, or any.');
    }
    await withClient(serverId, (client) async {
      final status = await getFirewallStatus(
        serverId,
        sshUserIsRoot: sshUserIsRoot,
        sudoPassword: sudoPassword,
      );
      final prefix = _rootPrefix(sshUserIsRoot, sudoPassword);
      final stdin = _rootStdin(sshUserIsRoot, sudoPassword);
      final result = switch (status.backend) {
        FirewallBackend.ufw => await _execute(
          client,
          '$prefix${_ufwAddCommand(draft)}',
          stdin: stdin,
        ),
        FirewallBackend.firewalld => await _execute(
          client,
          '$prefix${_firewalldAddCommand(draft)}',
          stdin: stdin,
        ),
        _ => throw StateError(
          'Adding rules is only supported for UFW and firewalld.',
        ),
      };
      if (result.exitCode != 0) throw StateError(_commandError(result));
    });
  }

  Future<void> deleteFirewallRule(
    int serverId, {
    required FirewallRule rule,
    bool sshUserIsRoot = false,
    String? sudoPassword,
  }) async {
    await withClient(serverId, (client) async {
      final status = await getFirewallStatus(
        serverId,
        sshUserIsRoot: sshUserIsRoot,
        sudoPassword: sudoPassword,
      );
      final prefix = _rootPrefix(sshUserIsRoot, sudoPassword);
      final stdin = _rootStdin(sshUserIsRoot, sudoPassword);
      final result = switch (status.backend) {
        FirewallBackend.ufw => await _execute(
          client,
          // Prefer numbered delete when the id is a UFW rule number.
          RegExp(r'^\d+$').hasMatch(rule.id)
              ? '${prefix}ufw --force delete ${rule.id}'
              : '${prefix}ufw delete ${_shellSingleQuote(rule.display)}',
          stdin: stdin,
        ),
        FirewallBackend.firewalld => await _execute(
          client,
          rule.id.startsWith('service:')
              ? '${prefix}sh -c "firewall-cmd --permanent --remove-service=${rule.id.substring('service:'.length)} && firewall-cmd --reload"'
              : '${prefix}sh -c "firewall-cmd --permanent --remove-port=${rule.id} && firewall-cmd --reload"',
          stdin: stdin,
        ),
        _ => throw StateError(
          'Deleting rules is only supported for UFW and firewalld.',
        ),
      };
      if (result.exitCode != 0) throw StateError(_commandError(result));
    });
  }

  /// Detects installed web servers (nginx, caddy, …) via registered adapters.
  Future<List<WebServerDetection>> detectWebServers(
    int serverId, {
    bool sshUserIsRoot = false,
    String? sudoPassword,
  }) async {
    return withClient(serverId, (client) async {
      final remote = _webServerRemote(
        client,
        sshUserIsRoot: sshUserIsRoot,
        sudoPassword: sudoPassword,
      );
      final detections = <WebServerDetection>[];
      for (final adapter in builtInWebServerAdapters) {
        try {
          final installed = await adapter.isInstalled(remote);
          if (!installed) {
            detections.add(
              WebServerDetection(
                adapterId: adapter.id,
                label: adapter.label,
                installed: false,
              ),
            );
            continue;
          }
          // Unprivileged probe for the picker; full site load is separate.
          final version = await remote.run(
            adapter.id == 'nginx' ? 'nginx -v 2>&1' : 'caddy version 2>&1',
          );
          final active = await remote.run(
            'systemctl is-active ${remote.quote(adapter.serviceUnit)} 2>/dev/null || true',
          );
          detections.add(
            WebServerDetection(
              adapterId: adapter.id,
              label: adapter.label,
              installed: true,
              version: version.combined.trim().isEmpty
                  ? null
                  : version.combined.trim().split('\n').first,
              running: active.output.trim().toLowerCase() == 'active',
            ),
          );
        } catch (_) {
          detections.add(
            WebServerDetection(
              adapterId: adapter.id,
              label: adapter.label,
              installed: false,
            ),
          );
        }
      }
      return detections;
    });
  }

  /// Full status + site listing for one web server adapter.
  Future<WebServerStatus> getWebServerStatus(
    int serverId, {
    required String adapterId,
    bool sshUserIsRoot = false,
    String? sudoPassword,
  }) async {
    final adapter = webServerAdapterById(adapterId);
    if (adapter == null) {
      throw ArgumentError.value(adapterId, 'adapterId', 'Unknown web server.');
    }
    return withClient(serverId, (client) async {
      final remote = _webServerRemote(
        client,
        sshUserIsRoot: sshUserIsRoot,
        sudoPassword: sudoPassword,
      );
      return adapter.loadStatus(remote);
    });
  }

  /// Runs a lifecycle action and returns a structured success/failure result.
  Future<WebServerTaskResult> runWebServerAction(
    int serverId, {
    required String adapterId,
    required WebServerAction action,
    bool sshUserIsRoot = false,
    String? sudoPassword,
    void Function(String chunk)? onOutput,
  }) async {
    final adapter = _requireWebServerAdapter(adapterId);
    return withClient(serverId, (client) async {
      final remote = _webServerRemote(
        client,
        sshUserIsRoot: sshUserIsRoot,
        sudoPassword: sudoPassword,
        onOutput: onOutput,
      );
      final title = '${action.englishLabel} ${adapter.label}';
      final steps = <WebServerTaskStep>[];
      try {
        // Pre-validate before reload so a bad config never replaces a live one
        // without a clear check step in the task log.
        if (action == WebServerAction.reload) {
          try {
            final output = await adapter.validateConfig(remote);
            final summary = summarizeCommandOutput(output);
            steps.add(
              WebServerTaskStep(
                id: 'validate',
                label: 'Config check',
                success: true,
                detail: summary.isEmpty
                    ? 'Configuration syntax is valid.'
                    : summary,
              ),
            );
            onOutput?.call('\n✓ Config check passed.\n');
          } catch (error) {
            final detail = summarizeCommandOutput('$error');
            steps.add(
              WebServerTaskStep(
                id: 'validate',
                label: 'Config check',
                success: false,
                detail: detail.isEmpty ? error.toString() : detail,
              ),
            );
            onOutput?.call('\n✗ Config check failed — reload aborted.\n');
            return WebServerTaskResult(
              success: false,
              title: title,
              summary: detail.isEmpty
                  ? 'Config check failed; ${adapter.label} was not reloaded.'
                  : 'Config check failed: $detail',
              steps: steps,
              detail: error.toString(),
            );
          }
        }

        await adapter.runAction(remote, action);
        steps.add(
          WebServerTaskStep(
            id: action.name,
            label: action.englishLabel,
            success: true,
            detail: '${adapter.label} ${action.systemctlVerb} completed.',
          ),
        );

        // Post-check running state for start/stop/restart/reload.
        if (action == WebServerAction.start ||
            action == WebServerAction.stop ||
            action == WebServerAction.restart ||
            action == WebServerAction.reload) {
          final active = await remote.run(
            'systemctl is-active ${remote.quote(adapter.serviceUnit)} 2>/dev/null || true',
          );
          final running = active.output.trim().toLowerCase() == 'active';
          final expectRunning = action != WebServerAction.stop;
          final ok = running == expectRunning;
          steps.add(
            WebServerTaskStep(
              id: 'verify',
              label: 'Service state',
              success: ok,
              detail: running
                  ? '${adapter.serviceUnit} is active.'
                  : '${adapter.serviceUnit} is ${active.output.trim().isEmpty ? 'inactive' : active.output.trim()}.',
            ),
          );
          if (!ok) {
            onOutput?.call('\n✗ Service state check failed.\n');
            return WebServerTaskResult(
              success: false,
              title: title,
              summary: expectRunning
                  ? '${adapter.label} did not become active after ${action.systemctlVerb}.'
                  : '${adapter.label} is still active after stop.',
              steps: steps,
              detail: active.combined,
            );
          }
          onOutput?.call(
            running ? '\n✓ Service is active.\n' : '\n✓ Service is stopped.\n',
          );
        }

        return WebServerTaskResult(
          success: true,
          title: title,
          summary: switch (action) {
            WebServerAction.start => '${adapter.label} started and is running.',
            WebServerAction.stop => '${adapter.label} stopped.',
            WebServerAction.restart =>
              '${adapter.label} restarted and is running.',
            WebServerAction.reload =>
              '${adapter.label} config reloaded successfully.',
            WebServerAction.enable => '${adapter.label} enabled on boot.',
            WebServerAction.disable => '${adapter.label} disabled on boot.',
          },
          steps: steps,
        );
      } catch (error) {
        final detail = summarizeCommandOutput('$error');
        steps.add(
          WebServerTaskStep(
            id: action.name,
            label: action.englishLabel,
            success: false,
            detail: detail.isEmpty ? error.toString() : detail,
          ),
        );
        return WebServerTaskResult(
          success: false,
          title: title,
          summary: detail.isEmpty
              ? 'Failed to ${action.systemctlVerb} ${adapter.label}.'
              : 'Failed to ${action.systemctlVerb} ${adapter.label}: $detail',
          steps: steps,
          detail: error.toString(),
        );
      }
    });
  }

  /// Validates config and returns a structured result (does not throw on fail).
  Future<WebServerTaskResult> validateWebServerConfig(
    int serverId, {
    required String adapterId,
    bool sshUserIsRoot = false,
    String? sudoPassword,
    void Function(String chunk)? onOutput,
  }) async {
    final adapter = _requireWebServerAdapter(adapterId);
    return withClient(serverId, (client) async {
      final remote = _webServerRemote(
        client,
        sshUserIsRoot: sshUserIsRoot,
        sudoPassword: sudoPassword,
        onOutput: onOutput,
      );
      final title = 'Validate ${adapter.label}';
      try {
        final output = await adapter.validateConfig(remote);
        final summary = summarizeCommandOutput(output);
        onOutput?.call('\n✓ Configuration is valid.\n');
        return WebServerTaskResult(
          success: true,
          title: title,
          summary: summary.isEmpty
              ? '${adapter.label} configuration is valid.'
              : summary,
          steps: [
            WebServerTaskStep(
              id: 'validate',
              label: 'Config check',
              success: true,
              detail: summary.isEmpty
                  ? 'Configuration syntax is valid.'
                  : summary,
            ),
          ],
          detail: output,
        );
      } catch (error) {
        final detail = summarizeCommandOutput('$error');
        onOutput?.call('\n✗ Configuration check failed.\n');
        return WebServerTaskResult(
          success: false,
          title: title,
          summary: detail.isEmpty
              ? '${adapter.label} configuration is invalid.'
              : detail,
          steps: [
            WebServerTaskStep(
              id: 'validate',
              label: 'Config check',
              success: false,
              detail: detail.isEmpty ? error.toString() : detail,
            ),
          ],
          detail: error.toString(),
        );
      }
    });
  }

  Future<String> readWebServerConfig(
    int serverId, {
    required String adapterId,
    String? siteId,
    bool sshUserIsRoot = false,
    String? sudoPassword,
  }) async {
    final adapter = _requireWebServerAdapter(adapterId);
    return withClient(serverId, (client) async {
      final remote = _webServerRemote(
        client,
        sshUserIsRoot: sshUserIsRoot,
        sudoPassword: sudoPassword,
      );
      final text = await adapter.readConfig(remote, siteId: siteId);
      final bytes = utf8.encode(text);
      if (bytes.length > webServerMaxEditableBytes) {
        throw StateError(
          'Config is larger than 1 MB and cannot be opened in the editor.',
        );
      }
      return text;
    });
  }

  /// Writes config, optionally validates and reloads. Structured task result.
  Future<WebServerTaskResult> applyWebServerConfig(
    int serverId, {
    required String adapterId,
    required String content,
    required WebServerApplyMode mode,
    String? siteId,
    bool sshUserIsRoot = false,
    String? sudoPassword,
    void Function(String chunk)? onOutput,
  }) async {
    final adapter = _requireWebServerAdapter(adapterId);
    return withClient(serverId, (client) async {
      final remote = _webServerRemote(
        client,
        sshUserIsRoot: sshUserIsRoot,
        sudoPassword: sudoPassword,
        onOutput: onOutput,
      );
      final title = switch (mode) {
        WebServerApplyMode.saveOnly => 'Save ${adapter.label} config',
        WebServerApplyMode.saveAndValidate => 'Save & check ${adapter.label}',
        WebServerApplyMode.saveValidateReload =>
          'Save, check & reload ${adapter.label}',
      };
      final steps = <WebServerTaskStep>[];

      try {
        await adapter.writeConfig(remote, content: content, siteId: siteId);
        steps.add(
          const WebServerTaskStep(
            id: 'save',
            label: 'Save',
            success: true,
            detail: 'Config written to disk.',
          ),
        );
        onOutput?.call('\n✓ Config saved.\n');
      } catch (error) {
        final detail = summarizeCommandOutput('$error');
        steps.add(
          WebServerTaskStep(
            id: 'save',
            label: 'Save',
            success: false,
            detail: detail.isEmpty ? error.toString() : detail,
          ),
        );
        return WebServerTaskResult(
          success: false,
          title: title,
          summary: detail.isEmpty
              ? 'Failed to write ${adapter.label} config.'
              : 'Failed to write config: $detail',
          steps: steps,
          detail: error.toString(),
        );
      }

      if (mode == WebServerApplyMode.saveOnly) {
        return WebServerTaskResult(
          success: true,
          title: title,
          summary: '${adapter.label} config saved.',
          steps: steps,
        );
      }

      try {
        final output = await adapter.validateConfig(remote);
        final summary = summarizeCommandOutput(output);
        steps.add(
          WebServerTaskStep(
            id: 'validate',
            label: 'Config check',
            success: true,
            detail: summary.isEmpty
                ? 'Configuration syntax is valid.'
                : summary,
          ),
        );
        onOutput?.call('\n✓ Config check passed.\n');
      } catch (error) {
        final detail = summarizeCommandOutput('$error');
        steps.add(
          WebServerTaskStep(
            id: 'validate',
            label: 'Config check',
            success: false,
            detail: detail.isEmpty ? error.toString() : detail,
          ),
        );
        onOutput?.call('\n✗ Config check failed — reload skipped.\n');
        return WebServerTaskResult(
          success: false,
          title: title,
          summary: detail.isEmpty
              ? 'Config saved but check failed. Service was not reloaded.'
              : 'Config saved but check failed: $detail',
          steps: steps,
          detail: error.toString(),
        );
      }

      if (mode == WebServerApplyMode.saveAndValidate) {
        return WebServerTaskResult(
          success: true,
          title: title,
          summary: '${adapter.label} config saved and validated.',
          steps: steps,
        );
      }

      try {
        await adapter.runAction(remote, WebServerAction.reload);
        steps.add(
          WebServerTaskStep(
            id: 'reload',
            label: 'Reload',
            success: true,
            detail: '${adapter.label} reloaded.',
          ),
        );
        final active = await remote.run(
          'systemctl is-active ${remote.quote(adapter.serviceUnit)} 2>/dev/null || true',
        );
        final running = active.output.trim().toLowerCase() == 'active';
        steps.add(
          WebServerTaskStep(
            id: 'verify',
            label: 'Service state',
            success: running,
            detail: running
                ? '${adapter.serviceUnit} is active.'
                : '${adapter.serviceUnit} is not active after reload.',
          ),
        );
        if (!running) {
          onOutput?.call('\n✗ Service is not active after reload.\n');
          return WebServerTaskResult(
            success: false,
            title: title,
            summary:
                'Config saved and valid, but ${adapter.label} is not active after reload.',
            steps: steps,
            detail: active.combined,
          );
        }
        onOutput?.call('\n✓ Config reloaded; service is active.\n');
        return WebServerTaskResult(
          success: true,
          title: title,
          summary: '${adapter.label} config saved, validated, and reloaded.',
          steps: steps,
        );
      } catch (error) {
        final detail = summarizeCommandOutput('$error');
        steps.add(
          WebServerTaskStep(
            id: 'reload',
            label: 'Reload',
            success: false,
            detail: detail.isEmpty ? error.toString() : detail,
          ),
        );
        return WebServerTaskResult(
          success: false,
          title: title,
          summary: detail.isEmpty
              ? 'Config valid but reload failed.'
              : 'Config valid but reload failed: $detail',
          steps: steps,
          detail: error.toString(),
        );
      }
    });
  }

  Future<String> getWebServerLogs(
    int serverId, {
    required String adapterId,
    int lines = 200,
    bool sshUserIsRoot = false,
    String? sudoPassword,
  }) async {
    final adapter = _requireWebServerAdapter(adapterId);
    return withClient(serverId, (client) async {
      final remote = _webServerRemote(
        client,
        sshUserIsRoot: sshUserIsRoot,
        sudoPassword: sudoPassword,
      );
      return adapter.getLogs(remote, lines: lines);
    });
  }

  WebServerAdapter _requireWebServerAdapter(String adapterId) {
    final adapter = webServerAdapterById(adapterId);
    if (adapter == null) {
      throw ArgumentError.value(adapterId, 'adapterId', 'Unknown web server.');
    }
    return adapter;
  }

  WebServerRemote _webServerRemote(
    SSHClient client, {
    required bool sshUserIsRoot,
    String? sudoPassword,
    void Function(String chunk)? onOutput,
  }) {
    return _SshWebServerRemote(
      execute: (command, {privileged = false, stdinPayload}) async {
        onOutput?.call('\$ $command\n');
        final _CommandResult result;
        if (!privileged) {
          result = await _execute(client, command, stdin: stdinPayload);
        } else {
          final prefix = _rootPrefix(sshUserIsRoot, sudoPassword);
          // sudo -S reads the password as the first stdin line; remaining
          // bytes are available to the command (used by tee for file writes).
          final String? stdin;
          if (sshUserIsRoot) {
            stdin = stdinPayload;
          } else if (sudoPassword == null) {
            stdin = stdinPayload;
          } else if (stdinPayload == null) {
            stdin = sudoPassword;
          } else {
            stdin = '$sudoPassword\n$stdinPayload';
          }
          result = await _execute(client, '$prefix$command', stdin: stdin);
        }
        final mapped = WebServerCommandResult(
          stdout: result.stdout,
          stderr: result.stderr,
          exitCode: result.exitCode,
        );
        final combined = mapped.combined.trim();
        if (combined.isNotEmpty) {
          onOutput?.call(combined.endsWith('\n') ? combined : '$combined\n');
        }
        if (result.exitCode != 0) {
          onOutput?.call('[exit ${result.exitCode}]\n');
        }
        return mapped;
      },
      quoteFn: _shellSingleQuote,
    );
  }

  String _rootPrefix(bool sshUserIsRoot, String? sudoPassword) {
    if (sshUserIsRoot) return '';
    return sudoPassword == null ? 'sudo -n ' : 'sudo -S -p "" ';
  }

  String? _rootStdin(bool sshUserIsRoot, String? sudoPassword) {
    if (sshUserIsRoot) return null;
    return sudoPassword;
  }

  String _ufwAddCommand(FirewallRuleDraft draft) {
    final action = switch (draft.action) {
      FirewallAction.allow => 'allow',
      FirewallAction.deny => 'deny',
      FirewallAction.reject => 'reject',
      FirewallAction.drop => 'deny',
    };
    final port = draft.port.trim();
    final protocol = draft.protocol.trim().toLowerCase();
    final target = protocol.isEmpty || protocol == 'any'
        ? port
        : '$port/$protocol';
    final from = draft.source?.trim();
    if (from != null && from.isNotEmpty) {
      return 'ufw $action from ${_shellSingleQuote(from)} to any port '
          '${protocol.isEmpty || protocol == 'any' ? port : '$port proto $protocol'}';
    }
    return 'ufw $action $target';
  }

  String _firewalldAddCommand(FirewallRuleDraft draft) {
    final port = draft.port.trim();
    final protocol = draft.protocol.trim().toLowerCase();
    final proto = protocol.isEmpty || protocol == 'any' ? 'tcp' : protocol;
    final portSpec = port.contains('/') ? port : '$port/$proto';
    // Single sudo session so both permanent write and reload succeed.
    return 'sh -c "firewall-cmd --permanent --add-port=$portSpec && firewall-cmd --reload"';
  }

  FirewallStatus _parseUfwStatus(
    _CommandResult result, {
    _CommandResult? verbose,
  }) {
    final text = result.stdout.isNotEmpty ? result.stdout : result.stderr;
    final verboseText = verbose == null
        ? text
        : (verbose.stdout.isNotEmpty ? verbose.stdout : verbose.stderr);
    if (result.exitCode != 0 && text.trim().isEmpty) {
      return FirewallStatus(
        backend: FirewallBackend.ufw,
        active: false,
        error: _commandError(result),
      );
    }
    final statusSource = verboseText.isNotEmpty ? verboseText : text;
    final lower = statusSource.toLowerCase();
    final active = lower.contains('status: active');
    String? defaultIncoming;
    String? defaultOutgoing;
    final defaultMatch = RegExp(
      r'Default:\s*(\w+)\s*\(incoming\),\s*(\w+)\s*\(outgoing\)',
      caseSensitive: false,
    ).firstMatch(statusSource);
    if (defaultMatch != null) {
      defaultIncoming = defaultMatch.group(1);
      defaultOutgoing = defaultMatch.group(2);
    }

    final rules = <FirewallRule>[];
    // Prefer numbered status if present; otherwise parse verbose rows.
    final numbered = RegExp(r'^\s*\[\s*(\d+)\s*\]\s+(.+)$', multiLine: true);
    final numberedMatches = numbered.allMatches(text).toList();
    if (numberedMatches.isNotEmpty) {
      for (final match in numberedMatches) {
        final id = match.group(1)!;
        // Strip trailing ANSI/color leftovers and "(v6)" annotations stay.
        final body = match
            .group(2)!
            .replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '')
            .trim();
        rules.add(
          FirewallRule(
            id: id,
            display: body,
            action: _guessFirewallAction(body),
          ),
        );
      }
    } else {
      var inRules = false;
      var index = 1;
      for (final line in statusSource.split('\n')) {
        final trimmed = line.trimRight();
        if (trimmed.toLowerCase().startsWith('to ') &&
            trimmed.toLowerCase().contains('action')) {
          inRules = true;
          continue;
        }
        if (!inRules) continue;
        if (trimmed.isEmpty || trimmed.startsWith('--')) continue;
        final fields = trimmed.split(RegExp(r'\s{2,}'));
        if (fields.isEmpty) continue;
        final display = trimmed.trim();
        rules.add(
          FirewallRule(
            id: '$index',
            display: display,
            action: _guessFirewallAction(display),
            port: fields.firstOrNull?.trim(),
          ),
        );
        index++;
      }
    }

    return FirewallStatus(
      backend: FirewallBackend.ufw,
      active: active,
      rules: rules,
      defaultIncoming: defaultIncoming,
      defaultOutgoing: defaultOutgoing,
      rawStatus: statusSource,
      error: result.exitCode != 0 && !active ? _commandError(result) : null,
    );
  }

  FirewallStatus _parseFirewalldStatus(
    _CommandResult stateResult,
    _CommandResult listResult,
  ) {
    final active =
        stateResult.stdout.trim().toLowerCase() == 'running' ||
        stateResult.stderr.trim().toLowerCase() == 'running';
    final text = listResult.stdout.isNotEmpty
        ? listResult.stdout
        : listResult.stderr;
    final rules = <FirewallRule>[];
    final zones = <String>[];
    final zoneMatch = RegExp(
      r'^(\S+)\s*\(active\)',
      multiLine: true,
    ).firstMatch(text);
    if (zoneMatch != null) zones.add(zoneMatch.group(1)!);

    final portsMatch = RegExp(
      r'ports:\s*(.*)$',
      multiLine: true,
    ).firstMatch(text);
    if (portsMatch != null) {
      for (final port in portsMatch.group(1)!.split(RegExp(r'\s+'))) {
        final value = port.trim();
        if (value.isEmpty) continue;
        rules.add(
          FirewallRule(
            id: value,
            display: 'ALLOW $value',
            action: FirewallAction.allow,
            port: value,
          ),
        );
      }
    }
    final servicesMatch = RegExp(
      r'services:\s*(.*)$',
      multiLine: true,
    ).firstMatch(text);
    if (servicesMatch != null) {
      for (final service in servicesMatch.group(1)!.split(RegExp(r'\s+'))) {
        final value = service.trim();
        if (value.isEmpty) continue;
        rules.add(
          FirewallRule(
            id: 'service:$value',
            display: 'ALLOW service $value',
            action: FirewallAction.allow,
            port: value,
          ),
        );
      }
    }

    return FirewallStatus(
      backend: FirewallBackend.firewalld,
      active: active,
      rules: rules,
      zones: zones,
      rawStatus: text,
      error: !active && stateResult.exitCode != 0
          ? _commandError(stateResult)
          : null,
    );
  }

  FirewallStatus _parseNftStatus(_CommandResult result) {
    final text = result.stdout.isNotEmpty ? result.stdout : result.stderr;
    if (result.exitCode != 0 && text.trim().isEmpty) {
      return FirewallStatus(
        backend: FirewallBackend.nftables,
        active: false,
        error: _commandError(result),
      );
    }
    final rules = <FirewallRule>[];
    var index = 1;
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('table ') ||
          trimmed.startsWith('chain ') ||
          trimmed == '{' ||
          trimmed == '}') {
        continue;
      }
      rules.add(
        FirewallRule(
          id: '$index',
          display: trimmed,
          action: _guessFirewallAction(trimmed),
        ),
      );
      index++;
      if (rules.length >= 200) break;
    }
    return FirewallStatus(
      backend: FirewallBackend.nftables,
      active: text.trim().isNotEmpty,
      rules: rules,
      rawStatus: text,
    );
  }

  FirewallStatus _parseIptablesStatus(_CommandResult result) {
    final text = result.stdout.isNotEmpty ? result.stdout : result.stderr;
    if (result.exitCode != 0 && text.trim().isEmpty) {
      return FirewallStatus(
        backend: FirewallBackend.iptables,
        active: false,
        error: _commandError(result),
      );
    }
    final rules = <FirewallRule>[];
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('Chain ') ||
          trimmed.startsWith('num ') ||
          trimmed.startsWith('target ')) {
        continue;
      }
      final match = RegExp(r'^(\d+)\s+(.+)$').firstMatch(trimmed);
      if (match == null) continue;
      rules.add(
        FirewallRule(
          id: match.group(1)!,
          display: match.group(2)!.trim(),
          action: _guessFirewallAction(match.group(2)!),
        ),
      );
      if (rules.length >= 200) break;
    }
    return FirewallStatus(
      backend: FirewallBackend.iptables,
      active: rules.isNotEmpty || text.contains('Chain'),
      rules: rules,
      rawStatus: text,
    );
  }

  FirewallAction? _guessFirewallAction(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('allow') || lower.contains('accept')) {
      return FirewallAction.allow;
    }
    if (lower.contains('deny') || lower.contains('drop')) {
      return FirewallAction.deny;
    }
    if (lower.contains('reject')) return FirewallAction.reject;
    return null;
  }

  /// Lists every installed Docker and Podman environment for both the SSH user
  /// and root. Root is intentionally non-interactive: MaidKit never requests
  /// or transports a sudo password.
  Future<List<ContainerEnvironment>> listContainers(
    int serverId, {
    bool sshUserIsRoot = false,
    String? sudoPassword,
  }) async {
    return withClient(serverId, (client) async {
      final environments = <ContainerEnvironment>[];
      for (final runtime in ContainerRuntime.values) {
        final available = await _runtimeAvailable(client, runtime);
        if (!available) continue;
        final scopes = sshUserIsRoot
            ? const [ContainerScope.root]
            : ContainerScope.values;
        for (final scope in scopes) {
          environments.add(
            await _listContainerEnvironment(
              client,
              runtime,
              scope,
              sudoPassword: sudoPassword,
            ),
          );
        }
      }
      return _deduplicateContainerEnvironments(environments);
    });
  }

  /// A Docker compatibility shim backed by Podman reports the exact same
  /// containers through both CLIs. Keep one result per ID and scope, with the
  /// native Podman runtime taking precedence so future project actions use it.
  List<ContainerEnvironment> _deduplicateContainerEnvironments(
    List<ContainerEnvironment> environments,
  ) {
    final seenByScope = <ContainerScope, Set<String>>{
      for (final scope in ContainerScope.values) scope: <String>{},
    };
    final keptByEnvironment = <ContainerEnvironment, List<ServerContainer>>{};
    for (final environment in [
      ...environments,
    ]..sort((a, b) => b.runtime.index.compareTo(a.runtime.index))) {
      if (!environment.isAvailable) continue;
      final seen = seenByScope[environment.scope]!;
      keptByEnvironment[environment] = [
        for (final container in environment.containers)
          if (seen.add(container.id)) container,
      ];
    }
    return [
      for (final environment in environments)
        if (!keptByEnvironment.containsKey(environment) ||
            keptByEnvironment[environment]!.isNotEmpty)
          ContainerEnvironment(
            runtime: environment.runtime,
            scope: environment.scope,
            containers:
                keptByEnvironment[environment] ?? environment.containers,
            error: environment.error,
          ),
    ];
  }

  Future<void> runContainerAction(
    int serverId, {
    required ContainerRuntime runtime,
    required ContainerScope scope,
    required String containerId,
    required ContainerAction action,

    /// When [action] is [ContainerAction.remove], forces removal of a running
    /// container (`rm -f`). Ignored for other actions.
    bool force = false,
    String? sudoPassword,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]*$').hasMatch(containerId)) {
      throw ArgumentError.value(
        containerId,
        'containerId',
        'Invalid container ID.',
      );
    }
    final verb = action == ContainerAction.remove
        ? 'rm ${force ? '-f ' : ''}'
        : '${action.cliVerb} ';
    await withClient(serverId, (client) async {
      final result = await _execute(
        client,
        '${_scopePrefix(scope, sudoPassword)}${runtime.name} $verb$containerId',
        stdin: scope == ContainerScope.root ? sudoPassword : null,
      );
      if (result.exitCode != 0) {
        throw StateError(_commandError(result));
      }
    });
  }

  /// Executes a non-interactive command inside a running container.
  ///
  /// The command is evaluated by the container's `/bin/sh`, which preserves
  /// quoted arguments and supports custom command strings from the UI.
  Future<void> runContainerCommand(
    int serverId, {
    required ContainerRuntime runtime,
    required ContainerScope scope,
    required String containerId,
    required String command,
    String? sudoPassword,
    void Function(String chunk)? onOutput,
  }) async {
    if (!_safeContainerRef(containerId)) {
      throw ArgumentError.value(
        containerId,
        'containerId',
        'Invalid container ID.',
      );
    }
    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(command, 'command', 'Command is required.');
    }
    final cliCommand =
        '${runtime.name} exec ${_shellSingleQuote(containerId)} '
        'sh -c ${_shellSingleQuote(trimmed)}';
    final displayCommand =
        '${runtime.name} exec ${_shellSingleQuote(containerId)} $trimmed';
    await withClient(serverId, (client) async {
      onOutput?.call('\$ $displayCommand\n');
      final result = await _executeStreaming(
        client,
        '${_scopePrefix(scope, sudoPassword)}$cliCommand',
        stdin: scope == ContainerScope.root ? sudoPassword : null,
        onOutput: onOutput,
      );
      if (result.exitCode != 0) throw StateError(_commandError(result));
    });
  }

  Future<bool> _runtimeAvailable(
    SSHClient client,
    ContainerRuntime runtime,
  ) async {
    final result = await _execute(client, 'command -v ${runtime.name}');
    if (result.exitCode != 0) return false;
    if (runtime != ContainerRuntime.docker) return true;
    // Distro podman shims install `docker` as a wrapper around podman; the
    // CLI exists but answers `--version` with podman's version string. Skip
    // it while the real podman is present so containers/images are not
    // listed twice.
    final version = await _execute(client, 'docker --version');
    if (!version.stdout.toLowerCase().contains('podman')) return true;
    final podman = await _execute(client, 'command -v podman');
    return podman.exitCode != 0;
  }

  Future<ContainerEnvironment> _listContainerEnvironment(
    SSHClient client,
    ContainerRuntime runtime,
    ContainerScope scope, {
    String? sudoPassword,
  }) async {
    // Podman's `ps` reporter does not implement Docker's `.Label` template
    // field. Read the portable basic fields first, then inspect labels per
    // container; both Docker and Podman expose `.Config.Labels` there.
    final script =
        '''
${runtime.name} ps -a --format '{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.State}}\t{{.Status}}' |
while IFS="\$(printf '\t')" read -r id name image state status; do
  labels=\$(${runtime.name} inspect --format '{{with index .Config.Labels "com.docker.compose.project"}}{{.}}{{end}}\t{{with index .Config.Labels "io.podman.compose.project"}}{{.}}{{end}}' "\$id")
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "\$id" "\$name" "\$image" "\$state" "\$status" "\$labels"
done
''';
    final result = await _execute(
      client,
      _scopedShell(scope, sudoPassword, script),
      stdin: scope == ContainerScope.root ? sudoPassword : null,
    );
    if (result.exitCode != 0) {
      return ContainerEnvironment(
        runtime: runtime,
        scope: scope,
        error: _commandError(result),
      );
    }
    return ContainerEnvironment(
      runtime: runtime,
      scope: scope,
      containers: result.stdout
          .split('\n')
          .map(_parseContainer)
          .whereType<ServerContainer>()
          .toList(),
    );
  }

  Future<_CommandResult> _execute(
    SSHClient client,
    String command, {
    String? stdin,
  }) async {
    final session = await client.execute(_withRemoteToolPath(command));
    final stdout = utf8.decoder.bind(session.stdout).join();
    final stderr = utf8.decoder.bind(session.stderr).join();
    if (stdin != null) {
      session.stdin.add(Uint8List.fromList(utf8.encode('$stdin\n')));
      await session.stdin.close();
    }
    await session.done;
    return _CommandResult(
      stdout: await stdout,
      stderr: await stderr,
      exitCode: session.exitCode ?? 1,
    );
  }

  /// Streams stdout and stderr chunks while a remote command runs.
  ///
  /// When [usePty] is true (default for live task UIs), the remote process sees
  /// a terminal so tools like docker/podman emit ANSI colors and `\r` progress
  /// rewrites instead of non-interactive plain dumps.
  Future<_CommandResult> _executeStreaming(
    SSHClient client,
    String command, {
    String? stdin,
    void Function(String chunk)? onOutput,
    void Function(SSHSession session)? onSession,
    bool usePty = true,
  }) async {
    final session = await client.execute(
      _withRemoteToolPath(command),
      pty: usePty
          ? const SSHPtyConfig(type: 'xterm-256color', width: 120, height: 40)
          : null,
    );
    onSession?.call(session);
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final stdoutDone = utf8.decoder.bind(session.stdout).listen((chunk) {
      stdoutBuffer.write(chunk);
      onOutput?.call(chunk);
    }).asFuture<void>();
    final stderrDone = utf8.decoder.bind(session.stderr).listen((chunk) {
      stderrBuffer.write(chunk);
      onOutput?.call(chunk);
    }).asFuture<void>();
    if (stdin != null) {
      session.stdin.add(Uint8List.fromList(utf8.encode('$stdin\n')));
      await session.stdin.close();
    }
    await session.done;
    await Future.wait([stdoutDone, stderrDone]);
    return _CommandResult(
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
      exitCode: session.exitCode ?? 1,
    );
  }

  String _withRemoteToolPath(String command) =>
      'export PATH="$_remoteToolPath:\$PATH"; $command';

  /// Local image tags available to [runtime] under [scope], newest first.
  ///
  /// Used by autocomplete UIs; dangling / untagged images are omitted.
  Future<List<String>> listContainerImages(
    int serverId, {
    required ContainerRuntime runtime,
    required ContainerScope scope,
    String? sudoPassword,
  }) async {
    return withClient(serverId, (client) async {
      final result = await _execute(
        client,
        '${_scopePrefix(scope, sudoPassword)}'
        "${runtime.name} images --format '{{.Repository}}:{{.Tag}}'",
        stdin: scope == ContainerScope.root ? sudoPassword : null,
      );
      if (result.exitCode != 0) throw StateError(_commandError(result));
      final images = <String>{};
      for (final line in result.stdout.split('\n')) {
        final image = line.trim();
        if (image.isEmpty ||
            image == '<none>:<none>' ||
            image.endsWith(':<none>')) {
          continue;
        }
        images.add(image);
      }
      return images.toList()..sort();
    });
  }

  /// Lists Docker and Podman images for the SSH user and root environments.
  Future<List<ImageEnvironment>> listImages(
    int serverId, {
    bool sshUserIsRoot = false,
    String? sudoPassword,
  }) async {
    return withClient(serverId, (client) async {
      final environments = <ImageEnvironment>[];
      for (final runtime in ContainerRuntime.values) {
        final available = await _runtimeAvailable(client, runtime);
        if (!available) continue;
        final scopes = sshUserIsRoot
            ? const [ContainerScope.root]
            : ContainerScope.values;
        for (final scope in scopes) {
          environments.add(
            await _listImageEnvironment(
              client,
              runtime,
              scope,
              sudoPassword: sudoPassword,
            ),
          );
        }
      }
      return _deduplicateImageEnvironments(environments);
    });
  }

  /// Same Docker-via-Podman shim handling as containers: prefer Podman when
  /// both CLIs report an identical image id under the same scope.
  List<ImageEnvironment> _deduplicateImageEnvironments(
    List<ImageEnvironment> environments,
  ) {
    final seenByScope = <ContainerScope, Set<String>>{
      for (final scope in ContainerScope.values) scope: <String>{},
    };
    final keptByEnvironment = <ImageEnvironment, List<ServerContainerImage>>{};
    for (final environment in [
      ...environments,
    ]..sort((a, b) => b.runtime.index.compareTo(a.runtime.index))) {
      if (!environment.isAvailable) continue;
      final seen = seenByScope[environment.scope]!;
      keptByEnvironment[environment] = [
        for (final image in environment.images)
          if (seen.add(image.id)) image,
      ];
    }
    return [
      for (final environment in environments)
        if (!keptByEnvironment.containsKey(environment) ||
            keptByEnvironment[environment]!.isNotEmpty)
          ImageEnvironment(
            runtime: environment.runtime,
            scope: environment.scope,
            images: keptByEnvironment[environment] ?? environment.images,
            error: environment.error,
          ),
    ];
  }

  Future<ImageEnvironment> _listImageEnvironment(
    SSHClient client,
    ContainerRuntime runtime,
    ContainerScope scope, {
    String? sudoPassword,
  }) async {
    final prefix = _scopePrefix(scope, sudoPassword);
    final stdin = scope == ContainerScope.root ? sudoPassword : null;
    final result = await _execute(
      client,
      '$prefix'
      "${runtime.name} images --format "
      "'{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}'",
      stdin: stdin,
    );
    if (result.exitCode != 0) {
      return ImageEnvironment(
        runtime: runtime,
        scope: scope,
        error: _commandError(result),
      );
    }
    final parsed = result.stdout
        .split('\n')
        .map(_parseImage)
        .whereType<ServerContainerImage>()
        .toList();
    final used = await _listUsedImageMarkers(
      client,
      runtime,
      scope,
      sudoPassword: sudoPassword,
    );
    return ImageEnvironment(
      runtime: runtime,
      scope: scope,
      images: [
        for (final image in parsed)
          image.copyWith(unused: !_imageIsInUse(image, used)),
      ],
    );
  }

  /// Collects image IDs and name refs attached to any container so unused
  /// labels match what `image prune -a` would reclaim.
  Future<({Set<String> ids, Set<String> refs})> _listUsedImageMarkers(
    SSHClient client,
    ContainerRuntime runtime,
    ContainerScope scope, {
    String? sudoPassword,
  }) async {
    final stdin = scope == ContainerScope.root ? sudoPassword : null;
    // Image config name from `ps` (may be short) plus canonical Image ID from
    // inspect (sha256:…) so tag rewrites and digests still match.
    final script =
        '''
ids=\$(${runtime.name} ps -aq 2>/dev/null)
if [ -n "\$ids" ]; then
  ${runtime.name} ps -a --no-trunc --format '{{.Image}}'
  ${runtime.name} inspect --format '{{.Image}}' \$ids 2>/dev/null
fi
''';
    final result = await _execute(
      client,
      _scopedShell(scope, sudoPassword, script),
      stdin: stdin,
    );
    if (result.exitCode != 0 && result.stdout.trim().isEmpty) {
      return (ids: <String>{}, refs: <String>{});
    }
    final ids = <String>{};
    final refs = <String>{};
    for (final line in result.stdout.split('\n')) {
      final raw = line.trim();
      if (raw.isEmpty) continue;
      final withoutDigest = raw.split('@').first.trim();
      if (withoutDigest.startsWith('sha256:')) {
        final full = withoutDigest.substring(7);
        ids.add(full);
        if (full.length >= 12) ids.add(full.substring(0, 12));
      } else if (RegExp(r'^[a-f0-9]{12,64}$').hasMatch(withoutDigest)) {
        ids.add(withoutDigest);
        if (withoutDigest.length >= 12) {
          ids.add(withoutDigest.substring(0, 12));
        }
      } else {
        refs.add(withoutDigest);
        final slash = withoutDigest.lastIndexOf('/');
        final name = slash >= 0
            ? withoutDigest.substring(slash + 1)
            : withoutDigest;
        refs.add(name);
        if (!name.contains(':')) {
          refs.add('$name:latest');
        }
      }
    }
    return (ids: ids, refs: refs);
  }

  bool _imageIsInUse(
    ServerContainerImage image,
    ({Set<String> ids, Set<String> refs}) used,
  ) {
    final id = image.id.trim();
    final idBare = id.startsWith('sha256:') ? id.substring(7) : id;
    if (used.ids.contains(id) ||
        used.ids.contains(idBare) ||
        (idBare.length >= 12 && used.ids.contains(idBare.substring(0, 12)))) {
      return true;
    }
    for (final usedId in used.ids) {
      if (usedId.length >= 12 &&
          idBare.length >= 12 &&
          (usedId.startsWith(idBare) || idBare.startsWith(usedId))) {
        return true;
      }
    }

    final repository = image.repository.trim();
    final tag = image.tag.trim();
    if (repository.isEmpty || repository == '<none>') return false;

    final candidates = <String>{
      image.reference,
      repository,
      if (tag.isNotEmpty && tag != '<none>') '$repository:$tag',
      if (tag.isEmpty || tag == '<none>') '$repository:latest',
    };
    // Short names: docker.io/library/nginx:latest ↔ nginx:latest ↔ nginx
    final shortRepo = repository.contains('/')
        ? repository.split('/').last
        : repository;
    candidates.add(shortRepo);
    if (tag.isNotEmpty && tag != '<none>') {
      candidates.add('$shortRepo:$tag');
    } else {
      candidates.add('$shortRepo:latest');
    }

    for (final candidate in candidates) {
      if (used.refs.contains(candidate)) return true;
      for (final ref in used.refs) {
        if (ref == candidate ||
            ref.endsWith('/$candidate') ||
            candidate.endsWith('/$ref') ||
            ref.endsWith(':$candidate') ||
            candidate.endsWith(':$ref')) {
          return true;
        }
      }
    }
    return false;
  }

  ServerContainerImage? _parseImage(String line) {
    final fields = line.split('\t');
    if (fields.length < 5 || fields[0].trim().isEmpty) return null;
    return ServerContainerImage(
      id: fields[0].trim(),
      repository: fields[1].trim(),
      tag: fields[2].trim(),
      size: fields[3].trim(),
      created: fields[4].trim(),
    );
  }

  Future<void> runImageAction(
    int serverId, {
    required ContainerRuntime runtime,
    required ContainerScope scope,
    required String imageId,
    required ImageAction action,
    String? sudoPassword,
    void Function(String chunk)? onOutput,
  }) async {
    if (!_safeContainerRef(imageId)) {
      throw ArgumentError.value(imageId, 'imageId', 'Invalid image ID.');
    }
    final command = switch (action) {
      ImageAction.remove => '${runtime.name} rmi $imageId',
    };
    await withClient(serverId, (client) async {
      onOutput?.call('\$ $command\n');
      final result = await _executeStreaming(
        client,
        '${_scopePrefix(scope, sudoPassword)}$command',
        stdin: scope == ContainerScope.root ? sudoPassword : null,
        onOutput: onOutput,
      );
      if (result.exitCode != 0) {
        throw StateError(_commandError(result));
      }
    });
  }

  /// Runs `docker|podman image prune` with optional live [onOutput] streaming.
  ///
  /// Without [allUnused], only dangling (untagged) images are removed. With
  /// [allUnused] (`-a`), every image not used by a container is removed —
  /// matching the UI "Unused" label for tagged images.
  Future<void> pruneImages(
    int serverId, {
    required ContainerRuntime runtime,
    required ContainerScope scope,
    bool force = true,
    bool allUnused = false,
    String? sudoPassword,
    void Function(String chunk)? onOutput,
  }) async {
    final flags = StringBuffer();
    if (allUnused) flags.write(' -a');
    if (force) flags.write(' -f');
    final displayCmd = '${runtime.name} image prune$flags';
    await withClient(serverId, (client) async {
      onOutput?.call('\$ $displayCmd\n');
      final result = await _executeStreaming(
        client,
        '${_scopePrefix(scope, sudoPassword)}$displayCmd',
        stdin: scope == ContainerScope.root ? sudoPassword : null,
        onOutput: onOutput,
      );
      if (result.exitCode != 0) {
        throw StateError(_commandError(result));
      }
    });
  }

  ServerContainer? _parseContainer(String line) {
    final fields = line.split('\t');
    if (fields.length != 7 || fields.take(5).any((field) => field.isEmpty)) {
      return null;
    }
    return ServerContainer(
      id: fields[0],
      name: fields[1],
      image: fields[2],
      state: fields[3],
      status: fields[4],
      composeProject: fields[5].isEmpty
          ? (fields[6].isEmpty ? null : fields[6])
          : fields[5],
    );
  }

  Future<void> deployComposeProject(
    int serverId, {
    required ContainerRuntime runtime,
    required ContainerScope scope,
    required String projectName,
    required String directory,
    required String composeSource,
    String? sudoPassword,
    void Function(String chunk)? onOutput,
  }) async {
    if (!_safeProjectName(projectName) || !_safeRemoteDirectory(directory)) {
      throw ArgumentError('Project name or remote directory is invalid.');
    }
    final encoded = base64.encode(utf8.encode(composeSource));
    await withClient(serverId, (client) async {
      // Keep every part of the deployment in the same privileged shell. A
      // prefix on only `mkdir` leaves the redirected file write running as the
      // SSH user, which fails for folders such as /srv.
      final script =
          'mkdir -p $directory && '
          'printf %s $encoded | base64 -d > $directory/compose.yaml && '
          'cd $directory && COMPOSE_ANSI=always ${runtime.name} compose '
          '--ansi always -p $projectName up -d';
      final command = _scopedShell(scope, sudoPassword, script);
      onOutput?.call(
        '\$ ${runtime.name} compose -p $projectName up -d  ($directory)\n',
      );
      final result = await _executeStreaming(
        client,
        command,
        stdin: scope == ContainerScope.root ? sudoPassword : null,
        onOutput: onOutput,
      );
      if (result.exitCode != 0) throw StateError(_commandError(result));
    });
  }

  /// Reads the first conventional compose file from a directory using the
  /// selected container scope. This is intentionally command based rather
  /// than SFTP so root-owned project folders can be imported as well.
  Future<(String source, String fileName)?> readComposeFile(
    int serverId, {
    required ContainerScope scope,
    required String directory,
    String? sudoPassword,
  }) async {
    if (!_safeRemoteDirectory(directory)) {
      throw ArgumentError.value(directory, 'directory', 'Invalid directory.');
    }
    const names = [
      'compose.yaml',
      'compose.yml',
      'docker-compose.yaml',
      'docker-compose.yml',
    ];
    final checks = names
        .map(
          (name) =>
              'if [ -f $directory/$name ]; then '
              'printf "%s\\n" $name; cat $directory/$name; exit 0; fi',
        )
        .join('; ');
    return withClient(serverId, (client) async {
      final result = await _execute(
        client,
        _scopedShell(scope, sudoPassword, '$checks; exit 2'),
        stdin: scope == ContainerScope.root ? sudoPassword : null,
      );
      if (result.exitCode == 2) return null;
      if (result.exitCode != 0) throw StateError(_commandError(result));
      final split = result.stdout.indexOf('\n');
      if (split <= 0) return null;
      return (
        result.stdout.substring(split + 1).trimRight(),
        result.stdout.substring(0, split),
      );
    });
  }

  Future<void> startRawContainer(
    int serverId, {
    required ContainerRuntime runtime,
    required ContainerScope scope,
    required String image,
    required String name,
    String arguments = '',
    String? sudoPassword,
    void Function(String chunk)? onOutput,
  }) async {
    if (!_safeProjectName(name) || image.trim().isEmpty) {
      throw ArgumentError('Container name and image are required.');
    }
    // Arguments are deliberately a terminal-like escape hatch. The image and
    // name remain validated, while advanced runtime flags stay available.
    final command =
        '${_scopePrefix(scope, sudoPassword)}${runtime.name} run -d '
        '--name $name ${arguments.isEmpty ? '' : '$arguments '}$image';
    await withClient(serverId, (client) async {
      onOutput?.call(
        '\$ ${runtime.name} run -d --name $name '
        '${arguments.isEmpty ? '' : '$arguments '}$image\n',
      );
      final result = await _executeStreaming(
        client,
        command,
        stdin: scope == ContainerScope.root ? sudoPassword : null,
        onOutput: onOutput,
      );
      if (result.exitCode != 0) throw StateError(_commandError(result));
    });
  }

  bool _safeContainerRef(String value) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]*$').hasMatch(value);

  /// Full inspect payload for one container, including fields used to rebuild
  /// a `run` command.
  Future<ContainerInspectDetail> inspectContainer(
    int serverId, {
    required ContainerRuntime runtime,
    required ContainerScope scope,
    required String containerId,
    String? sudoPassword,
  }) async {
    if (!_safeContainerRef(containerId)) {
      throw ArgumentError.value(containerId, 'containerId', 'Invalid id.');
    }
    return withClient(serverId, (client) async {
      final result = await _execute(
        client,
        '${_scopePrefix(scope, sudoPassword)}'
        "${runtime.name} inspect --format '{{json .}}' $containerId",
        stdin: scope == ContainerScope.root ? sudoPassword : null,
      );
      if (result.exitCode != 0) throw StateError(_commandError(result));
      final raw = result.stdout.trim();
      if (raw.isEmpty) {
        throw StateError('Inspect returned no data for $containerId.');
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Inspect payload was not a JSON object.');
      }
      return _parseContainerInspect(decoded, rawJson: raw);
    });
  }

  /// Recent container logs (`stdout`/`stderr` merged by the runtime).
  ///
  /// Docker/Podman send the container's stdout to the CLI's stdout and the
  /// container's stderr to the CLI's stderr, so both streams must be merged.
  Future<String> readContainerLogs(
    int serverId, {
    required ContainerRuntime runtime,
    required ContainerScope scope,
    required String containerId,
    int tail = 300,
    bool timestamps = false,
    String? sudoPassword,
  }) async {
    if (!_safeContainerRef(containerId)) {
      throw ArgumentError.value(containerId, 'containerId', 'Invalid id.');
    }
    final safeTail = tail.clamp(1, 5000);
    return withClient(serverId, (client) async {
      final flags = StringBuffer('--tail $safeTail');
      if (timestamps) flags.write(' --timestamps');
      final result = await _execute(
        client,
        '${_scopePrefix(scope, sudoPassword)}'
        '${runtime.name} logs $flags $containerId',
        stdin: scope == ContainerScope.root ? sudoPassword : null,
      );
      final merged = _mergeContainerLogStreams(result.stdout, result.stderr);
      // Missing container / permission errors have no log body.
      if (result.exitCode != 0 && merged.trim().isEmpty) {
        throw StateError(_commandError(result));
      }
      return merged;
    });
  }

  /// Merged logs for every service in a Compose project.
  ///
  /// Uses `compose logs` so multi-service stacks keep the service-name prefix
  /// on each line. Tail applies per service (Compose CLI behavior).
  Future<String> readComposeProjectLogs(
    int serverId, {
    required ContainerRuntime runtime,
    required ContainerScope scope,
    required String projectName,
    required String directory,
    int tail = 300,
    bool timestamps = false,
    String? sudoPassword,
  }) async {
    if (!_safeProjectName(projectName) || !_safeRemoteDirectory(directory)) {
      throw ArgumentError('Project name or remote directory is invalid.');
    }
    final safeTail = tail.clamp(1, 5000);
    return withClient(serverId, (client) async {
      final flags = StringBuffer('--tail $safeTail');
      if (timestamps) flags.write(' --timestamps');
      final composeCmd = '${runtime.name} compose -p $projectName logs $flags';
      final result = await _execute(
        client,
        _scopedShell(scope, sudoPassword, 'cd $directory && $composeCmd'),
        stdin: scope == ContainerScope.root ? sudoPassword : null,
      );
      final merged = _mergeContainerLogStreams(result.stdout, result.stderr);
      if (result.exitCode != 0 && merged.trim().isEmpty) {
        throw StateError(_commandError(result));
      }
      return merged;
    });
  }

  /// Live-follow one container's logs (`docker|podman logs -f`).
  ///
  /// Call [LogFollowHandle.cancel] when leaving the page or restarting the
  /// stream so the remote process is stopped.
  Future<LogFollowHandle> followContainerLogs(
    int serverId, {
    required ContainerRuntime runtime,
    required ContainerScope scope,
    required String containerId,
    required void Function(String chunk) onChunk,
    int tail = 300,
    bool timestamps = false,
    String? sudoPassword,
  }) async {
    if (!_safeContainerRef(containerId)) {
      throw ArgumentError.value(containerId, 'containerId', 'Invalid id.');
    }
    final safeTail = tail.clamp(1, 5000);
    final flags = StringBuffer('--follow --tail $safeTail');
    if (timestamps) flags.write(' --timestamps');
    return _startLogFollow(
      serverId,
      command:
          '${_scopePrefix(scope, sudoPassword)}'
          '${runtime.name} logs $flags $containerId',
      stdin: scope == ContainerScope.root ? sudoPassword : null,
      onChunk: onChunk,
    );
  }

  /// Live-follow every service in a Compose project (`compose logs -f`).
  Future<LogFollowHandle> followComposeProjectLogs(
    int serverId, {
    required ContainerRuntime runtime,
    required ContainerScope scope,
    required String projectName,
    required String directory,
    required void Function(String chunk) onChunk,
    int tail = 300,
    bool timestamps = false,
    String? sudoPassword,
  }) async {
    if (!_safeProjectName(projectName) || !_safeRemoteDirectory(directory)) {
      throw ArgumentError('Project name or remote directory is invalid.');
    }
    final safeTail = tail.clamp(1, 5000);
    final flags = StringBuffer('--follow --tail $safeTail');
    if (timestamps) flags.write(' --timestamps');
    final composeCmd = '${runtime.name} compose -p $projectName logs $flags';
    return _startLogFollow(
      serverId,
      command: _scopedShell(
        scope,
        sudoPassword,
        'cd $directory && $composeCmd',
      ),
      stdin: scope == ContainerScope.root ? sudoPassword : null,
      onChunk: onChunk,
    );
  }

  /// Opens a long-running log session and streams stdout/stderr as text chunks.
  Future<LogFollowHandle> _startLogFollow(
    int serverId, {
    required String command,
    String? stdin,
    required void Function(String chunk) onChunk,
  }) async {
    final client = clientFor(serverId);
    if (client == null) throw const ServerConnectionRequiredException();
    // No PTY: keep log bytes line-oriented without terminal reflow.
    final session = await client.execute(command);
    var cancelled = false;
    final stdoutSub = utf8.decoder.bind(session.stdout).listen((chunk) {
      if (chunk.isNotEmpty) onChunk(chunk);
    });
    final stderrSub = utf8.decoder.bind(session.stderr).listen((chunk) {
      if (chunk.isNotEmpty) onChunk(chunk);
    });
    if (stdin != null) {
      session.stdin.add(Uint8List.fromList(utf8.encode('$stdin\n')));
      await session.stdin.close();
    }

    final done = () async {
      try {
        await session.done;
      } finally {
        await Future.wait([stdoutSub.cancel(), stderrSub.cancel()]);
      }
    }();

    return LogFollowHandle._(
      done: done,
      cancel: () async {
        if (cancelled) return;
        cancelled = true;
        try {
          session.kill(SSHSignal.TERM);
        } catch (_) {}
        try {
          session.close();
        } catch (_) {}
        try {
          await done;
        } catch (_) {}
      },
    );
  }

  /// Joins CLI stdout and stderr without dropping either stream.
  String _mergeContainerLogStreams(String stdout, String stderr) {
    final out = stdout;
    final err = stderr;
    if (out.isEmpty) return err;
    if (err.isEmpty) return out;
    if (out.endsWith('\n') || out.endsWith('\r')) return '$out$err';
    return '$out\n$err';
  }

  Future<void> removeContainer(
    int serverId, {
    required ContainerRuntime runtime,
    required ContainerScope scope,
    required String containerId,
    bool force = false,
    String? sudoPassword,
    void Function(String chunk)? onOutput,
  }) async {
    if (!_safeContainerRef(containerId)) {
      throw ArgumentError.value(containerId, 'containerId', 'Invalid id.');
    }
    final command =
        '${_scopePrefix(scope, sudoPassword)}'
        '${runtime.name} rm ${force ? '-f ' : ''}$containerId';
    await withClient(serverId, (client) async {
      onOutput?.call(
        '\$ ${runtime.name} rm ${force ? '-f ' : ''}$containerId\n',
      );
      final result = await _executeStreaming(
        client,
        command,
        stdin: scope == ContainerScope.root ? sudoPassword : null,
        onOutput: onOutput,
      );
      if (result.exitCode != 0) throw StateError(_commandError(result));
    });
  }

  ContainerInspectDetail _parseContainerInspect(
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

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const {};
  }

  List<dynamic> _asList(Object? value) {
    if (value is List) return value;
    return const [];
  }

  /// Runs a compose project action with optional live [onOutput] streaming
  /// (same pattern as [startRawContainer] / [deployComposeProject]).
  Future<void> runComposeProjectAction(
    int serverId, {
    required ContainerRuntime runtime,
    required ContainerScope scope,
    required String projectName,
    required String directory,
    required ComposeProjectAction action,
    String? sudoPassword,
    void Function(String chunk)? onOutput,
  }) async {
    if (!_safeProjectName(projectName) || !_safeRemoteDirectory(directory)) {
      throw ArgumentError('Project name or remote directory is invalid.');
    }
    // Force ANSI + a real TTY so pull/up progress bars and colors stream live.
    final composeCmd =
        'COMPOSE_ANSI=always ${runtime.name} compose --ansi always '
        '-p $projectName ${action.composeArgs}';
    final displayCmd =
        '${runtime.name} compose -p $projectName ${action.composeArgs}';
    await withClient(serverId, (client) async {
      onOutput?.call('\$ $displayCmd  ($directory)\n');
      final result = await _executeStreaming(
        client,
        _scopedShell(scope, sudoPassword, 'cd $directory && $composeCmd'),
        stdin: scope == ContainerScope.root ? sudoPassword : null,
        onOutput: onOutput,
      );
      if (result.exitCode != 0) throw StateError(_commandError(result));
    });
  }

  /// One-shot resource sample from `docker stats` / `podman stats`.
  ///
  /// When [containerIds] is non-empty, only those containers are sampled.
  /// Stopped IDs are ignored by the runtime and simply omit a row.
  Future<List<ContainerStats>> listContainerStats(
    int serverId, {
    required ContainerRuntime runtime,
    required ContainerScope scope,
    List<String> containerIds = const [],
    String? sudoPassword,
  }) async {
    for (final id in containerIds) {
      if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$').hasMatch(id)) {
        throw ArgumentError.value(id, 'containerIds', 'Invalid container ID.');
      }
    }
    return withClient(serverId, (client) async {
      final targets = containerIds.isEmpty ? '' : ' ${containerIds.join(' ')}';
      // Go templates are portable across Docker and Podman for these fields.
      final script =
          '${runtime.name} stats --no-stream --format '
          "'{{.ID}}\\t{{.Name}}\\t{{.CPUPerc}}\\t{{.MemUsage}}\\t{{.MemPerc}}"
          "\\t{{.NetIO}}\\t{{.BlockIO}}\\t{{.PIDs}}'$targets";
      final result = await _execute(
        client,
        _scopedShell(scope, sudoPassword, script),
        stdin: scope == ContainerScope.root ? sudoPassword : null,
      );
      if (result.exitCode != 0) {
        // Empty set (no running containers) is not an error for the UI.
        final message = _commandError(result).toLowerCase();
        if (message.contains('no such container') ||
            message.contains('you must provide at least one') ||
            message.contains('no containers') ||
            result.stdout.trim().isEmpty) {
          return const [];
        }
        throw StateError(_commandError(result));
      }
      return result.stdout
          .split('\n')
          .map(_parseContainerStats)
          .whereType<ContainerStats>()
          .toList();
    });
  }

  ContainerStats? _parseContainerStats(String line) {
    final fields = line.split('\t');
    if (fields.length < 8) return null;
    final id = fields[0].trim();
    final name = fields[1].trim();
    if (id.isEmpty || name.isEmpty) return null;
    final memParts = _splitIoPair(fields[3]);
    final netParts = _splitIoPair(fields[5]);
    final blockParts = _splitIoPair(fields[6]);
    return ContainerStats(
      id: id,
      name: name,
      cpuPercent: _parsePercent(fields[2]),
      memUsage: fields[3].trim(),
      memPercent: _parsePercent(fields[4]),
      memUsedBytes: memParts.$1,
      memLimitBytes: memParts.$2,
      netIO: fields[5].trim(),
      netRxBytes: netParts.$1,
      netTxBytes: netParts.$2,
      blockIO: fields[6].trim(),
      blockReadBytes: blockParts.$1,
      blockWriteBytes: blockParts.$2,
      pids: int.tryParse(fields[7].trim()),
    );
  }

  double? _parsePercent(String raw) {
    final cleaned = raw.trim().replaceAll('%', '');
    if (cleaned.isEmpty || cleaned == '--') return null;
    return double.tryParse(cleaned);
  }

  /// Parses Docker/Podman pairs such as `1.2MiB / 2GiB` or `1.1kB / 2.2kB`.
  (int?, int?) _splitIoPair(String raw) {
    final parts = raw.split('/');
    if (parts.length != 2) return (null, null);
    return (_parseHumanSize(parts[0]), _parseHumanSize(parts[1]));
  }

  int? _parseHumanSize(String raw) {
    final match = RegExp(
      r'^\s*([\d.]+)\s*([A-Za-z]+)?\s*$',
    ).firstMatch(raw.trim());
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!);
    if (value == null) return null;
    final unit = (match.group(2) ?? 'B').toLowerCase();
    final multiplier = switch (unit) {
      'b' => 1,
      'kb' || 'k' => 1000,
      'kib' => 1024,
      'mb' || 'm' => 1000 * 1000,
      'mib' => 1024 * 1024,
      'gb' || 'g' => 1000 * 1000 * 1000,
      'gib' => 1024 * 1024 * 1024,
      'tb' || 't' => 1000 * 1000 * 1000 * 1000,
      'tib' => 1024 * 1024 * 1024 * 1024,
      _ => 1,
    };
    return (value * multiplier).round();
  }

  bool _safeProjectName(String value) =>
      RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]*$').hasMatch(value);

  bool _safePackageName(String value) =>
      RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9+_.:@/-]*$').hasMatch(value);

  String _packageExecutable(PackageManager manager) => switch (manager) {
    PackageManager.apt => 'apt-get',
    PackageManager.dnf => 'dnf',
    PackageManager.yum => 'yum',
    PackageManager.pacman => 'pacman',
    PackageManager.zypper => 'zypper',
    PackageManager.apk => 'apk',
    PackageManager.xbps => 'xbps-install',
    PackageManager.brew => 'brew',
  };

  String _packageOutdatedCommand(PackageManager manager) => switch (manager) {
    PackageManager.apt =>
      "apt list --upgradable 2>/dev/null | sed '1d' | cut -d/ -f1",
    PackageManager.dnf =>
      'dnf -q check-update 2>/dev/null | awk \'NF >= 3 {print \$1}\'',
    PackageManager.yum =>
      'yum -q check-update 2>/dev/null | awk \'NF >= 3 {print \$1}\'',
    PackageManager.pacman => 'pacman -Qu 2>/dev/null | awk \'{print \$1}\'',
    PackageManager.zypper =>
      'zypper --non-interactive list-updates 2>/dev/null | awk \'/^v / {print \$3}\'',
    PackageManager.apk => 'apk version -l "<" 2>/dev/null | cut -d" " -f1',
    PackageManager.xbps =>
      'xbps-install -Mun 2>/dev/null | awk \'{print \$1}\'',
    PackageManager.brew => 'HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --formula',
  };

  String _installedPackageCountCommand(PackageManager manager) =>
      switch (manager) {
        PackageManager.apt => r"dpkg-query -W -f='${binary:Package}\n' | wc -l",
        PackageManager.dnf ||
        PackageManager.yum ||
        PackageManager.zypper => 'rpm -qa | wc -l',
        PackageManager.pacman => 'pacman -Qq | wc -l',
        PackageManager.apk => 'apk info | wc -l',
        PackageManager.xbps => 'xbps-query -l | wc -l',
        PackageManager.brew =>
          'HOMEBREW_NO_AUTO_UPDATE=1 brew list --formula | wc -l',
      };

  String _packageInstallationStatusCommand(
    PackageManager manager,
    Iterable<String> names,
  ) {
    final packages = names
        .where(_safePackageName)
        .map(_shellSingleQuote)
        .join(' ');
    final check = switch (manager) {
      PackageManager.apt =>
        "dpkg-query -W -f='\${db:Status-Status}' \$package 2>/dev/null | grep -qx installed",
      PackageManager.dnf ||
      PackageManager.yum ||
      PackageManager.zypper => 'rpm -q \$package >/dev/null 2>&1',
      PackageManager.pacman => 'pacman -Q \$package >/dev/null 2>&1',
      PackageManager.apk => 'apk info -e \$package >/dev/null 2>&1',
      PackageManager.xbps => 'xbps-query -p pkgver \$package >/dev/null 2>&1',
      PackageManager.brew =>
        'HOMEBREW_NO_AUTO_UPDATE=1 brew list --formula "\$package" '
            '>/dev/null 2>&1',
    };
    return 'for package in $packages; do if $check; then '
        'printf "%s\\t1\\n" "\$package"; else '
        'printf "%s\\t0\\n" "\$package"; fi; done';
  }

  String _packageSearchCommand(PackageManager manager, String query) {
    final pattern = '$query*';
    return switch (manager) {
      PackageManager.apt =>
        "apt-cache search --names-only '^$query' | head -n 80",
      PackageManager.dnf => 'dnf -q search $pattern 2>/dev/null | head -n 80',
      PackageManager.yum => 'yum -q search $pattern 2>/dev/null | head -n 80',
      PackageManager.pacman => 'pacman -Ss ^$query 2>/dev/null | head -n 160',
      PackageManager.zypper =>
        'zypper --non-interactive search $pattern 2>/dev/null | head -n 80',
      PackageManager.apk => 'apk search -v $pattern 2>/dev/null | head -n 80',
      PackageManager.xbps => 'xbps-query -Rs $query 2>/dev/null | head -n 80',
      PackageManager.brew =>
        'HOMEBREW_NO_AUTO_UPDATE=1 brew search --formula '
            '${_shellSingleQuote(pattern)} | head -n 80',
    };
  }

  String _packageActionCommand(
    PackageManager manager,
    PackageAction action,
    String? packageName,
  ) {
    final name = packageName ?? '';
    return switch ((manager, action)) {
      (PackageManager.apt, PackageAction.refresh) => 'apt-get update',
      (PackageManager.apt, PackageAction.upgrade) =>
        'env DEBIAN_FRONTEND=noninteractive apt-get -y upgrade',
      (PackageManager.apt, PackageAction.install) =>
        'env DEBIAN_FRONTEND=noninteractive apt-get -y install $name',
      (PackageManager.apt, PackageAction.remove) =>
        'env DEBIAN_FRONTEND=noninteractive apt-get -y remove $name',
      (PackageManager.dnf, PackageAction.refresh) ||
      (
        PackageManager.yum,
        PackageAction.refresh,
      ) => '${_packageExecutable(manager)} makecache',
      (PackageManager.dnf, PackageAction.upgrade) ||
      (
        PackageManager.yum,
        PackageAction.upgrade,
      ) => '${_packageExecutable(manager)} -y upgrade',
      (PackageManager.dnf, PackageAction.install) ||
      (
        PackageManager.yum,
        PackageAction.install,
      ) => '${_packageExecutable(manager)} -y install $name',
      (PackageManager.dnf, PackageAction.remove) ||
      (
        PackageManager.yum,
        PackageAction.remove,
      ) => '${_packageExecutable(manager)} -y remove $name',
      (PackageManager.pacman, PackageAction.refresh) => 'pacman -Sy',
      (PackageManager.pacman, PackageAction.upgrade) =>
        'pacman --noconfirm -Syu',
      (PackageManager.pacman, PackageAction.install) =>
        'pacman --noconfirm -S $name',
      (PackageManager.pacman, PackageAction.remove) =>
        'pacman --noconfirm -R $name',
      (PackageManager.zypper, PackageAction.refresh) =>
        'zypper --non-interactive refresh',
      (PackageManager.zypper, PackageAction.upgrade) =>
        'zypper --non-interactive update',
      (PackageManager.zypper, PackageAction.install) =>
        'zypper --non-interactive install $name',
      (PackageManager.zypper, PackageAction.remove) =>
        'zypper --non-interactive remove $name',
      (PackageManager.apk, PackageAction.refresh) => 'apk update',
      (PackageManager.apk, PackageAction.upgrade) => 'apk upgrade',
      (PackageManager.apk, PackageAction.install) => 'apk add $name',
      (PackageManager.apk, PackageAction.remove) => 'apk del $name',
      (PackageManager.xbps, PackageAction.refresh) => 'xbps-install -S',
      (PackageManager.xbps, PackageAction.upgrade) => 'xbps-install -yu',
      (PackageManager.xbps, PackageAction.install) => 'xbps-install -y $name',
      (PackageManager.xbps, PackageAction.remove) => 'xbps-remove -y $name',
      (PackageManager.brew, PackageAction.refresh) => 'brew update',
      (PackageManager.brew, PackageAction.upgrade) =>
        'HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade',
      (PackageManager.brew, PackageAction.install) =>
        'HOMEBREW_NO_AUTO_UPDATE=1 brew install $name',
      (PackageManager.brew, PackageAction.remove) =>
        'HOMEBREW_NO_AUTO_UPDATE=1 brew uninstall $name',
    };
  }

  List<String> _parsePackageNames(String output) => output
      .split('\n')
      .map((line) => line.trim().split(RegExp(r'\s+')).firstOrNull ?? '')
      .where((name) => _safePackageName(name))
      .toSet()
      .take(80)
      .toList();

  List<PackageSearchResult> _parsePackageSearch(String output) => output
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('Last metadata'))
      .map((line) {
        final fields = line.split(RegExp(r'\s+'));
        final name = fields.first.split('/').first;
        return PackageSearchResult(
          name: name,
          version: fields.length > 1 ? fields[1] : null,
          description: fields.length > 2 ? fields.skip(2).join(' ') : null,
        );
      })
      .where((result) => _safePackageName(result.name))
      .take(80)
      .toList();

  Set<String> _parseInstalledPackageNames(String output) => output
      .split('\n')
      .map((line) => line.split('\t'))
      .where((fields) => fields.length == 2 && fields[1].trim() == '1')
      .map((fields) => fields.first.trim())
      .where(_safePackageName)
      .toSet();

  bool _safeRemoteDirectory(String value) =>
      RegExp(r'^/[a-zA-Z0-9_./-]+$').hasMatch(value) && !value.contains('..');

  String _scopedShell(
    ContainerScope scope,
    String? sudoPassword,
    String script,
  ) {
    final encoded = base64.encode(utf8.encode(script));
    final shell = 'echo $encoded | base64 -d | sh';
    return switch (scope) {
      ContainerScope.user => shell,
      ContainerScope.root =>
        '${_scopePrefix(scope, sudoPassword)}sh -c "$shell"',
    };
  }

  String _scopePrefix(ContainerScope scope, String? sudoPassword) =>
      switch (scope) {
        ContainerScope.user => '',
        ContainerScope.root =>
          sudoPassword == null ? 'sudo -n ' : 'sudo -S -p "" ',
      };

  String _commandError(_CommandResult result) {
    final message = result.stderr.trim().isNotEmpty
        ? result.stderr.trim()
        : result.stdout.trim();
    return message.isEmpty
        ? 'The command exited with code ${result.exitCode}.'
        : message;
  }

  Future<void> _refreshStats(SSHClient client, SshSessionInfo state) async {
    try {
      final stats = await _metricsCollector.collect(client);
      if (stats != null && identical(_sessions[state.serverId], client)) {
        _set((_states[state.serverId] ?? state).copyWith(stats: stats));
      }
    } catch (_) {
      // Statistics are optional and can be unavailable on restricted hosts.
    }
  }

  Future<void> _refreshSystemInfo(
    SSHClient client,
    SshSessionInfo state,
  ) async {
    try {
      final windowsResult = await _execute(client, _windowsSystemInfoCommand());
      if (windowsResult.exitCode == 0 &&
          windowsResult.stdout.contains('--WINDOWS--')) {
        final values = windowsResult.stdout
            .split('\n')
            .where((line) => line.isNotEmpty && line != '--WINDOWS--')
            .toList();
        if (values.isNotEmpty && identical(_sessions[state.serverId], client)) {
          _set(
            (_states[state.serverId] ?? state).copyWith(
              systemInfo: ServerSystemInfo(
                distribution: values.first,
                kernel: values.length > 1 ? values[1] : null,
              ),
            ),
          );
        }
        return;
      }
      final session = await client.execute(r"""sh -c '
if command -v sw_vers >/dev/null 2>&1; then
  printf "%s %s\n" "$(sw_vers -productName)" "$(sw_vers -productVersion)"
elif [ -r /etc/os-release ]; then
  . /etc/os-release
  printf "%s\n" "$PRETTY_NAME"
else
  uname -s
fi
uname -r
'""");
      final output = await utf8.decoder.bind(session.stdout).join();
      await session.done;
      final values = output.trim().split('\n');
      if (values.isNotEmpty && identical(_sessions[state.serverId], client)) {
        _set(
          (_states[state.serverId] ?? state).copyWith(
            systemInfo: ServerSystemInfo(
              distribution: values.firstOrNull,
              kernel: values.length > 1 ? values[1] : null,
            ),
          ),
        );
      }
    } catch (_) {
      // System information is optional on restricted or non-POSIX hosts.
    }
  }

  Future<void> connect(
    Server server,
    ServerCredential credential,
    HostKeyApproval approve, {
    String? knownHostKeyFingerprint,
    ServerProxy? proxy,
  }) async {
    await disconnect(server.id);
    _set(
      SshSessionInfo(
        serverId: server.id,
        serverName: server.name,
        connectedAt: DateTime.now(),
        status: SessionStatus.connecting,
      ),
    );
    String? serverAuthMethods;
    try {
      final client = await _createClient(
        server,
        credential,
        approve,
        knownHostKeyFingerprint: knownHostKeyFingerprint,
        onAuthMethods: (methods) => serverAuthMethods = methods,
        proxy: proxy,
      );
      _sessions[server.id] = client;
      _sessionJumpHosts[server.id] = server.jumpHostServerId;
      _set(_states[server.id]!.copyWith(status: SessionStatus.connected));
      onConnected?.call(server);
      // Listen before issuing probes: a transport can fail while the first
      // command is being opened, and [SSHClient.done] completes with that
      // transport error.
      unawaited(
        client.done.then<void>(
          (_) => _handleClientClosed(server, client),
          onError: (Object error, StackTrace _) {
            _handleClientClosed(server, client, error: error);
          },
        ),
      );
      unawaited(
        _refreshNetworkLatency(server, _states[server.id]!).catchError((_) {}),
      );
      unawaited(_refreshConnectionDetails(server, client));
    } catch (error) {
      final message = error is SSHAuthFailError
          ? serverAuthMethods == null || serverAuthMethods!.isEmpty
                ? 'The server rejected the supplied password.'
                : 'The server rejected the supplied password. It advertises: $serverAuthMethods.'
          : error.toString();
      _set(
        _states[server.id]!.copyWith(
          status: SessionStatus.failed,
          error: message,
        ),
      );
      rethrow;
    }
  }

  void _handleClientClosed(Server server, SSHClient client, {Object? error}) {
    if (!identical(_sessions[server.id], client)) return;
    _sessions.remove(server.id);
    _sessionJumpHosts.remove(server.id);
    unawaited(_closeDependentSessions(server.id));
    unawaited(_closeTerminalsFor(server.id));
    unawaited(_closeTerminalsForJumpHost(server.id));
    unawaited(_stopPortForwardsFor(server.id));
    final state = _states[server.id];
    if (state != null && state.status == SessionStatus.connected) {
      _set(
        state.copyWith(
          status: SessionStatus.closed,
          error: error == null ? 'SSH connection closed.' : error.toString(),
        ),
      );
    }
  }

  Future<void> _refreshConnectionDetails(
    Server server,
    SSHClient client,
  ) async {
    final state = _states[server.id];
    if (!identical(_sessions[server.id], client) || state == null) return;
    if (server.collectStats) await _refreshStats(client, state);
    if (server.collectSystemInfo) {
      await _refreshSystemInfo(client, _states[server.id] ?? state);
    }
  }

  Future<void> disconnect(int serverId) async {
    await _closeDependentSessions(serverId);
    await _stopPortForwardsFor(serverId);
    await _closeTerminalsForJumpHost(serverId);
    final client = _sessions.remove(serverId);
    _sessionJumpHosts.remove(serverId);
    client?.close();
    final state = _states[serverId];
    if (state != null) _set(state.copyWith(status: SessionStatus.closed));
  }

  void _set(SshSessionInfo value) {
    _states[value.serverId] = value;
    _controller.add(current);
  }

  Future<void> dispose() async {
    for (final terminalId in _terminals.keys.toList()) {
      await closeTerminal(terminalId);
    }
    for (final serverId in _sessions.keys.toList()) {
      await disconnect(serverId);
    }
    for (final id in _portForwards.keys.toList()) {
      await _stopPortForward(id, allowManaged: true);
    }
    await _controller.close();
    await _portForwardController.close();
  }

  Future<void> _closeDependentSessions(int serverId) async {
    final dependentIds = _sessionJumpHosts.entries
        .where((entry) => entry.value == serverId)
        .map((entry) => entry.key)
        .toList();
    for (final dependentId in dependentIds) {
      await disconnect(dependentId);
    }
  }

  Future<void> _stopPortForwardsFor(int serverId) async {
    final ids = _portForwards.entries
        .where((entry) => entry.value.info.serverId == serverId)
        .map((entry) => entry.key)
        .toList();
    for (final id in ids) {
      await _stopPortForward(id, allowManaged: true);
    }
  }

  Future<void> _closeTerminalsFor(int serverId) async {
    final terminalIds = _terminals.entries
        .where((entry) => entry.value.serverId == serverId)
        .map((entry) => entry.key)
        .toList();
    for (final terminalId in terminalIds) {
      await closeTerminal(terminalId);
    }
  }

  Future<void> _closeTerminalsForJumpHost(int serverId) async {
    final terminalIds = _terminals.entries
        .where((entry) => entry.value.jumpHostServerId == serverId)
        .map((entry) => entry.key)
        .toList();
    for (final terminalId in terminalIds) {
      await closeTerminal(terminalId);
    }
  }

  ServerProcess? _parseProcess(String line) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length < 6) return null;
    final pid = int.tryParse(fields[0]);
    final cpuPercent = double.tryParse(fields[2]);
    final memoryPercent = double.tryParse(fields[3]);
    final rssKb = int.tryParse(fields[4]);
    if (pid == null ||
        cpuPercent == null ||
        memoryPercent == null ||
        rssKb == null) {
      return null;
    }
    return ServerProcess(
      pid: pid,
      user: fields[1],
      cpuPercent: cpuPercent,
      memoryPercent: memoryPercent,
      rssKb: rssKb,
      command: fields.sublist(5).join(' '),
    );
  }

  Future<SSHClient> _createClient(
    Server server,
    ServerCredential credential,
    HostKeyApproval approve, {
    String? knownHostKeyFingerprint,
    void Function(String? methods)? onAuthMethods,
    ServerProxy? proxy,
  }) async {
    final identities = credential.type == CredentialType.privateKey
        ? SSHKeyPair.fromPem(credential.privateKey!, credential.keyPassphrase)
        : null;
    final rawSocket = server.jumpHostServerId != null
        ? await _socketThroughJumpHost(server)
        : isTailnetAddress(server.host) && tailscaleSupported
        ? await TailscaleSshSocket.connect(server.host, server.port)
        : await _LowLatencySshSocket.connect(
            server.host,
            server.port,
            proxy: proxy,
          );
    final socket = _SafeSshSocket(rawSocket);
    final client = SSHClient(
      socket,
      username: server.username,
      identities: identities,
      onPasswordRequest: credential.type == CredentialType.password
          ? () => credential.password
          : null,
      onUserInfoRequest: credential.type == CredentialType.password
          ? (request) => List<String>.filled(
              request.prompts.length,
              credential.password!,
            )
          : null,
      onVerifyHostKey: (algorithm, fingerprint) {
        final presented =
            'SHA256:${base64Encode(fingerprint).replaceAll('=', '')}';
        if (knownHostKeyFingerprint == presented) return true;
        return approve(
          HostKeyPrompt(
            algorithm: algorithm,
            fingerprint: presented,
            replacesExisting: knownHostKeyFingerprint != null,
          ),
        );
      },
      printTrace: (message) {
        final match = RegExp(
          r'SSH_Message_Userauth_Failure\(methodsLeft: \[(.*?)\]',
        ).firstMatch(message ?? '');
        if (match != null) onAuthMethods?.call(match.group(1));
      },
      handshakeTimeout: const Duration(seconds: 15),
      authTimeout: const Duration(seconds: 15),
      ident: "MaidKit",
    );
    await client.authenticated;
    return client;
  }

  Future<SSHSocket> _socketThroughJumpHost(Server server) async {
    final jumpHostServerId = server.jumpHostServerId!;
    final jumpClient = clientFor(jumpHostServerId);
    if (jumpClient == null) {
      throw JumpHostConnectionRequiredException(jumpHostServerId);
    }
    return jumpClient.forwardLocal(server.host, server.port);
  }
}

/// Prevents dartssh2's asynchronous channel uploader from throwing after the
/// underlying socket has already completed. The transport closure is still
/// reported through [SSHClient.done]; closed writes are deliberately dropped.
class _SafeSshSocket implements SSHSocket {
  _SafeSshSocket(this._delegate) {
    unawaited(
      _delegate.done.then<void>(
        (_) => _closed = true,
        onError: (_, _) => _closed = true,
      ),
    );
  }

  final SSHSocket _delegate;
  var _closed = false;
  late final StreamSink<List<int>> _safeSink = _SafeSshSink(
    _delegate.sink,
    () => _closed,
    () => _closed = true,
  );

  @override
  Stream<Uint8List> get stream => _delegate.stream;
  @override
  StreamSink<List<int>> get sink => _safeSink;

  @override
  Future<void> get done => _delegate.done;

  @override
  Future<void> close() => _delegate.close();

  @override
  void destroy() => _delegate.destroy();

  @override
  Future<void> flush() => _delegate.flush();

  @override
  String toString() => _delegate.toString();
}

class _SafeSshSink implements StreamSink<List<int>> {
  _SafeSshSink(this._delegate, this._isClosed, this._markClosed);

  final StreamSink<List<int>> _delegate;
  final bool Function() _isClosed;
  final void Function() _markClosed;

  @override
  void add(List<int> data) {
    if (_isClosed()) return;
    try {
      _delegate.add(data);
    } on StateError catch (error) {
      if (!error.toString().contains('StreamSink is bound to a stream')) {
        rethrow;
      }
      _markClosed();
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_isClosed()) return;
    _delegate.addError(error, stackTrace);
  }

  @override
  Future<void> close() => _delegate.close();

  @override
  Future<void> get done => _delegate.done;

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      _delegate.addStream(stream);
}

/// An SSH socket with Nagle's algorithm disabled.
///
/// Interactive terminals commonly send one small packet for each key press.
/// Waiting for an acknowledgement before transmitting a subsequent packet can
/// turn normal network round-trip time into very noticeable typing lag.
class _LowLatencySshSocket implements SSHSocket {
  _LowLatencySshSocket._(this._socket);

  final Socket _socket;

  static Future<SSHSocket> connect(
    String host,
    int port, {
    ServerProxy? proxy,
  }) async {
    if (proxy == null || proxy.type == ServerProxyType.none) {
      final socket = await Socket.connect(host, port);
      socket.setOption(SocketOption.tcpNoDelay, true);
      return _LowLatencySshSocket._(socket);
    }
    return connectThroughProxy(proxy, host, port);
  }

  @override
  Stream<Uint8List> get stream => _socket;

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> close() => _socket.close();

  @override
  void destroy() => _socket.destroy();

  @override
  Future<void> flush() => _socket.flush();

  @override
  String toString() => _socket.toString();
}

class TerminalSessionHandle {
  const TerminalSessionHandle({
    required this.id,
    required this.adapter,
    required this.done,
  });

  final String id;
  final TerminalSessionAdapter adapter;
  final Future<void> done;
}

class _TerminalConnection {
  const _TerminalConnection({
    required this.serverId,
    required this.jumpHostServerId,
    required this.client,
    required this.shell,
    required this.binding,
  });

  final int serverId;
  final int? jumpHostServerId;
  final SSHClient client;
  final SSHSession shell;
  final TerminalSessionBinding binding;
}

/// Handle for a live `logs -f` stream. Call [cancel] to stop the remote process.
class LogFollowHandle {
  LogFollowHandle._({required this.done, required this._cancel});

  /// Completes when the remote log process exits or is cancelled.
  final Future<void> done;
  final Future<void> Function() _cancel;
  var _cancelled = false;

  bool get isCancelled => _cancelled;

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    await _cancel();
  }
}

class _PortForwardingConnection {
  _PortForwardingConnection.local(this.info, this.localListener)
    : remoteForward = null;

  _PortForwardingConnection.remote(this.info, this.remoteForward)
    : localListener = null;

  final ActivePortForward info;
  final ServerSocket? localListener;
  final SSHRemoteForward? remoteForward;
  StreamSubscription<Object?>? subscription;

  Future<void> close() async {
    await subscription?.cancel();
    await localListener?.close();
    remoteForward?.close();
  }
}

class _CommandResult {
  const _CommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  final String stdout;
  final String stderr;
  final int exitCode;
}

/// Bridges [SshConnectionManager] command execution to [WebServerRemote].
class _SshWebServerRemote implements WebServerRemote {
  _SshWebServerRemote({required this.execute, required this.quoteFn});

  final Future<WebServerCommandResult> Function(
    String command, {
    bool privileged,
    String? stdinPayload,
  })
  execute;
  final String Function(String value) quoteFn;

  @override
  Future<WebServerCommandResult> run(
    String command, {
    bool privileged = false,
    String? stdinPayload,
  }) => execute(command, privileged: privileged, stdinPayload: stdinPayload);

  @override
  String quote(String value) => quoteFn(value);
}

String _windowsActivityCommand() => encodePowerShellCommand(r'''
$ErrorActionPreference = 'Stop'
$os = Get-CimInstance Win32_OperatingSystem
$processors = @(Get-CimInstance Win32_Processor)
$cpuCount = [int](($processors | Measure-Object NumberOfLogicalProcessors -Sum).Sum)
$loadPercent = [double](($processors | Measure-Object LoadPercentage -Average).Average)
$load = if ($cpuCount -gt 0) { $loadPercent * $cpuCount / 100 } else { 0 }
$pageFiles = @(Get-CimInstance Win32_PageFileUsage)
$swapTotalKb = [int64](($pageFiles | Measure-Object AllocatedBaseSize -Sum).Sum)
$swapUsedKb = [int64](($pageFiles | Measure-Object CurrentUsage -Sum).Sum)
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$net = @(Get-NetAdapterStatistics -ErrorAction SilentlyContinue)
$rx = [int64](($net | Measure-Object ReceivedBytes -Sum).Sum)
$tx = [int64](($net | Measure-Object SentBytes -Sum).Sum)
Write-Output '--WINDOWS--'
Write-Output '--CPUUSAGE--'
$loadPercent
Write-Output '--LOAD--'
$load
Write-Output '--CPU--'
$cpuCount
Write-Output '--MEM--'
"MemTotal: $($os.TotalVisibleMemorySize)"
"MemAvailable: $($os.FreePhysicalMemory)"
Write-Output '--SWAP--'
"SwapTotal: $swapTotalKb"
"SwapFree: $([math]::Max(0, $swapTotalKb - $swapUsedKb))"
Write-Output '--DISK--'
if ($null -ne $disk) {
  "DiskTotal: $([int64]($disk.Size / 1KB))"
  "DiskAvailable: $([int64]($disk.FreeSpace / 1KB))"
}
Write-Output '--NET--'
"RxBytes: $rx"
"TxBytes: $tx"
Write-Output '--UPTIME--'
[int64](([DateTime]::UtcNow - $os.LastBootUpTime.ToUniversalTime()).TotalSeconds)
''');

String _windowsProcessCommand(int limit) => encodePowerShellCommand('''
\$ErrorActionPreference = 'Stop'
\$os = Get-CimInstance Win32_OperatingSystem
\$totalMemory = [double]\$os.TotalVisibleMemorySize * 1KB
Write-Output '--WINDOWS--'
Get-Process |
  Sort-Object WorkingSet64 -Descending |
  Select-Object -First $limit |
  ForEach-Object {
    \$memoryPercent = if (\$totalMemory -gt 0) {
      100 * \$_.WorkingSet64 / \$totalMemory
    } else { 0 }
    '{0} {1} 0 {2} {3} {4}' -f \$_.Id, \$env:USERNAME,
      ([math]::Round(\$memoryPercent, 2)),
      ([int64](\$_.WorkingSet64 / 1KB)), \$_.ProcessName
  }
''');

String _windowsSystemInfoCommand() => encodePowerShellCommand(r'''
$ErrorActionPreference = 'Stop'
$os = Get-CimInstance Win32_OperatingSystem
Write-Output '--WINDOWS--'
$os.Caption
$os.Version
''');
