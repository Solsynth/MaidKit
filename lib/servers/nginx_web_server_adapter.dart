import 'web_server_adapter.dart';
import 'web_server_models.dart';

/// Nginx management via the `nginx` CLI and `nginx.service`.
class NginxWebServerAdapter
    with WebServerSystemdHelpers
    implements WebServerAdapter {
  const NginxWebServerAdapter();

  @override
  String get id => 'nginx';

  @override
  String get label => 'Nginx';

  @override
  String get binaryName => 'nginx';

  @override
  String get serviceUnit => 'nginx.service';

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
        adapterId: 'nginx',
        label: 'Nginx',
        installed: false,
        error: 'nginx was not found on PATH.',
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
  Future<void> runAction(WebServerRemote remote, WebServerAction action) =>
      runSystemctl(remote, action);

  @override
  Future<String> validateConfig(WebServerRemote remote) async {
    final configPath = await _resolveConfigPath(remote);
    final result = await _runNginxTest(remote, configPath: configPath);
    final text = result.combined.trim();
    if (result.exitCode != 0) {
      throw StateError(
        text.isEmpty ? 'nginx -t failed (exit ${result.exitCode}).' : text,
      );
    }
    return text.isEmpty ? 'nginx: configuration file syntax is ok' : text;
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
    if (siteId != null) {
      if (!isSafeConfigPath(siteId)) {
        throw ArgumentError.value(siteId, 'siteId', 'Unsafe config path.');
      }
      return siteId;
    }
    final configPath = await _resolveConfigPath(remote);
    if (configPath == null) {
      throw StateError('Could not determine the nginx configuration path.');
    }
    return configPath;
  }

  @override
  Future<String> getLogs(WebServerRemote remote, {int lines = 200}) async {
    try {
      return await readJournal(remote, lines: lines);
    } catch (_) {
      final n = lines.clamp(1, 2000);
      final result = await remote.run(
        'sh -c \'for f in /var/log/nginx/error.log /var/log/nginx/access.log; '
        'do if [ -f "\$f" ]; then echo "===== \$f ====="; '
        'tail -n $n "\$f"; echo; fi; done\'',
        privileged: true,
      );
      if (result.exitCode != 0 && result.stdout.trim().isEmpty) {
        throw StateError(
          result.combined.trim().isEmpty
              ? 'Could not read nginx logs.'
              : result.combined.trim(),
        );
      }
      final text = result.stdout.trim();
      return text.isEmpty ? 'No nginx log files found.' : text;
    }
  }

  Future<String?> _readVersion(WebServerRemote remote) async {
    final result = await remote.run('nginx -v 2>&1');
    final text = result.combined.trim();
    if (text.isEmpty) return null;
    // "nginx version: nginx/1.24.0"
    final match = RegExp(r'nginx/([\d.]+)').firstMatch(text);
    return match?.group(1) ??
        text.replaceFirst(RegExp(r'^nginx version:\s*'), '');
  }

  Future<String?> _resolveConfigPath(WebServerRemote remote) async {
    final fromV = await remote.run('nginx -V 2>&1');
    final confMatch = RegExp(
      r'--conf-path=([^\s]+)',
    ).firstMatch(fromV.combined);
    if (confMatch != null) {
      final path = confMatch.group(1)!.trim();
      if (isSafeConfigPath(path)) return path;
    }
    for (final candidate in const [
      '/etc/nginx/nginx.conf',
      '/usr/local/etc/nginx/nginx.conf',
      '/usr/local/nginx/conf/nginx.conf',
    ]) {
      final check = await remote.run(
        'test -f ${remote.quote(candidate)} && echo yes || true',
      );
      if (check.stdout.trim() == 'yes') return candidate;
    }
    return '/etc/nginx/nginx.conf';
  }

  Future<(bool?, String?)> _validate(
    WebServerRemote remote, {
    required String? configPath,
  }) async {
    final result = await _runNginxTest(remote, configPath: configPath);
    final text = result.combined.trim();
    if (text.isEmpty && result.exitCode != 0) {
      return (null, 'Could not validate configuration.');
    }
    return (result.exitCode == 0, text.isEmpty ? null : text);
  }

  Future<WebServerCommandResult> _runNginxTest(
    WebServerRemote remote, {
    required String? configPath,
  }) {
    final confArg = configPath != null && isSafeConfigPath(configPath)
        ? ' -c ${remote.quote(configPath)}'
        : '';
    // nginx -t writes diagnostics to stderr; needs root for private includes.
    return remote.run('nginx -t$confArg 2>&1', privileged: true);
  }

  Future<List<WebServerSite>> _listSites(
    WebServerRemote remote, {
    required String? configPath,
  }) async {
    final script = r'''
sh -c '
dirs=""
for d in /etc/nginx/sites-enabled /etc/nginx/conf.d /usr/local/etc/nginx/sites-enabled /usr/local/etc/nginx/conf.d; do
  if [ -d "$d" ]; then dirs="$dirs $d"; fi
done
if [ -z "$dirs" ]; then
  echo "--NONE--"
  exit 0
fi
for d in $dirs; do
  for f in "$d"/*; do
    [ -e "$f" ] || continue
    [ -f "$f" ] || [ -L "$f" ] || continue
    case "$f" in
      *.bak|*.old|*.rpmnew|*.dpkg-*|*.swp|*~) continue ;;
    esac
    real=$(readlink -f "$f" 2>/dev/null || echo "$f")
    names=$(grep -E "^[[:space:]]*server_name[[:space:]]" "$f" 2>/dev/null | head -n 8 | sed -E "s/^[[:space:]]*server_name[[:space:]]+//; s/;[[:space:]]*$//" | tr "\n" " " | sed "s/[[:space:]]\+/ /g")
    listens=$(grep -E "^[[:space:]]*listen[[:space:]]" "$f" 2>/dev/null | head -n 8 | sed -E "s/^[[:space:]]*listen[[:space:]]+//; s/;[[:space:]]*$//" | tr "\n" " " | sed "s/[[:space:]]\+/ /g")
    upstream=$(grep -E "^[[:space:]]*proxy_pass[[:space:]]" "$f" 2>/dev/null | head -n 1 | sed -E "s/^[[:space:]]*proxy_pass[[:space:]]+//; s/;[[:space:]]*$//" | tr -d "\\r\\n")
    tls=no
    case "$listens" in *ssl*) tls=yes ;; esac
    base=$(basename "$f")
    enabled=yes
    if [ -d /etc/nginx/sites-available ] && [ -d /etc/nginx/sites-enabled ]; then
      case "$f" in
        /etc/nginx/sites-enabled/*) enabled=yes ;;
        *) enabled=yes ;;
      esac
    fi
    printf "FILE\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$base" "$real" "$enabled" "$names" "$listens" "$upstream" "$tls"
  done
done
'
''';
    final result = await remote.run(script, privileged: true);
    final text = result.stdout;
    if (text.contains('--NONE--') || text.trim().isEmpty) {
      // Fall back to the main config as a single "site" entry.
      if (configPath != null) {
        return [
          WebServerSite(
            id: configPath,
            name: 'nginx.conf',
            path: configPath,
            kind: WebServerSiteKind.main,
          ),
        ];
      }
      return const [];
    }
    return parseNginxSiteListing(text);
  }
}

