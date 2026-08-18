import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/terminal_branding.dart';

void main() {
  group('detectRemoteShellDialect', () {
    test('detects fish and fish variants', () {
      expect(
        detectRemoteShellDialect('/usr/bin/fish'),
        RemoteShellDialect.fish,
      );
      expect(
        detectRemoteShellDialect('/opt/homebrew/bin/fish'),
        RemoteShellDialect.fish,
      );
    });

    test('detects csh-family, nushell, PowerShell, and cmd', () {
      expect(detectRemoteShellDialect('/bin/tcsh'), RemoteShellDialect.csh);
      expect(
        detectRemoteShellDialect('/usr/bin/nu'),
        RemoteShellDialect.nushell,
      );
      expect(
        detectRemoteShellDialect('C:\\Program Files\\PowerShell\\pwsh.exe'),
        RemoteShellDialect.powershell,
      );
      expect(
        detectRemoteShellDialect('C:\\Windows\\System32\\cmd.exe'),
        RemoteShellDialect.cmd,
      );
    });

    test('uses POSIX syntax for common and unknown shells', () {
      expect(detectRemoteShellDialect('/bin/bash'), RemoteShellDialect.posix);
      expect(detectRemoteShellDialect('/bin/zsh'), RemoteShellDialect.posix);
      expect(
        detectRemoteShellDialect('/bin/unknown-shell'),
        RemoteShellDialect.posix,
      );
    });
  });

  group('terminalBrandingCommand', () {
    test('uses fish assignment and unset syntax', () {
      expect(
        terminalBrandingCommand(RemoteShellDialect.fish),
        'set -gx TERM_PROGRAM MaidKit; set -e SSH_CONNECTION SSH_TTY\n',
      );
    });

    test('uses POSIX export and unset syntax', () {
      expect(
        terminalBrandingCommand(RemoteShellDialect.posix),
        'export TERM_PROGRAM=MaidKit; unset SSH_CONNECTION SSH_TTY\n',
      );
    });

    test('supports Windows shell environment syntax', () {
      expect(
        terminalBrandingCommand(RemoteShellDialect.powershell),
        contains(r'$env:TERM_PROGRAM = '),
      );
      expect(
        terminalBrandingCommand(RemoteShellDialect.cmd),
        contains('set "TERM_PROGRAM=MaidKit"'),
      );
    });
  });
}
