import 'web_server_adapter.dart';
import 'web_server_models.dart';

/// Caddy management via the `caddy` CLI and `caddy.service`.
class CaddyWebServerAdapter
    with WebServerSystemdHelpers
    implements WebServerAdapter {
  const CaddyWebServerAdapter();

  @override
  String get id => 'caddy';

  @override
  String get label => 'Caddy';

  @override
  String get binaryName => 'caddy';

  @override
  String get serviceUnit => 'caddy.service';

  static const _defaultConfigCandidates = [
    '/etc/caddy/Caddyfile',
    '/etc/caddy/caddy.conf',
    '/usr/local/etc/caddy/Caddyfile',
    '/opt/caddy/Caddyfile',
  ];

  @override
  Future<bool> isInstalled(WebServerRemote remote) async {
    final path = await resolveBinaryPath(remote);
    return path != null;
  }

  @override
  Future<WebServerStatus> loadStatus(WebServerRemote remote) async {
    final binaryPath = await resolveBinaryPath(remote);
    if (binaryPath == null) {
      return const WebServerStatus(
        adapterId: 'caddy',
        label: 'Caddy',
        installed: false,
        error: 'caddy was not found on PATH.',
      );
    }

    final version = await _readVersion(remote);
    final service = await readServiceState(remote);
    final configPath = await _resolveConfigPath(remote);
    final validation = await _validate(remote, configPath: configPath);
    final sites = await _listSites(remote, configPath: configPath);

    return WebServerStatus(
      adapterId: id,
      label: label,
      installed: true,
      binaryPath: binaryPath,
      version: version,
      serviceUnit: serviceUnit,
      running: service.running,
      enabled: service.enabled,
      configPath: configPath,
      configValid: validation.$1,
      configMessage: validation.$2,
      sites: sites,
    );
  }

  @override
  Future<void> runAction(WebServerRemote remote, WebServerAction action) async {
    if (action == WebServerAction.reload) {
      // Prefer graceful config reload when a Caddyfile is known.
      final configPath = await _resolveConfigPath(remote);
      if (configPath != null) {
        final result = await remote.run(
          'caddy reload --config ${remote.quote(configPath)}',
          privileged: true,
        );
        if (result.exitCode == 0) return;
        // Fall through to systemctl reload if admin API is unavailable.
      }
    }
    await runSystemctl(remote, action);
  }

  @override
  Future<String> validateConfig(WebServerRemote remote) async {
    final configPath = await _resolveConfigPath(remote);
    if (configPath == null) {
      throw StateError('Could not locate a Caddyfile on this host.');
    }
    final result = await remote.run(
      'caddy validate --config ${remote.quote(configPath)} 2>&1',
      privileged: true,
    );
    final text = result.combined.trim();
    if (result.exitCode != 0) {
      throw StateError(
        text.isEmpty
            ? 'caddy validate failed (exit ${result.exitCode}).'
            : text,
      );
    }
    return text.isEmpty ? 'Valid configuration' : text;
  }

  @override
  Future<String> readConfig(WebServerRemote remote, {String? siteId}) async {
    final path = await _configPathFor(remote, siteId: siteId);
    return readFile(remote, path);
  }

  @override
  Future<void> writeConfig(
    WebServerRemote remote, {
    required String content,
    String? siteId,
  }) async {
    final path = await _configPathFor(remote, siteId: siteId);
    await writeFile(remote, path, content);
  }

  Future<String> _configPathFor(
    WebServerRemote remote, {
    String? siteId,
  }) async {
    // Caddy sites are typically blocks inside one Caddyfile.
    final path = siteId ?? await _resolveConfigPath(remote);
    if (path == null) {
      throw StateError('Could not locate a Caddyfile on this host.');
    }
    if (!isSafeConfigPath(path)) {
      throw ArgumentError.value(path, 'siteId', 'Unsafe config path.');
    }
    return path;
  }

  @override
  Future<String> getLogs(WebServerRemote remote, {int lines = 200}) =>
      readJournal(remote, lines: lines);

  Future<String?> _readVersion(WebServerRemote remote) async {
    final result = await remote.run('caddy version 2>&1');
    final text = result.combined.trim();
    if (text.isEmpty) return null;
    // "v2.7.6 h1:..." or "2.7.6"
    final match = RegExp(r'v?(\d+\.\d+\.\d+)').firstMatch(text);
    return match?.group(1) ?? text.split(RegExp(r'\s+')).first;
  }

  Future<String?> _resolveConfigPath(WebServerRemote remote) async {
    // Prefer the unit's ExecStart --config / Environment when available.
    final unitShow = await remote.run(
      "systemctl show caddy.service -p ExecStart -p FragmentPath --value 2>/dev/null || true",
    );
    final unitText = unitShow.combined;
    final execMatch = RegExp(r'--config[=\s]+(\S+)').firstMatch(unitText);
    if (execMatch != null) {
      final path = execMatch.group(1)!.replaceAll('"', '');
      if (isSafeConfigPath(path)) return path;
    }

    for (final candidate in _defaultConfigCandidates) {
      final check = await remote.run(
        'test -f ${remote.quote(candidate)} && echo yes || true',
      );
      if (check.stdout.trim() == 'yes') return candidate;
    }
    return null;
  }

  Future<(bool?, String?)> _validate(
    WebServerRemote remote, {
    required String? configPath,
  }) async {
    if (configPath == null) return (null, 'No Caddyfile found.');
    final result = await remote.run(
      'caddy validate --config ${remote.quote(configPath)} 2>&1',
      privileged: true,
    );
    final text = result.combined.trim();
    if (text.isEmpty && result.exitCode != 0) {
      return (null, 'Could not validate configuration.');
    }
    return (result.exitCode == 0, text.isEmpty ? null : text);
  }

  Future<List<WebServerSite>> _listSites(
    WebServerRemote remote, {
    required String? configPath,
  }) async {
    if (configPath == null) return const [];
    try {
      final content = await readFile(remote, configPath);
      final blocks = parseCaddyfileSiteBlocks(content);
      if (blocks.isEmpty) {
        return [
          WebServerSite(
            id: configPath,
            name: _basename(configPath),
            path: configPath,
            kind: WebServerSiteKind.main,
          ),
        ];
      }
      return [
        for (final block in blocks)
          WebServerSite(
            id: configPath,
            name: block.address,
            path: configPath,
            serverNames: [block.address],
            kind: WebServerSiteKind.site,
            upstream: block.upstream,
            https: caddySiteUsesHttps(block.address),
          ),
      ];
    } catch (_) {
      return [
        WebServerSite(
          id: configPath,
          name: _basename(configPath),
          path: configPath,
          kind: WebServerSiteKind.main,
        ),
      ];
    }
  }

  String _basename(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }
}

