import 'dart:convert';

/// One directory the MaidCafe daemon's file API may serve, and whether writing
/// inside it needs root.
///
/// The daemon keeps two allowlists that must agree for a privileged root: its
/// own `[[daemon.files.roots]]` entry, and a profile in the helper's
/// `/etc/maidkit/priv.toml`. Both are generated from this one declaration so an
/// operator cannot end up with a root the daemon will route to the helper but
/// the helper refuses, or the reverse.
class MaidCafeFileRoot {
  const MaidCafeFileRoot({
    required this.path,
    this.privileged = false,
    this.profile = '',
    this.modes = const ['0644', '0640'],
  });

  /// Absolute path on the host.
  final String path;

  /// Whether writes inside it go through the `maidkit-priv` helper as root.
  final bool privileged;

  /// The helper profile name authorizing a privileged root. Required when
  /// [privileged]; ignored otherwise.
  final String profile;

  /// The permission modes the helper may use in this root. Only the helper's
  /// supported set is allowed (`0600`, `0640`, `0644`, `0700`, `0750`, `0755`);
  /// the helper refuses anything else, so a value outside it is a configuration
  /// error rather than a silent downgrade.
  final List<String> modes;

  bool get isValid {
    if (path.trim().isEmpty || !path.startsWith('/')) return false;
    if (!privileged) return true;
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(profile)) return false;
    return modes.isNotEmpty && modes.every(_allowedModes.contains);
  }

  static const _allowedModes = {'0600', '0640', '0644', '0700', '0750', '0755'};
}

/// The package managers the privileged helper may be granted.
///
/// Homebrew is absent on purpose: it installs into a user-owned prefix and is
/// designed to run without root, so a grant for it would be a root grant that
/// buys nothing. A helper grant naming anything outside this set is refused by
/// the helper's own validation, not silently widened.
const maidCafeGrantablePackageManagers = <String>{
  'apt',
  'dnf',
  'yum',
  'pacman',
  'zypper',
  'apk',
  'xbps',
};

/// The verbs a package grant may name, matching the daemon's package API.
const maidCafeGrantablePackageVerbs = <String>{
  'refresh',
  'upgrade',
  'install',
  'remove',
};

/// The firewall backends the privileged helper may be granted. Nothing else is
/// a firewall the helper knows how to drive.
const maidCafeGrantableFirewallBackends = <String>{'ufw', 'firewalld'};

/// The verbs a firewall grant may name, matching the daemon's firewall API.
const maidCafeGrantableFirewallVerbs = <String>{
  'enable',
  'disable',
  'allow',
  'deny',
  'delete',
};

/// One package family the privileged helper may drive: the manager it runs and
/// the verbs it may use.
///
/// A package manager run as root is the largest grant in the helper's file —
/// a package's maintainer scripts run as root, so `install` executes code the
/// operator did not write — which is why the verbs are granted one at a time
/// and [manager] is fixed here rather than chosen per request.
class MaidCafePackageGrant {
  const MaidCafePackageGrant({required this.manager, required this.verbs});

  /// The manager the helper runs, e.g. `apt`. Never a caller-supplied binary.
  final String manager;

  /// The verbs the helper may pass to that manager, granted one at a time.
  final List<String> verbs;

  /// True when the helper's own validation accepts this grant. A manager
  /// outside [maidCafeGrantablePackageManagers] — `brew` above all — never is.
  bool get isValid =>
      maidCafeGrantablePackageManagers.contains(manager) &&
      verbs.isNotEmpty &&
      verbs.every(maidCafeGrantablePackageVerbs.contains);
}

/// One firewall family the privileged helper may drive, on the same terms as
/// [MaidCafePackageGrant]: the backend and the rule grammar are the helper's to
/// decide, so a caller never reaches a raw rule or another command.
class MaidCafeFirewallGrant {
  const MaidCafeFirewallGrant({required this.backend, required this.verbs});

  /// The backend the helper drives, e.g. `ufw`.
  final String backend;

  /// The verbs the helper may run, granted one at a time.
  final List<String> verbs;

  bool get isValid =>
      maidCafeGrantableFirewallBackends.contains(backend) &&
      verbs.isNotEmpty &&
      verbs.every(maidCafeGrantableFirewallVerbs.contains);
}

