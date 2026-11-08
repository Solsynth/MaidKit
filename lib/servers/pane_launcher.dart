import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/services/english_translations.dart';
import 'package:maid_kit/theme.dart';
import 'package:maid_kit/shared/presentation/search_field_suffix.dart';
import 'server_providers.dart';
import 'workspace_actions.dart';

/// What an empty pane shows: the workspace's command palette, inline.
///
/// An empty pane is not a dead end — it is one question, "what goes here?" —
/// so it is answered with the same searchable list the session-actions palette
/// uses, built from the same catalog: a terminal on any host, the file
/// manager, a server page, each assets page, projects, the agent chat, the cloud
/// console, settings and the dashboard. Picking an entry mounts it in this pane
/// when [paneId] names one, and opens a new workspace tab otherwise (the
/// no-tabs intro).
class PaneLauncher extends ConsumerStatefulWidget {
  const PaneLauncher({
    super.key,
    required this.paneId,
    this.compact = false,
    this.focused = false,
  });

  /// The empty pane to fill. Null for the whole-workspace intro, where a
  /// choice opens a tab of its own.
  final String? paneId;

  /// Sizes the block down for a split pane rather than the whole workspace.
  final bool compact;

  /// Whether this launcher's pane is the live one.
  ///
  /// A split leaves its new, empty pane live, and the one thing to do there is
  /// choose what goes into it, so a live launcher owns the keyboard. The claim
  /// waits for the frame that made the pane live: whatever closed just before
  /// — the command palette that ran the split — restores the keyboard to its
  /// previous owner on that frame, and the newer claim has to land after it.
  final bool focused;

  @override
  ConsumerState<PaneLauncher> createState() => _PaneLauncherState();
}

class _PaneLauncherState extends ConsumerState<PaneLauncher> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode(debugLabel: 'PaneLauncher search');
  final _rowKeys = <int, GlobalKey>{};
  var _query = '';
  var _highlighted = 0;

  @override
  void initState() {
    super.initState();
    // Arrow keys are answered on the field's own node: it is the first stop of
    // the key walk, ahead of every ancestor Shortcuts and of the text editing
    // bindings that would otherwise consume them as caret moves.
    _focusNode.onKeyEvent = workspaceActionKeyHandler(
      count: () => _entries.isEmpty ? 0 : _entries.length,
      highlighted: () => _highlighted,
      highlight: _highlight,
      run: (index) => _entries[index].run?.call(),
    );
    _claimKeyboard();
  }

  @override
  void didUpdateWidget(covariant PaneLauncher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focused && !oldWidget.focused) _claimKeyboard();
  }

  void _claimKeyboard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.focused || _focusNode.hasFocus) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// The rows the last frame built, which the key handler indexes.
  List<WorkspaceAction> _entries = const [];

  void _highlight(int index) {
    if (!mounted) return;
    setState(() => _highlighted = index);
    revealWorkspaceRow(_rowKeys[index]);
  }

  void _setQuery(String value) {
    final query = value.trim().toLowerCase();
    setState(() {
      _query = query;
      _highlighted = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final servers =
        ref.watch(serversProvider).asData?.value ?? const <Server>[];
    final hideAddresses = ref.watch(hideServerAddressesProvider);
    final english = EnglishLabels.labels;
    final query = _query.trim().toLowerCase();

    // A browser has no SSH socket: only a host it can reach through a daemon
    // offers a terminal there, so rows it cannot run drop out entirely.
    final entries = [
      for (final server in servers)
        ...serverActions(
          context: context,
          ref: ref,
          english: english,
          server: server,
          hideAddresses: hideAddresses,
          paneId: widget.paneId,
        ),
      ...workspaceDestinationActions(
        ref: ref,
        english: english,
        paneId: widget.paneId,
      ),
    ].where((entry) => entry.run != null && entry.matches(query)).toList();
    _entries = entries;
    if (_highlighted >= entries.length) _highlighted = 0;
    _rowKeys.removeWhere((index, _) => index >= entries.length);

    final padding = widget.compact ? 16.0 : 32.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - padding * 2).clamp(
          0.0,
          widget.compact ? 520.0 : 560.0,
        );
        return SingleChildScrollView(
          padding: EdgeInsets.all(padding),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - padding * 2).clamp(
                0.0,
                double.infinity,
              ),
            ),
            child: Center(
              child: SizedBox(
                width: width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!widget.compact) ...[
                      Text(
                        'sessionsSearchActions'.tr(),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _LauncherSearchField(
                      controller: _controller,
                      focusNode: _focusNode,
                      query: _query,
                      onChanged: _setQuery,
                      onClear: () {
                        _controller.clear();
                        _setQuery('');
                        _focusNode.requestFocus();
                      },
                    ),
                    const SizedBox(height: 8),
                    if (entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'serversNoMatches'.tr(),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      for (var index = 0; index < entries.length; index++)
                        _LauncherRow(
                          key: _rowKeys[index] ??= GlobalKey(),
                          entry: entries[index],
                          highlighted: index == _highlighted,
                          dense: widget.compact,
                          onTap: () => entries[index].run?.call(),
                          onHover: () => setState(() => _highlighted = index),
                        ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The launcher's search field.
///
/// The clear button is always laid out — only its visibility changes — so the
/// field keeps one height whether or not a query is typed. An icon button that
/// comes and goes changes the row's cross-axis extent and the band jumps; a
/// short field never does.
class _LauncherSearchField extends StatelessWidget {
  const _LauncherSearchField({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'sessionsSearchActions'.tr(),
        prefixIcon: const Icon(Symbols.search, size: 20),
        // The same fixed slot the command palette uses: showing the clear
        // button must not change the field's height, so it is always laid out.
        suffixIcon: SearchFieldSuffix(
          visible: query.isNotEmpty,
          onClear: onClear,
        ),
      ),
      onChanged: onChanged,
    );
  }
}

/// One launcher row: icon, name, optional target line.
class _LauncherRow extends StatelessWidget {
  const _LauncherRow({
    super.key,
    required this.entry,
    required this.highlighted,
    required this.dense,
    required this.onTap,
    required this.onHover,
  });

  final WorkspaceAction entry;
  final bool highlighted;
  final bool dense;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hint = entry.hint;
    return ListTile(
      dense: dense,
      selected: highlighted,
      selectedTileColor: scheme.secondaryContainer.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: MaidKitRadius.controlRadius),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(
        entry.icon,
        size: 20,
        color: highlighted ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(entry.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: hint == null
          ? null
          : Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
      onFocusChange: (focused) {
        if (focused) onHover();
      },
    );
  }
}
