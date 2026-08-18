/// Shell dialects supported by the terminal branding command.
enum RemoteShellDialect { posix, fish, csh, powershell, cmd, nushell }

/// Infers a shell dialect from a login shell executable path.
RemoteShellDialect detectRemoteShellDialect(String shellPath) {
  final executable = shellPath
      .trim()
      .replaceAll('\\', '/')
      .split('/')
      .last
      .toLowerCase();
  final withoutExtension = executable.endsWith('.exe')
      ? executable.substring(0, executable.length - 4)
      : executable;
  return switch (withoutExtension) {
    'fish' => RemoteShellDialect.fish,
    'csh' || 'tcsh' => RemoteShellDialect.csh,
    'nu' => RemoteShellDialect.nushell,
    'pwsh' || 'powershell' => RemoteShellDialect.powershell,
    'cmd' => RemoteShellDialect.cmd,
    _ => RemoteShellDialect.posix,
  };
}

/// Builds the command that brands the current interactive shell as MaidKit.
///
/// SSH connection variables are removed because terminal information tools
/// otherwise report the SSH transport instead of the terminal application.
String terminalBrandingCommand(RemoteShellDialect dialect) => switch (dialect) {
  RemoteShellDialect.fish =>
    'set -gx TERM_PROGRAM MaidKit; set -e SSH_CONNECTION SSH_TTY\n',
  RemoteShellDialect.csh =>
    'setenv TERM_PROGRAM MaidKit; unsetenv SSH_CONNECTION SSH_TTY\n',
  RemoteShellDialect.nushell =>
    "\$env.TERM_PROGRAM = 'MaidKit'; hide-env SSH_CONNECTION; "
        'hide-env SSH_TTY\n',
  RemoteShellDialect.powershell =>
    "\$env:TERM_PROGRAM = 'MaidKit'; Remove-Item Env:SSH_CONNECTION,"
        'Env:SSH_TTY -ErrorAction SilentlyContinue\n',
  RemoteShellDialect.cmd =>
    'set "TERM_PROGRAM=MaidKit" & set "SSH_CONNECTION=" & '
        'set "SSH_TTY="\n',
  RemoteShellDialect.posix =>
    'export TERM_PROGRAM=MaidKit; unset SSH_CONNECTION SSH_TTY\n',
};