/// Extracts top-level site addresses from a Caddyfile.
///
/// Handles common forms:
/// - `example.com { ... }`
/// - `example.com, www.example.com { ... }`
/// - `:80 { ... }`
/// - `https://example.com { ... }`
///
/// Skips global options blocks (`{ ... }` at column 0) and snippet definitions
/// (`(snippet) { ... }`).
List<String> parseCaddyfileSiteAddresses(String content) => [
  for (final block in parseCaddyfileSiteBlocks(content)) block.address,
];

/// One top-level site block: its address and the upstream it forwards to.
class CaddySiteBlock {
  const CaddySiteBlock({required this.address, this.upstream});

  final String address;
  final String? upstream;
}

/// Every top-level site block in a Caddyfile, with the first
/// `reverse_proxy` target declared inside each. Site blocks with no proxy
/// directive still appear, with no upstream.
List<CaddySiteBlock> parseCaddyfileSiteBlocks(String content) {
  final blocks = <CaddySiteBlock>[];
  final seen = <String>{};
  final lines = content.split('\n');
  // Brace depth of the line currently being read.
  var depth = 0;
  // Depth that enclosed the open site body, or -1 when no site is open.
  var siteDepth = -1;
  var siteAddresses = <String>[];
  // Depth of an open nested `reverse_proxy { … }` block, or -1.
  var proxyBlockDepth = -1;
  String? upstream;

  for (final raw in lines) {
    final line = raw.trim();
    final open = '{'.allMatches(raw).length;
    final close = '}'.allMatches(raw).length;
    final nextDepth = depth + open - close;
    if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) {
      depth = nextDepth < 0 ? 0 : nextDepth;
      continue;
    }

    if (siteDepth >= 0) {
      // Inside a site body: the first proxy directive names its upstream.
      // Both forms count — `reverse_proxy host:port`, and a nested
      // `reverse_proxy { to host:port }` block.
      if (proxyBlockDepth >= 0 &&
          nextDepth >= proxyBlockDepth &&
          nextDepth > siteDepth) {
        if (upstream == null && line.startsWith('to ')) {
          upstream = line.split(RegExp(r'\s+')).last;
        }
      } else if (upstream == null && nextDepth > siteDepth) {
        final target = _reverseProxyTarget(line);
        if (target != null) {
          upstream = target;
        } else if (line.endsWith('{') && line.startsWith('reverse_proxy')) {
          proxyBlockDepth = nextDepth;
        }
      }
      if (nextDepth < proxyBlockDepth) proxyBlockDepth = -1;
      if (nextDepth <= siteDepth) {
        for (final address in siteAddresses) {
          blocks.add(CaddySiteBlock(address: address, upstream: upstream));
        }
        siteDepth = -1;
        siteAddresses = const [];
        proxyBlockDepth = -1;
        upstream = null;
      }

      depth = nextDepth < 0 ? 0 : nextDepth;
      continue;
    }

    if (depth != 0) {
      depth = nextDepth < 0 ? 0 : nextDepth;
      continue;
    }

    // Global options: a lone `{` or `{ key ...`.
    if (line == '{' || line.startsWith('{')) {
      depth = nextDepth < 0 ? 0 : nextDepth;
      continue;
    }
    // Named snippet: (foo) {
    if (line.startsWith('(')) {
      depth = nextDepth < 0 ? 0 : nextDepth;
      continue;
    }

    final siteLine = line.contains('{')
        ? line.substring(0, line.indexOf('{')).trim()
        : line;
    if (siteLine.isNotEmpty && _looksLikeSiteAddress(siteLine)) {
      // A multi-host block becomes one row per host: a route table reads by
      // hostname, not by brace group.
      final addresses = <String>[];
      for (final part in siteLine.split(',')) {
        final address = part.trim();
        if (address.isNotEmpty && seen.add(address)) addresses.add(address);
      }
      if (addresses.isNotEmpty) {
        if (nextDepth > 0) {
          siteDepth = depth;
          siteAddresses = addresses;
          upstream = null;
        } else {
          for (final address in addresses) {
            blocks.add(CaddySiteBlock(address: address));
          }
        }
      }
    }
    depth = nextDepth < 0 ? 0 : nextDepth;
  }
  for (final address in siteAddresses) {
    blocks.add(CaddySiteBlock(address: address, upstream: upstream));
  }
  return blocks;
}

