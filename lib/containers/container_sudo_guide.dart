import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'package:maid_kit/theme.dart';

/// The sudoers drop-in the container grants live in — the file the daemon's own
/// deployment documents name.
const containerSudoersFile = '/etc/sudoers.d/maidcafe-containers';

/// Process name of the daemon whose account a grant has to name.
const maidCafeDaemonProcess = 'maidcafe-daemon';

/// Which refusal the daemon's message is: the standalone compose tool that
/// updates a stack, or the runtime binary that pulls an image.
enum ContainerSudoGrantKind { composeTool, runtimeBinary }

/// A daemon refusal that names the `sudo -n` grant that would let the step run.
///
/// Both daemon refusals of this shape end with the same sentence — "grant it
/// (for example" followed by a rule line naming the account, the run-as user
/// and the command, "in a file under /etc/sudoers.d/)" — so both parse into the
/// same thing: the account the rule is for, the run-as account, and the command
/// it names.
class ContainerSudoGrant {
  const ContainerSudoGrant({
    required this.message,
    required this.kind,
    required this.exampleAccount,
    required this.runAs,
    required this.commands,
    this.project,
    this.store,
  });

  /// The daemon's refusal, verbatim (its `StateError` prefix stripped).
  final String message;

  final ContainerSudoGrantKind kind;

  /// The account the daemon printed as its example. Only a fallback: the rule
  /// has to name the account the daemon actually runs under (see
  /// `SshConnectionManager.processAccount`).
  final String exampleAccount;

  /// Account the command runs as — `root` in both of the daemon's refusals.
  final String runAs;

  /// The command(s) the grant names, as the daemon printed them.
  final String commands;

  /// The compose project the step was for, when the message named one.
  final String? project;

  /// The store the daemon described, for example `podman in root's store`.
  final String? store;

  /// The sudoers line this grant is, for [account].
  String ruleFor(String account) => '$account ALL=($runAs) NOPASSWD: $commands';
}

/// Strips the prefix Dart puts on a thrown string (`Bad state: `), which says
/// which language threw and nothing an operator needs.
///
/// Public so the rule this guide installs and the words it shows an operator
/// are parsed from the same text.
String withoutDartPrefix(String message) => message
    .replaceFirst(
      RegExp(r'^(Bad state|ArgumentError|UnsupportedError):\s*'),
      '',
    )
    .trim();

/// Parses [error] into a [ContainerSudoGrant], or null when it is not one of
/// the daemon's "grant it" refusals.
ContainerSudoGrant? parseContainerSudoGrant(String error) {
  final message = withoutDartPrefix(error);
  // Both refusals name the probe that failed and the rule that would pass it.
  if (!message.contains('sudo -n')) return null;
  final example = RegExp(
    r'grant it \(for example `([^`]+)` in a file under /etc/sudoers\.d/\)',
  ).firstMatch(message)?.group(1);
  if (example == null) return null;
  final spec = RegExp(
    r'^(\S+)\s+ALL=\(([^)]*)\)\s+NOPASSWD:\s*(.+)$',
  ).firstMatch(example.trim());
  if (spec == null) return null;
  return ContainerSudoGrant(
    message: message,
    kind: message.contains('compose tool')
        ? ContainerSudoGrantKind.composeTool
        : ContainerSudoGrantKind.runtimeBinary,
    exampleAccount: spec.group(1)!,
    runAs: spec.group(2)!.trim(),
    commands: spec.group(3)!.trim(),
    project: RegExp(r'project "([^"]+)"').firstMatch(message)?.group(1),
    store: RegExp(r'lives in (.+?), and ').firstMatch(message)?.group(1),
  );
}

/// The POSIX script that adds [grant]'s rule to [file] and validates it.
///
/// Safe to run twice and safe next to a file this app did not write: the
/// existing content is kept, the rule is appended only when it is absent, and
/// `visudo` has to accept the result before anything is installed. Written for
/// `sh -s` under root, which is how `runPrivilegedScriptSnippet` supplies it.
String buildContainerSudoGrantScript({
  required ContainerSudoGrant grant,
  required String account,
  String file = containerSudoersFile,
}) {
  final rule = _shellSingleQuote(grant.ruleFor(account));
  return '''
set -eu
file=${_shellSingleQuote(file)}
command -v visudo >/dev/null 2>&1 || {
  echo "visudo is required to validate a sudoers rule." >&2
  exit 1
}
tmp=\$(mktemp "\${TMPDIR:-/tmp}/maidkit-containers.XXXXXX") || exit 1
trap 'rm -f "\$tmp"' EXIT
if [ -f "\$file" ]; then cat "\$file" > "\$tmp"; fi
grep -qxF -e $rule "\$tmp" 2>/dev/null || printf '%s\\n' $rule >> "\$tmp"
visudo -cf "\$tmp" >/dev/null 2>&1 || {
  echo "visudo rejected the rule; nothing was installed." >&2
  exit 1
}
install -o root -g root -m 0440 "\$tmp" "\$file"
echo "Installed the rule in \$file"
''';
}