/// Renders the daemon's `[daemon.files]` table for [roots].
///
/// Every root is a table, never a bare path: a privileged root needs a profile
/// name beside it, and one shape for both kinds keeps this generator honest.
///
/// A null [roots] means the caller has no opinion — it does not model the file
/// API — and renders nothing; the install then carries an existing
/// `[daemon.files]` table over rather than dropping it. An empty list is an
/// explicit "serve nothing" and renders nothing either, but the privileged
/// helper's grant is revoked for it (see [buildMaidCafePrivScript]): the
/// difference between "I did not say" and "I said none" decides whether an
/// operator's own configuration survives an unrelated save.
String maidCafeFilesConfig(List<MaidCafeFileRoot>? roots) {
  final valid = roots?.where((root) => root.isValid).toList() ?? const [];
  if (valid.isEmpty) return '';
  final buffer = StringBuffer()
    ..writeln('[daemon.files]')
    ..writeln('enabled = true')
    // Writing is the interesting half of this feature, so it is on by default
    // here; a read-only root is an operator's deliberate choice, not the
    // default a generated config should make.
    ..writeln('allowWrite = true');
  for (final root in valid) {
    buffer
      ..writeln()
      ..writeln('[[daemon.files.roots]]')
      ..writeln('path = ${_toml(root.path)}');
    if (root.privileged) {
      buffer
        ..writeln('privileged = true')
        ..writeln('profile = ${_toml(root.profile)}');
    }
  }
  return buffer.toString();
}

/// The keys [maidCafeFilesConfig] writes. Any other key an operator has in
/// `[daemon.files]` — a read cap, a dedicated secret, a list cap — is not this
/// app's to drop, so the section rewrite keeps it.
const maidCafeGeneratedFilesKeys = {'enabled', 'allowwrite'};

/// Replaces the `[daemon.files]` section of [currentConfig] with [generated],
/// keeping every key the generator does not write.
///
/// The section is rewritten as a whole because its roots are an array of
/// tables, which a key-by-key patcher cannot address. That makes preserving the
/// rest of the section this function's job: without it, saving a root would
/// silently reset an operator's `maxReadBytes` or drop a dedicated `secret`.
///
/// Everything outside the section — the rest of the file, comments included —
/// is carried across untouched, and a file with no such section gains one at
/// the end.
String mergeMaidCafeFilesConfig(String currentConfig, String generated) {
  if (generated.isEmpty) return currentConfig;
  final lines = currentConfig.split('\n');
  final before = <String>[];
  final after = <String>[];
  final kept = <String>[];
  var inSection = false;
  var inTable = false;
  var found = false;
  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('[')) {
      // The section and its roots sub-tables; the table itself is what may
      // carry unmodelled keys.
      inSection =
          trimmed == '[daemon.files]' || trimmed.startsWith('[[daemon.files.');
      inTable = trimmed == '[daemon.files]';
      if (inSection) {
        found = true;
        continue;
      }
    }
    if (inSection) {
      if (!inTable) continue;
      final separator = trimmed.indexOf('=');
      if (separator <= 0) continue;
      final key = trimmed.substring(0, separator).trim().toLowerCase();
      if (maidCafeGeneratedFilesKeys.contains(key)) continue;
      kept.add(line);
      continue;
    }
    (found ? after : before).add(line);
  }

  final body = generated.split('\n');
  final insertAt = body.indexWhere((line) => line.startsWith('[['));
  final at = insertAt < 0 ? body.length : insertAt;
  final section = <String>[
    ...body.sublist(0, at),
    ...kept,
    if (kept.isNotEmpty) '',
    ...body.sublist(at),
  ];
  if (!found) {
    // No section to replace: the generated one goes at the end, separated from
    // whatever table the file ended with.
    final head = <String>[...before];
    while (head.isNotEmpty && head.last.trim().isEmpty) {
      head.removeLast();
    }
    return '${[...head, '', ...section].join('\n').trimRight()}\n';
  }
  return [...before, ...section, ...after].join('\n');
}

