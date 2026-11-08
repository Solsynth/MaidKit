import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/services/english_translations.dart';
import 'privacy_preferences.dart';
import 'server_connection_actions.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'terminal_tabs_provider.dart';

/// Where an entry belongs when the list is shown unfiltered.
///
/// The sections give a palette shape: what acts on the tab you are looking at,
/// what opens a server, and the workspace-wide destinations. A typed query
/// drops the headings so the matches read as one ranked list.
enum WorkspaceActionGroup { tab, servers, workspace }

/// One thing the workspace can open or do, from any surface that offers it.
///
/// The empty-pane launcher and the session-actions palette list the same
/// destinations, so both build them from this one catalog: an entry added or
/// renamed once shows up — with the same icon, label and English alias — in
/// both. [run] is null when this build cannot offer the entry; the row is then
/// left out rather than offered and refused.
class WorkspaceAction {
  const WorkspaceAction({
    required this.label,
    required this.icon,
    required this.group,
    this.run,
    this.aliases = const [],
    this.hint,
    this.shortcut,
  });

  final String label;
  final IconData icon;
  final WorkspaceActionGroup group;

  /// Null when the action is unavailable; such a row is dropped.
  final Future<void> Function()? run;

  /// Further text this entry answers to, beyond [label]: its English name and
  /// any older wording the same thing is known by.
  ///
  /// A user who switched the app to another language still recognizes the
  /// English name from a screenshot, a ticket or a colleague, so every locale
  /// keeps that name searchable.
  final List<String> aliases;

  /// A second line naming the target, e.g. a server's address.
  final String? hint;

  /// The chord that runs this action, printed on the row.
  final String? shortcut;

  /// Whether [query] — already trimmed and lower-cased — names this entry.
  bool matches(String query) {
    if (query.isEmpty) return true;
    if (label.toLowerCase().contains(query)) return true;
    if (hint?.toLowerCase().contains(query) ?? false) return true;
    return aliases.any((alias) => alias.toLowerCase().contains(query));
  }

  /// The same entry, filed under another section of the list.
  WorkspaceAction inGroup(WorkspaceActionGroup group) {
    return WorkspaceAction(
      label: label,
      icon: icon,
      group: group,
      run: run,
      aliases: aliases,
      hint: hint,
      shortcut: shortcut,
    );
  }
}

/// The destinations every surface that opens workspace tabs offers.
///
/// [paneId] mounts into that empty pane; null opens a workspace tab. [done]
/// runs after the destination is selected — the palette closes itself with it,
/// the launcher has nothing to close.
List<WorkspaceAction> workspaceDestinationActions({
  required WidgetRef ref,
  required Map<String, String> english,
  String? paneId,
  void Function()? done,
}) {
  final notifier = ref.read(terminalTabsProvider.notifier);

  WorkspaceAction destination({
    required String key,
    required IconData icon,
    required void Function() open,
    List<String> aliases = const [],
  }) {
    return WorkspaceAction(
      label: key.tr(),
      icon: icon,
      group: WorkspaceActionGroup.workspace,
      aliases: [?englishText(english, key), ...aliases],
      run: () async {
        open();
        done?.call();
      },
    );
  }

  return [
    destination(
      key: 'tabDashboard',
      icon: Symbols.dashboard,
      open: () => notifier.openDashboard(paneId: paneId),
    ),
    destination(
      key: 'assetsConnections',
      icon: Symbols.dns,
      open: () => notifier.openAssets(paneId: paneId),
    ),
    destination(
      key: 'assetsCredentialsTitle',
      icon: Symbols.key,
      open: () =>
          notifier.openAssets(section: AssetsSection.credentials, paneId: paneId),
    ),
    destination(
      key: 'tabSnippets',
      icon: Symbols.code,
      open: () =>
          notifier.openAssets(section: AssetsSection.snippets, paneId: paneId),
    ),
    destination(
      key: 'tabProjects',
      icon: Symbols.deployed_code,
      open: () => notifier.openProjects(paneId: paneId),
    ),
    // One entry for the agent: the chat is what opens, so it is named after the
    // tab it mounts, and the old "new conversation" wording stays searchable.
    destination(
      key: 'tabAgent',
      icon: Symbols.smart_toy,
      open: () => notifier.openAgentChat(paneId: paneId),
      aliases: [
        'agentNewConversation'.tr(),
        ?englishText(english, 'agentNewConversation'),
      ],
    ),
    destination(
      key: 'maidCafeCloudTitle',
      icon: Symbols.cloud,
      open: () => notifier.openMaidCafeCloud(paneId: paneId),
    ),
    destination(
      key: 'tabSettings',
      icon: Symbols.settings,
      open: () => notifier.openSettings(paneId: paneId),
    ),
  ];
}