/// A `reverse_proxy host:port` target on [line], or null.
String? _reverseProxyTarget(String line) {
  final match = RegExp(r'^reverse_proxy\s+(?:@\S+\s+)?(\S+)').firstMatch(line);
  if (match == null) return null;
  final target = match.group(1)!.trim();
  if (target.isEmpty || target.startsWith('{')) return null;
  return target;
}

/// Whether Caddy terminates TLS for [address]. Automatic HTTPS applies to
/// bare hostnames; `http://` and port-only listeners serve plaintext.
bool caddySiteUsesHttps(String address) {
  final value = address.trim().toLowerCase();
  if (value.startsWith('http://')) return false;
  if (value.startsWith('https://')) return true;
  if (value.startsWith(':')) return false;
  return value.contains('.');
}

bool _looksLikeSiteAddress(String text) {
  // Reject pure directives that sometimes appear at top level.
  final first = text.split(RegExp(r'\s+')).first.toLowerCase();
  const directives = {
    'import',
    'email',
    'debug',
    'order',
    'storage',
    'servers',
    'acme_ca',
    'acme_dns',
    'on_demand_tls',
    'local_certs',
    'auto_https',
    'default_sni',
    'grace_period',
    'log',
    'admin',
  };
  if (directives.contains(first)) return false;
  // Site addresses typically contain a host, path, or listen port.
  return text.contains('.') ||
      text.contains(':') ||
      text.contains('/') ||
      text.contains('*') ||
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(text);
}
