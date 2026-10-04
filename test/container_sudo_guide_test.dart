import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/containers/container_sudo_guide.dart';

/// The daemon's own refusals, verbatim from `nativeOpRunner.composeAttempts`
/// and `runtimePullAttempts`.
const _composeRefusal =
    'Bad state: project "openlist" lives in podman in root\'s store, and the '
    'compose tool that runs there — /usr/local/bin/podman-compose — may not be '
    'run through `sudo -n` on this host; grant it (for example `maidcafe '
    'ALL=(root) NOPASSWD: /usr/local/bin/podman-compose` in a file under '
    '/etc/sudoers.d/) or run the step yourself as root';

const _pullRefusal =
    'Bad state: the container lives in podman in root\'s store, and `sudo -n` '
    'may not run /usr/bin/podman on this host; grant it (for example `maidcafe '
    'ALL=(root) NOPASSWD: /usr/bin/podman` in a file under /etc/sudoers.d/) or '
    'pull the image yourself';

void main() {
  test('a compose refusal parses into the rule it names', () {
    final grant = parseContainerSudoGrant(_composeRefusal)!;

    expect(grant.kind, ContainerSudoGrantKind.composeTool);
    expect(grant.exampleAccount, 'maidcafe');
    expect(grant.runAs, 'root');
    expect(grant.commands, '/usr/local/bin/podman-compose');
    expect(grant.project, 'openlist');
    expect(grant.store, "podman in root's store");
    // The StateError prefix belongs to Dart, not to the daemon's words.
    expect(grant.message, isNot(contains('Bad state')));
    expect(grant.message, startsWith('project "openlist"'));
    expect(
      grant.ruleFor('deploy'),
      'deploy ALL=(root) NOPASSWD: /usr/local/bin/podman-compose',
    );
  });

  test('a pull refusal parses into the runtime binary it names', () {
    final grant = parseContainerSudoGrant(_pullRefusal)!;

    expect(grant.kind, ContainerSudoGrantKind.runtimeBinary);
    expect(grant.commands, '/usr/bin/podman');
    expect(grant.project, isNull);
    expect(grant.store, "podman in root's store");
  });

  test('anything that is not a grant refusal stays a snackbar', () {
    expect(parseContainerSudoGrant('connection closed'), isNull);
    // A sudo mention without the rule the daemon prints is not actionable.
    expect(
      parseContainerSudoGrant('sudo -n failed for /usr/bin/podman'),
      isNull,
    );
    expect(
      parseContainerSudoGrant(
        'project "alpha" is not a stack this daemon manages',
      ),
      isNull,
    );
  });

  test('the install script appends the rule and validates before writing', () {
    final grant = parseContainerSudoGrant(_composeRefusal)!;
    final script = buildContainerSudoGrantScript(
      grant: grant,
      account: 'maidcafe',
      file: '/tmp/maidkit-sudoers-test',
    );

    // The existing file is read, not replaced: the runtime grant that lets the
    // daemon see root's store at all must survive this rule being added.
    expect(script, contains(r'if [ -f "$file" ]; then cat "$file" > "$tmp"'));
    expect(
      script,
      contains(
        r'grep -qxF -e '
        r"""'maidcafe ALL=(root) NOPASSWD: /usr/local/bin/podman-compose'"""
        r' "$tmp"',
      ),
    );
    expect(script, contains(r"printf '%s\n'"));
    // Nothing is installed until a rule the host accepts is in hand.
    expect(script, contains(r'visudo -cf "$tmp"'));
    expect(script, contains(r'install -o root -g root -m 0440 "$tmp" "$file"'));
    expect(script, contains("file='/tmp/maidkit-sudoers-test'"));
  });

  test('the copyable command is the same script under sudo', () {
    final grant = parseContainerSudoGrant(_pullRefusal)!;
    final command = containerSudoGrantCommand(grant: grant, account: 'deploy');

    expect(command, startsWith("sudo sh -s <<'EOF'\n"));
    expect(command, endsWith('EOF\n'));
    expect(command, contains("deploy ALL=(root) NOPASSWD: /usr/bin/podman"));
    expect(
      command,
      contains(buildContainerSudoGrantScript(grant: grant, account: 'deploy')),
    );
  });
}
