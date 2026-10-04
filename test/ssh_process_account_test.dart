import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/servers/ssh_connection_manager.dart';

void main() {
  test('the account probe asks ps and answers with the account', () {
    final command = SshConnectionManager.processAccountCommand(
      'maidcafe-daemon',
    );

    expect(command, contains("name='maidcafe-daemon'"));
    // The process list is asked twice: by name first, then by command line,
    // because a daemon started with a full path is not always named the same
    // way. Either way the answer is a user name, not a uid.
    expect(command, contains('ps -eo pid=,comm='));
    expect(command, contains('ps -eo pid=,args='));
    expect(command, contains('id -nu'));
    // No process is an answer of its own ("nothing to name a rule for"), and
    // it must not be confused with a failed query.
    expect(command, contains('exit 3'));
  });

  test('a process name that could reach the shell is refused', () {
    for (final name in ["podman; id", 'a b', r'$HOME', 'podman|id', '']) {
      expect(
        () => SshConnectionManager.processAccountCommand(name),
        throwsArgumentError,
        reason: name,
      );
    }
  });
}