/// Renders the helper's profile file for the privileged [roots], plus the
/// host-wide grants the caller asked for.
///
/// Only privileged roots appear: an unprivileged root is served by the daemon's
/// own account and must not be reachable through the helper, which runs as
/// root. [packages] and [firewall] render a `[packages]`/`[firewall]` table
/// only when supplied, the same "I did not say" rule [maidCafeFilesConfig]
/// follows; a grant the helper would refuse is dropped rather than written as a
/// broken entry.
String maidCafePrivToml(
  List<MaidCafeFileRoot> roots, {
  MaidCafePackageGrant? packages,
  MaidCafeFirewallGrant? firewall,
}) {
  final privileged = roots
      .where((root) => root.privileged && root.isValid)
      .toList();
  final packageGrant = packages != null && packages.isValid ? packages : null;
  final firewallGrant = firewall != null && firewall.isValid ? firewall : null;
  if (privileged.isEmpty && packageGrant == null && firewallGrant == null) {
    return '';
  }
  final buffer = StringBuffer()
    ..writeln(
      '# Generated by MaidKit. This file is the authorization boundary for',
    )
    ..writeln(
      '# privileged operations: the sudoers rule authorizes the helper, and the',
    )
    ..writeln('# helper can only do what is named here. Keep it root-owned and')
    ..writeln(
      '# unwritable by anyone else — a file the daemon\'s own account could',
    )
    ..writeln('# rewrite would be a privilege grant it can edit.')
    ..writeln();
  for (final root in privileged) {
    buffer
      ..writeln('[[profiles]]')
      ..writeln('name = ${_toml(root.profile)}')
      ..writeln('path = ${_toml(root.path)}')
      ..writeln('modes = [${root.modes.map(_toml).join(', ')}]')
      ..writeln();
  }
  if (packageGrant != null) {
    buffer
      ..writeln(
        '# Package operations: one manager, with the verbs it may receive.',
      )
      ..writeln(
        '# The manager is named here so a caller can never choose the binary.',
      )
      ..writeln('[packages]')
      ..writeln('manager = ${_toml(packageGrant.manager)}')
      ..writeln('verbs = [${packageGrant.verbs.map(_toml).join(', ')}]')
      ..writeln();
  }
  if (firewallGrant != null) {
    buffer
      ..writeln(
        '# Firewall rules: the backend, and the verbs the helper may run.',
      )
      ..writeln('[firewall]')
      ..writeln('backend = ${_toml(firewallGrant.backend)}')
      ..writeln('verbs = [${firewallGrant.verbs.map(_toml).join(', ')}]')
      ..writeln();
  }
  return buffer.toString();
}

/// The daemon's `[daemon.priv]` table: where the privileged helper lives and
/// which operation families the daemon may route through it.
///
/// A family switched on makes the helper the only path for it: the helper's own
/// grant decides what it may do, and a refusal is an error rather than a
/// fallback to the blanket `sudo -n` an operator may also have. That is why each
/// family has its own switch instead of one "privileged" flag.
class MaidCafePrivSection {
  const MaidCafePrivSection({
    this.helper = '',
    this.systemd = false,
    this.packages = false,
    this.firewall = false,
  });

  /// The installed helper binary. Empty uses the daemon's compiled default;
  /// naming it does not grant anything on its own.
  final String helper;

  /// Route native systemd unit actions through the helper.
  final bool systemd;

  /// Route package operations through the helper.
  final bool packages;

  /// Route firewall operations through the helper, on the same terms.
  final bool firewall;
}

/// Renders the daemon's `[daemon.priv]` table for [section].
///
/// A null [section] means the caller has no opinion — it does not model the
/// helper's routing — and renders nothing; the install then carries an existing
/// table over rather than dropping an operator's routing decisions. The same
/// rule as [maidCafeFilesConfig], and for the same reason: an unread or
/// unmodelled section is never replaced with a default.
String maidCafePrivConfig(MaidCafePrivSection? section) {
  if (section == null) return '';
  final buffer = StringBuffer()..writeln('[daemon.priv]');
  if (section.helper.trim().isNotEmpty) {
    buffer.writeln('helper = ${_toml(section.helper.trim())}');
  }
  return (buffer
        ..writeln('systemd = ${section.systemd}')
        ..writeln('packages = ${section.packages}')
        ..writeln('firewall = ${section.firewall}'))
      .toString();
}