/// The same script as a command an operator can paste, `sudo sh -s` and all —
/// what the install button runs, in the form that runs it by hand.
String containerSudoGrantCommand({
  required ContainerSudoGrant grant,
  required String account,
  String file = containerSudoersFile,
}) =>
    "sudo sh -s <<'EOF'\n"
    '${buildContainerSudoGrantScript(grant: grant, account: account, file: file)}'
    'EOF\n';

/// Reports a failed container or compose operation.
///
/// The daemon's refusals are paragraphs, and a snackbar cannot be read,
/// scrolled or copied from. So a refusal that names the `sudo -n` grant that
/// would fix it opens the guide, and any other failure long enough to be
/// truncated by a snackbar opens the same sheet with just its words — a
/// project that exists in two stores is a paragraph an operator has to act on,
/// not a line to read as it slides away.
Future<void> reportContainerSudoFailure({
  required BuildContext context,
  required WidgetRef ref,
  required Server server,
  required Object error,
  required String snackBarTitle,
  Future<void> Function()? onRetry,
}) async {
  if (!context.mounted) return;
  final message = withoutDartPrefix('$error');
  final grant = parseContainerSudoGrant(message);
  if (grant == null) {
    if (message.trim().length < _verboseFailureLength) {
      showStyledSnackBar(
        title: snackBarTitle,
        message: message,
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) =>
          _ContainerFailureSheet(title: snackBarTitle, message: message),
    );
    return;
  }
  await showContainerSudoGuideSheet(
    context: context,
    ref: ref,
    server: server,
    grant: grant,
    onRetry: onRetry,
  );
}

/// How long a failure has to be before a snackbar truncates it.
const _verboseFailureLength = 160;

/// Copies [value] and says so, the way every block in the sheets here does.
Future<void> _copyToClipboard(
  BuildContext context,
  String value,
  String label,
) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  showStyledSnackBar(
    title: label,
    message: 'commonCopiedToClipboard'.tr(),
    icon: Symbols.content_copy,
    accentColor: Theme.of(context).colorScheme.primary,
  );
}