/// Parses the tab-separated site listing produced by [NginxWebServerAdapter].
List<WebServerSite> parseNginxSiteListing(String text) {
  final sites = <WebServerSite>[];
  final seen = <String>{};
  for (final line in text.split('\n')) {
    if (!line.startsWith('FILE\t')) continue;
    final parts = line.split('\t');
    if (parts.length < 3) continue;
    final name = parts[1].trim();
    final path = parts[2].trim();
    if (name.isEmpty || path.isEmpty || !isSafeConfigPath(path)) continue;
    if (!seen.add(path)) continue;
    final enabled = parts.length < 4 || parts[3].trim().toLowerCase() != 'no';
    final serverNames = parts.length > 4
        ? _splitTokens(parts[4])
        : const <String>[];
    final listen = parts.length > 5 ? _splitTokens(parts[5]) : const <String>[];
    final upstream = parts.length > 6 && parts[6].trim().isNotEmpty
        ? parts[6].trim()
        : null;
    final https = parts.length > 7 && parts[7].trim().toLowerCase() == 'yes';
    sites.add(
      WebServerSite(
        id: path,
        name: name,
        path: path,
        enabled: enabled,
        serverNames: serverNames,
        listen: listen,
        upstream: upstream,
        https: https,
      ),
    );
  }
  sites.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return sites;
}

List<String> _splitTokens(String raw) {
  return raw
      .split(RegExp(r'\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && s != ';')
      .toList();
}