/// Reads the `[daemon.priv]` table of a daemon configuration, or null when the
/// configuration has none.
///
/// The daemon accepts the switches both inside `[daemon.priv]` and as dotted
/// keys (`daemon.priv.packages`), so both are understood, the way the terminal
/// settings are. Public so the parse can be unit-tested without a live daemon.
MaidCafePrivSection? parseMaidCafePrivConfig(String configText) {
  var found = false;
  var helper = '';
  var systemd = false;
  var packages = false;
  var firewall = false;
  var section = '';
  for (final line in configText.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    if (trimmed.startsWith('[')) {
      section = trimmed;
      if (section == '[daemon.priv]') found = true;
      continue;
    }
    final separator = trimmed.indexOf('=');
    if (separator <= 0) continue;
    var key = trimmed.substring(0, separator).trim().toLowerCase();
    if (key.startsWith('daemon.priv.')) {
      key = key.substring('daemon.priv.'.length);
    } else if (section != '[daemon.priv]') {
      continue;
    }
    found = true;
    final raw = trimmed.substring(separator + 1).trim();
    switch (key) {
      case 'helper':
        helper = _tomlUnquote(raw);
      case 'systemd':
        systemd = _filesTomlBool(raw) ?? false;
      case 'packages':
        packages = _filesTomlBool(raw) ?? false;
      case 'firewall':
        firewall = _filesTomlBool(raw) ?? false;
    }
  }
  if (!found) return null;
  return MaidCafePrivSection(
    helper: helper,
    systemd: systemd,
    packages: packages,
    firewall: firewall,
  );
}

/// Builds the privileged shell snippet that installs the `maidkit-priv` helper,
/// its profile file and the sudoers rule authorizing it.
///
/// Ordering is load-bearing, and this script is the authority on it: the helper,
/// the profiles and the rule are installed **before** the daemon configuration
/// that declares a privileged root, because the daemon validates that its
/// helper exists when it loads its configuration. The caller therefore runs this
/// before writing `config.toml`.
///
/// The sudoers rule is printed by the installed helper itself (`maidkit-priv
/// sudoers` with the account as its argument), so the rule and the helper's command surface cannot
/// drift apart, and `visudo` validates it before it is installed — the same
/// gate the run-as rule uses. With no privileged roots the rule and the profile
/// file are removed: a helper that can reach nothing is one thing, but a
/// standing sudoers grant is what should not survive.
///
/// [helperBase64] is the compiled helper's bytes. It is null when the caller has
/// no bundle for this platform (the helper ships with the daemon archive on
/// Linux and macOS); the script then keeps any installed helper and only
/// reconciles the profiles and the rule.
///
/// [packages] and [firewall] add the host-wide grants to the same file, so a
/// caller that declares either owns the whole file exactly as declaring file
/// roots does. An invalid grant throws rather than being dropped: the daemon
/// would otherwise route that family to a helper with no grant for it.
String buildMaidCafePrivScript(
  List<MaidCafeFileRoot>? roots, {
  required bool stdio,
  String? helperBase64,
  MaidCafePackageGrant? packages,
  MaidCafeFirewallGrant? firewall,
}) {
  final privileged =
      roots?.where((root) => root.privileged && root.isValid).toList() ??
      const <MaidCafeFileRoot>[];
  if (packages != null && !packages.isValid) {
    throw ArgumentError.value(
      packages.manager,
      'packages',
      'must name a grantable manager and at least one granted verb',
    );
  }
  if (firewall != null && !firewall.isValid) {
    throw ArgumentError.value(
      firewall.backend,
      'firewall',
      'must name a grantable backend and at least one granted verb',
    );
  }
  // The daemon runs as the SSH user in stdio mode; sudo sets SUDO_USER when the
  // install was elevated, so that is the account the rule must name. The
  // expression is evaluated by the install script, not written literally.
  final ruleUserExpr = stdio ? '"\${SUDO_USER:-\$(id -un)}"' : '"maidcafe"';
  const helperPath = '/usr/local/libexec/maidkit-priv';
  const configPath = '/etc/maidkit/priv.toml';

  // Installed through /dev/stdin, the same way action scripts are, so no
  // temporary file exists for another account to race.
  final installHelper = helperBase64 == null
      ? ''
      : "printf '%s' '$helperBase64' | base64 -d | "
            'install -o root -g root -m 0755 /dev/stdin $helperPath';

  // A caller that models none of the helper's grants says nothing about them,
  // and removing a grant this save did not create would revoke a feature the
  // operator configured. Only an explicit declaration does that.
  if (roots == null && packages == null && firewall == null) {
    if (helperBase64 == null) return '';
    return '''
install -d -o root -g root -m 0755 /usr/local/libexec
$installHelper''';
  }
  if (privileged.isEmpty && packages == null && firewall == null) {
    return '''
rm -f /etc/sudoers.d/maidkit-priv
rm -f $configPath''';
  }

  final encodedToml = base64Encode(
    utf8.encode(
      maidCafePrivToml(
        roots ?? const <MaidCafeFileRoot>[],
        packages: packages,
        firewall: firewall,
      ),
    ),
  );
  return '''
command -v visudo >/dev/null 2>&1 || {
  echo "Privileged operations require visudo (sudo) on the host." >&2
  exit 1
}
install -d -o root -g root -m 0755 /usr/local/libexec /etc/maidkit
$installHelper
if [ ! -x $helperPath ]; then
  echo "The privileged helper is not installed at $helperPath." >&2
  echo "Reinstall the daemon bundle to get maidkit-priv, or declare no privileged ${privileged.isEmpty ? 'operations' : 'roots'}." >&2
  exit 1
fi
printf '%s' '$encodedToml' | base64 -d | install -o root -g root -m 0644 /dev/stdin $configPath
# Refuse to install a grant file the helper cannot parse, so a typo here
# surfaces during the install rather than as a failed write later.
$helperPath --config $configPath fs profiles >/dev/null || {
  echo "The privileged helper rejected the generated grant file." >&2
  exit 1
}
rule_user=$ruleUserExpr
sudoers_tmp="\$(mktemp "\${TMPDIR:-/tmp}/maidkit-priv.XXXXXX")"
# The rule comes from the helper itself, so it always matches the verbs it
# implements.
"$helperPath" sudoers "\$rule_user" > "\$sudoers_tmp"
visudo -cf "\$sudoers_tmp" >/dev/null 2>&1 || {
  echo "MaidCafe rejected the privileged helper's sudoers rule; no changes were made." >&2
  rm -f "\$sudoers_tmp"
  exit 1
}
install -o root -g root -m 0440 "\$sudoers_tmp" /etc/sudoers.d/maidkit-priv
rm -f "\$sudoers_tmp"''';
}