/// A failure long enough that a snackbar would truncate it, with somewhere to
/// read and copy it from.
class _ContainerFailureSheet extends StatelessWidget {
  const _ContainerFailureSheet({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SheetScaffold(
      titleText: title,
      heightFactor: 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: SelectableText(message, style: theme.textTheme.bodyMedium),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => _copyToClipboard(context, message, title),
                  icon: const Icon(Symbols.content_copy, size: 16),
                  label: Text('commonCopy'.tr()),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('commonClose'.tr()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the guide for [grant] and, when the operator asks for it, installs the
/// rule on [server] over SSH and retries the step that was refused.
///
/// Returns true when the rule was installed.
Future<bool> showContainerSudoGuideSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Server server,
  required ContainerSudoGrant grant,
  Future<void> Function()? onRetry,
}) async {
  final request = await showModalBottomSheet<_SudoInstallRequest>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (_) => _ContainerSudoGuideSheet(server: server, grant: grant),
  );
  if (request == null || !context.mounted) return false;
  try {
    await installContainerSudoGrant(
      ref: ref,
      server: server,
      grant: grant,
      account: request.account,
    );
  } catch (error) {
    if (context.mounted) {
      showStyledSnackBar(
        title: 'containerSudoGuideInstallFailed'.tr(),
        message: '$error',
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
    return false;
  }
  if (context.mounted) {
    showStyledSnackBar(
      title: 'containerSudoGuideInstalled'.tr(),
      message: server.name,
      icon: Symbols.check_circle,
      accentColor: Theme.of(context).colorScheme.primary,
    );
  }
  // The retry is the verification: the daemon re-runs its own probe, so a rule
  // that does not reach the daemon shows up as the same refusal, not as a
  // green tick this client invented.
  if (onRetry != null && context.mounted) await onRetry();
  return true;
}

/// Writes the grant on [server] through the shared task terminal.
Future<void> installContainerSudoGrant({
  required WidgetRef ref,
  required Server server,
  required ContainerSudoGrant grant,
  required String account,
}) async {
  final credential = await ref
      .read(serverRepositoryProvider)
      .credentialFor(server);
  final sudoPassword = credential.type == CredentialType.password
      ? credential.password
      : null;
  final manager = ref.read(connectionManagerProvider);
  await runWithDeployTerminal(
    ref: ref,
    title: 'containerSudoGuideInstall'.tr(args: [server.name]),
    subtitle: containerSudoersFile,
    command: 'sudo sh -s',
    run: (onOutput) => manager.runPrivilegedScriptSnippet(
      server.id,
      script: buildContainerSudoGrantScript(grant: grant, account: account),
      sshUserIsRoot: server.username == 'root',
      sudoPassword: sudoPassword,
      onOutput: onOutput,
    ),
  );
}

/// What the sheet hands back when the operator asks for the install: the
/// account the rule must name, resolved while the sheet was open.
class _SudoInstallRequest {
  const _SudoInstallRequest(this.account);

  final String account;
}

class _ContainerSudoGuideSheet extends ConsumerStatefulWidget {
  const _ContainerSudoGuideSheet({required this.server, required this.grant});

  final Server server;
  final ContainerSudoGrant grant;

  @override
  ConsumerState<_ContainerSudoGuideSheet> createState() =>
      _ContainerSudoGuideSheetState();
}

class _ContainerSudoGuideSheetState
    extends ConsumerState<_ContainerSudoGuideSheet> {
  /// Whether this build can install anything: a browser has no SSH, and a
  /// server that is not connected has nowhere to run the script.
  var _canInstall = false;
  var _probing = false;

  /// The account the daemon runs under on this host, when it could be read.
  String? _account;

  @override
  void initState() {
    super.initState();
    _canInstall =
        !kIsWeb &&
        ref.read(connectionManagerProvider).clientFor(widget.server.id) != null;
    if (_canInstall) {
      _probing = true;
      unawaited(_probeAccount());
    }
  }

  Future<void> _probeAccount() async {
    String? account;
    try {
      account = await ref
          .read(connectionManagerProvider)
          .processAccount(widget.server.id, maidCafeDaemonProcess);
    } catch (_) {
      // An unreadable process list is not a failure of the guide: the rule
      // still installs, it just names the account the daemon printed.
      account = null;
    }
    if (mounted) {
      setState(() {
        _account = account;
        _probing = false;
      });
    }
  }

  /// The account to write the rule for. The running daemon is the authority;
  /// the daemon's printed example is the fallback.
  String get _ruleAccount {
    final probed = _account;
    return probed == null || probed.isEmpty
        ? widget.grant.exampleAccount
        : probed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final grant = widget.grant;
    final account = _ruleAccount;
    final rule = grant.ruleFor(account);
    final command = containerSudoGrantCommand(grant: grant, account: account);
    final where = [
      if (grant.project != null) grant.project!,
      if (grant.store != null) grant.store!,
    ].join(' · ');
    return SheetScaffold(
      titleText: 'containerSudoGuideTitle'.tr(),
      heightFactor: 0.86,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'containerSudoGuideIntro'.tr(args: [widget.server.name]),
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (where.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      where,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _GuideCodeBlock(
                    label: 'containerSudoGuideRuleLabel'.tr(),
                    value: rule,
                    maxHeight: 80,
                    onCopy: () => _copyToClipboard(
                      context,
                      rule,
                      'containerSudoGuideRuleLabel'.tr(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'containerSudoGuideCaution'.tr(args: [grant.commands]),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _GuideCodeBlock(
                    label: 'containerSudoGuideScriptLabel'.tr(),
                    value: command,
                    maxHeight: 200,
                    onCopy: () => _copyToClipboard(
                      context,
                      command,
                      'containerSudoGuideScriptLabel'.tr(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _accountLine(theme),
                  const SizedBox(height: 16),
                  _GuideCodeBlock(
                    label: 'containerSudoGuideMessageLabel'.tr(),
                    value: grant.message,
                    maxHeight: 160,
                    onCopy: () => _copyToClipboard(
                      context,
                      grant.message,
                      'containerSudoGuideMessageLabel'.tr(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('commonClose'.tr()),
                ),
                FilledButton.icon(
                  onPressed: _canInstall
                      ? () =>
                            Navigator.pop(context, _SudoInstallRequest(account))
                      : null,
                  icon: const Icon(Symbols.verified_user),
                  label: Text(
                    'containerSudoGuideInstall'.tr(args: [widget.server.name]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountLine(ThemeData theme) {
    final scheme = theme.colorScheme;
    final String text;
    final Color color;
    if (_probing) {
      text = 'containerSudoGuideAccountProbing'.tr();
      color = scheme.onSurfaceVariant;
    } else if (_account != null && _account!.isNotEmpty) {
      text = 'containerSudoGuideAccount'.tr(args: [_account!]);
      color = scheme.onSurfaceVariant;
    } else {
      text = _canInstall
          ? 'containerSudoGuideAccountUnknown'.tr(
              args: [widget.grant.exampleAccount],
            )
          : 'containerSudoGuideNoSsh'.tr();
      color = _canInstall ? scheme.error : scheme.onSurfaceVariant;
    }
    return Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color));
  }
}

/// A labelled, selectable, copyable block of shell text.
class _GuideCodeBlock extends StatelessWidget {
  const _GuideCodeBlock({
    required this.label,
    required this.value,
    required this.onCopy,
    required this.maxHeight,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              tooltip: 'commonCopy'.tr(),
              visualDensity: VisualDensity.compact,
              onPressed: onCopy,
              icon: const Icon(Symbols.content_copy, size: 16),
            ),
          ],
        ),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: MaidKitFonts.mono,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// POSIX-safe single-quoted string, the form the SSH manager uses.
String _shellSingleQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";