/// What can be opened on one server: a terminal, its files, its page.
///
/// [context] is the surface offering the rows; it is still mounted when one is
/// run, and the terminal opener needs it to report or ask about a connection.
///
/// [group] files the rows; the palette's tab section takes the active server's
/// terminal and files there, since those act on the tab being looked at.
/// [includeFiles] and [includeDetails] let a surface skip a row it already
/// offers, so the same server is not listed twice for the same action.
List<WorkspaceAction> serverActions({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, String> english,
  required Server server,
  required bool hideAddresses,
  WorkspaceActionGroup group = WorkspaceActionGroup.servers,
  String? paneId,
  void Function()? done,
  bool includeTerminal = true,
  bool includeFiles = true,
  bool includeDetails = true,
}) {
  final notifier = ref.read(terminalTabsProvider.notifier);
  // A browser has no SSH socket: only a host it can reach through a daemon
  // offers a terminal there, the same rule the command palette applies.
  final reachable =
      !kIsWeb ||
      server.connectionType == ServerConnectionType.maidcafe.name ||
      server.hasMaidCafeTerminalRoute;
  final address = serverAddressLabel(server, hideAddresses: hideAddresses);

  Future<void> run(FutureOr<void> Function() action) async {
    await action();
    done?.call();
  }

  return [
    if (includeTerminal)
      WorkspaceAction(
        label: 'sessionsNewTerminalOn'.tr(args: [server.name]),
        icon: Symbols.terminal,
        group: group,
        hint: address,
        aliases: [
          server.name,
          ?englishText(english, 'sessionsNewTerminalOn', args: [server.name]),
        ],
        run: reachable
            ? () => run(
                () => openTerminalFor(context, ref, server, paneId: paneId),
              )
            : null,
      ),
    if (includeFiles)
      WorkspaceAction(
        label: 'sessionsOpenFileTransfer'.tr(args: [server.name]),
        icon: Symbols.folder,
        group: group,
        hint: address,
        aliases: [
          server.name,
          ?englishText(
            english,
            'sessionsOpenFileTransfer',
            args: [server.name],
          ),
        ],
        run: reachable
            ? () => run(() => openFilesOn(context, ref, server, paneId))
            : null,
      ),
    if (includeDetails)
      WorkspaceAction(
        label: '${'serversDetailedView'.tr()} · ${server.name}',
        icon: Symbols.dns,
        group: group,
        hint: address,
        aliases: [server.name, ?englishText(english, 'serversDetailedView')],
        run: () => run(() => notifier.openServerDetails(server, paneId: paneId)),
      ),
  ];
}

/// Mounts [server]'s file manager in [paneId], connecting first when a native
/// build has no session for it yet.
///
/// The file manager talks to the host over SFTP (or the daemon's file API in a
/// browser), so a native build needs the session up before it opens.
Future<void> openFilesOn(
  BuildContext context,
  WidgetRef ref,
  Server server,
  String? paneId,
) async {
  if (!kIsWeb) {
    final manager = ref.read(connectionManagerProvider);
    if (manager.clientFor(server.id) == null &&
        !await connectForStatistics(context, ref, server)) {
      return;
    }
    if (!context.mounted) return;
  }
  ref
      .read(terminalTabsProvider.notifier)
      .openFileManagement(server, paneId: paneId);
}

/// Moves a highlight by [delta] through [count] rows, wrapping at both ends.
int moveWorkspaceHighlight(int current, int delta, int count) {
  if (count == 0) return 0;
  return (current + delta) % count;
}

/// Scrolls the row behind [key] into view, if it is built.
void revealWorkspaceRow(GlobalKey? key) {
  final context = key?.currentContext;
  if (context == null || !context.mounted) return;
  Scrollable.ensureVisible(
    context,
    alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    duration: const Duration(milliseconds: 120),
    curve: Curves.easeOut,
  );
}

/// Keys a search field hands to the list under it.
///
/// The list's keyboard lives in its search field: there is no second focus
/// target to Tab to, and a pointer user never leaves the field either. A text
/// field's own node is the first stop of the key event walk — earlier than every
/// ancestor `Shortcuts` and than the text editing bindings — so this handler
/// belongs on that node, not on a wrapper that would only see keys the field
/// already consumed.
///
/// Up and down move the highlight, Enter runs it; everything else is left to
/// the field.
FocusOnKeyEventCallback workspaceActionKeyHandler({
  required int Function() count,
  required int Function() highlighted,
  required void Function(int index) highlight,
  required void Function(int index) run,
}) {
  return (node, event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final total = count();
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        if (total > 0) {
          highlight(moveWorkspaceHighlight(highlighted(), 1, total));
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        if (total > 0) {
          highlight(moveWorkspaceHighlight(highlighted(), -1, total));
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        if (total == 0) return KeyEventResult.ignored;
        run(highlighted().clamp(0, total - 1));
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  };
}