/// Quotes a TOML basic string, escaping the characters TOML treats specially.
String _toml(String value) {
  final escaped = value
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');
  return '"$escaped"';
}

/// Reads the file roots a daemon's configuration declares.
///
/// Both shapes are understood, because both exist in the field: the current
/// `[[daemon.files.roots]]` array of tables, and the bare `roots = ["/srv"]`
/// list the first release wrote. The daemon itself still accepts the bare form,
/// so the editor has to show what such a host actually has rather than claiming
/// it has no roots.
List<MaidCafeFileRoot> parseMaidCafeFileRoots(String configText) {
  final roots = <MaidCafeFileRoot>[];
  var section = '';

  // One `[[daemon.files.roots]]` entry accumulates here until the next header.
  String? entryPath;
  var entryPrivileged = false;
  var entryProfile = '';
  final entryModes = <String>[];
  String? openListKey;
  final openList = StringBuffer();

  void commitEntry() {
    if (entryPath == null) return;
    roots.add(
      MaidCafeFileRoot(
        path: entryPath!,
        privileged: entryPrivileged,
        profile: entryProfile,
        modes: entryModes.isEmpty
            ? const ['0644', '0640']
            : List.of(entryModes),
      ),
    );
    entryPath = null;
    entryPrivileged = false;
    entryProfile = '';
    entryModes.clear();
  }

  void commitKey(String key, String raw) {
    switch (key) {
      case 'path':
        entryPath ??= _filesTomlString(raw);
      case 'privileged':
      case 'privilegedwrite':
        if (_filesTomlBool(raw) == true) entryPrivileged = true;
      case 'profile':
        final value = _filesTomlString(raw);
        if (value.isNotEmpty) entryProfile = value;
      case 'modes':
      case 'mode':
        if (entryModes.isEmpty) entryModes.addAll(_filesTomlStringList(raw));
    }
  }

  for (final line in configText.split('\n')) {
    final trimmed = line.trim();
    if (openListKey != null) {
      openList.write(' $trimmed');
      if (trimmed.contains(']')) {
        if (section == '[daemon.files]') {
          _commitBareRoots(openList.toString(), roots);
        } else {
          commitKey(openListKey, openList.toString());
        }
        openListKey = null;
        openList.clear();
      }
      continue;
    }
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    if (trimmed.startsWith('[')) {
      // A new header ends whatever the previous one was describing.
      if (section == '[[daemon.files.roots]]') commitEntry();
      section = trimmed;
      continue;
    }
    final separator = trimmed.indexOf('=');
    if (separator <= 0) continue;
    final key = trimmed.substring(0, separator).trim().toLowerCase();
    final value = trimmed.substring(separator + 1).trim();
    if (section == '[[daemon.files.roots]]') {
      if ((key == 'modes' || key == 'mode') &&
          value.startsWith('[') &&
          !value.contains(']')) {
        openListKey = key;
        openList
          ..clear()
          ..write(value);
        continue;
      }
      commitKey(key, value);
      continue;
    }
    if (section != '[daemon.files]') continue;
    if (key == 'roots' || key == 'root') {
      if (value.startsWith('[') && !value.contains(']')) {
        openListKey = key;
        openList
          ..clear()
          ..write(value);
        continue;
      }
      _commitBareRoots(value, roots);
    }
  }
  if (section == '[[daemon.files.roots]]') commitEntry();
  return roots;
}

