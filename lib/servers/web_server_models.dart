/// Lifecycle actions for a detected web server service (nginx, caddy, …).
enum WebServerAction { start, stop, restart, reload, enable, disable }

extension WebServerActionX on WebServerAction {
  String get trLabel => switch (this) {
    WebServerAction.start => 'webServerStart',
    WebServerAction.stop => 'webServerStop',
    WebServerAction.restart => 'webServerRestart',
    WebServerAction.reload => 'webServerReload',
    WebServerAction.enable => 'webServerEnable',
    WebServerAction.disable => 'webServerDisable',
  };

  String get trPastLabel => switch (this) {
    WebServerAction.start => 'webServerStarted',
    WebServerAction.stop => 'webServerStopped',
    WebServerAction.restart => 'webServerRestarted',
    WebServerAction.reload => 'webServerReloaded',
    WebServerAction.enable => 'webServerEnabled',
    WebServerAction.disable => 'webServerDisabled',
  };

  /// English verb for task logs / deploy terminal titles.
  String get englishLabel => switch (this) {
    WebServerAction.start => 'Start',
    WebServerAction.stop => 'Stop',
    WebServerAction.restart => 'Restart',
    WebServerAction.reload => 'Reload',
    WebServerAction.enable => 'Enable',
    WebServerAction.disable => 'Disable',
  };

  String get systemctlVerb => name;

  bool get isDestructive =>
      this == WebServerAction.stop || this == WebServerAction.disable;

  bool get requiresRunning =>
      this == WebServerAction.stop ||
      this == WebServerAction.restart ||
      this == WebServerAction.reload;

  bool get requiresStopped => this == WebServerAction.start;
}

/// One virtual host / site block discovered by a web server adapter.
class WebServerSite {
  const WebServerSite({
    required this.id,
    required this.name,
    required this.path,
    this.enabled = true,
    this.serverNames = const [],
    this.listen = const [],
    this.kind = WebServerSiteKind.site,
    this.upstream,
    this.https = false,
  });

  /// Adapter-stable id (usually the absolute config path).
  final String id;
  final String name;

  /// Absolute path of the site config file (or main config for inline sites).
  final String path;
  final bool enabled;
  final List<String> serverNames;
  final List<String> listen;
  final WebServerSiteKind kind;

  /// Where the site forwards to (`reverse_proxy` / `proxy_pass` target), when
  /// the config declares one. What a reader scanning routes cares about.
  final String? upstream;

  /// Whether the site terminates TLS. A bare hostname in a Caddyfile does;
  /// a plain `:80` listener or a non-ssl nginx site does not.
  final bool https;

  String get displayNames {
    if (serverNames.isNotEmpty) return serverNames.join(' ');
    if (listen.isNotEmpty) return listen.join(' ');
    return name;
  }

  /// The first hostname the site answers on, for opening it in a browser.
  String? get primaryHost {
    for (final name in serverNames) {
      if (name.contains('{')) continue;
      final host = name
          .replaceFirst(RegExp(r'^https?://'), '')
          .split(',')
          .first
          .trim();
      if (host.isEmpty || host.startsWith(':')) continue;
      if (host.contains('.') || host.contains(':')) return host;
    }
    return null;
  }
}

enum WebServerSiteKind { site, include, main }

/// Snapshot of a single web server installation on a host.
class WebServerStatus {
  const WebServerStatus({
    required this.adapterId,
    required this.label,
    required this.installed,
    this.binaryPath,
    this.version,
    this.serviceUnit,
    this.running = false,
    this.enabled = false,
    this.configPath,
    this.configValid,
    this.configMessage,
    this.sites = const [],
    this.error,
  });

  final String adapterId;
  final String label;
  final bool installed;
  final String? binaryPath;
  final String? version;
  final String? serviceUnit;
  final bool running;
  final bool enabled;
  final String? configPath;
  final bool? configValid;
  final String? configMessage;
  final List<WebServerSite> sites;
  final String? error;

  WebServerStatus copyWith({
    bool? running,
    bool? enabled,
    bool? configValid,
    String? configMessage,
    List<WebServerSite>? sites,
    String? error,
  }) => WebServerStatus(
    adapterId: adapterId,
    label: label,
    installed: installed,
    binaryPath: binaryPath,
    version: version,
    serviceUnit: serviceUnit,
    running: running ?? this.running,
    enabled: enabled ?? this.enabled,
    configPath: configPath,
    configValid: configValid ?? this.configValid,
    configMessage: configMessage ?? this.configMessage,
    sites: sites ?? this.sites,
    error: error,
  );
}

/// Lightweight detection result used when scanning a host for web servers.
class WebServerDetection {
  const WebServerDetection({
    required this.adapterId,
    required this.label,
    required this.installed,
    this.version,
    this.running = false,
  });

  final String adapterId;
  final String label;
  final bool installed;
  final String? version;
  final bool running;
}

/// How far to go when saving a config from the editor.
enum WebServerApplyMode {
  /// Write the file only.
  saveOnly,

  /// Write, then run the adapter's config check.
  saveAndValidate,

  /// Write, validate, then reload the service when the check passes.
  saveValidateReload,
}

/// One step inside a multi-step web server task (save / check / reload…).
class WebServerTaskStep {
  const WebServerTaskStep({
    required this.id,
    required this.label,
    required this.success,
    this.detail,
  });

  final String id;
  final String label;
  final bool success;

  /// Short human-readable detail (first error line, “syntax ok”, …).
  final String? detail;
}

/// Outcome of a web server management task for clear success/failure UI.
class WebServerTaskResult {
  const WebServerTaskResult({
    required this.success,
    required this.title,
    required this.summary,
    this.steps = const [],
    this.detail,
  });

  final bool success;

  /// Short title, e.g. "Validate Nginx".
  final String title;

  /// One-line user summary shown in the status banner (no need to open logs).
  final String summary;

  final List<WebServerTaskStep> steps;

  /// Full combined command output when useful.
  final String? detail;

  WebServerTaskStep? get failedStep {
    for (final step in steps) {
      if (!step.success) return step;
    }
    return null;
  }
}

/// Maximum config size the in-app editor will open or save (matches file manager).
const int webServerMaxEditableBytes = 1024 * 1024;