/// Appends the bare `roots = ["/srv"]` entries, which predate per-root
/// privileges and mean an ordinary, unprivileged root.
void _commitBareRoots(String raw, List<MaidCafeFileRoot> roots) {
  for (final path in _filesTomlStringList(raw)) {
    roots.add(MaidCafeFileRoot(path: path));
  }
}

String _filesTomlString(String raw) => _tomlUnquote(raw);
List<String> _filesTomlStringList(String raw) => RegExp(
  r'"((?:[^"\\]|\\.)*)"',
).allMatches(raw).map((match) => match.group(1)!).toList();
bool? _filesTomlBool(String raw) => switch (_tomlUnquote(raw).toLowerCase()) {
  'true' => true,
  'false' => false,
  _ => null,
};

String _tomlUnquote(String raw) {
  final trimmed = raw.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed.split('#').first.trim();
}

/// Rewrites the `[daemon.files]` table of [currentConfig] to match [roots],
/// leaving every other table, key and comment byte-for-byte alone.
///
/// A null [roots] means the caller does not model file roots and the section is
/// left untouched, which is what keeps an operator's hand-written configuration
/// from being erased by an unrelated save. An empty list is an explicit
/// teardown and removes the section.
///
/// The section is replaced as a whole rather than key by key: its roots are an
/// array of tables, which a scalar patcher cannot address, and a section that is
/// rewritten entirely is one whose `[[daemon.files.roots]]` children cannot be
/// left behind next to a new set.
String patchMaidCafeFilesConfigText(
  String currentConfig,
  List<MaidCafeFileRoot>? roots,
) {
  if (roots == null) return currentConfig;
  final lines = currentConfig.split('\n');
  final kept = <String>[];
  var inFiles = false;
  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('[')) {
      // The section and everything belonging to it: the table itself and each
      // of its roots entries.
      inFiles =
          trimmed == '[daemon.files]' ||
          trimmed.startsWith('[[daemon.files.roots]]') ||
          trimmed.startsWith('[[daemon.files.');
      if (inFiles) continue;
    }
    if (inFiles) continue;
    kept.add(line);
  }
  final body = maidCafeFilesConfig(roots);
  if (body.isEmpty) {
    return _collapseBlankLines(kept.join('\n'));
  }
  // The generated section is a table, so it cannot live inside another one: a
  // `[daemon]` table that is still open when the file ends takes the appended
  // headers as part of it. Appending after a trailing blank keeps the file
  // readable either way.
  final text = kept.join('\n');
  final separator = text.endsWith('\n') ? '' : '\n';
  return _collapseBlankLines('$text$separator\n$body');
}

/// Drops runs of blank lines left behind by a removed section.
String _collapseBlankLines(String text) =>
    '${text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trimRight()}\n';
