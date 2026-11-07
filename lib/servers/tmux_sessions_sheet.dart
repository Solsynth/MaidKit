import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'maidcafe_stream.dart';
import 'tmux_sessions.dart';

/// Lists the tmux sessions [server]'s host still runs, so a terminal that
/// detached can be picked up again.
///
/// A session is listed with what it holds and whether anything is attached;
/// attaching opens it as a workspace tab, killing ends it after a confirmation.
Future<void> showTmuxSessionsSheet(
  BuildContext context,
  WidgetRef ref,
  Server server,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  useRootNavigator: true,
  builder: (_) => _TmuxSessionsSheet(server: server),
);

/// Asks which of the sessions [server]'s host already runs should be attached,
/// before a terminal opens and creates a new one.
///
/// [sessions] is what the host reported (see [attachableTmuxSessions]); it is
/// passed in rather than fetched again so the caller's listing is the one the
/// user is choosing from. Returns the chosen session name, `''` for "start a new
/// one", or null when the sheet was dismissed.
Future<String?> showTmuxAttachPicker(
  BuildContext context,
  Server server, {
  required String defaultName,
  required List<TmuxSessionInfo> sessions,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  useRootNavigator: true,
  builder: (_) => _TmuxAttachPicker(
    server: server,
    defaultName: defaultName,
    sessions: sessions,
  ),
);

class _TmuxAttachPicker extends StatelessWidget {
  const _TmuxAttachPicker({
    required this.server,
    required this.defaultName,
    required this.sessions,
  });

  final Server server;

  /// The name MaidKit itself uses on this host, so "start a new terminal" can
  /// say what it will actually be called.
  final String defaultName;

  /// Sessions the user started, newest first as the host listed them.
  final List<TmuxSessionInfo> sessions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SheetScaffold(
      titleText: 'sessionsTmuxAttachPickerTitle'.tr(args: [server.name]),
      onClose: () => Navigator.of(context).pop(),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          children: [
            ListTile(
              leading: Icon(Symbols.add, color: scheme.onSurfaceVariant),
              title: Text('sessionsTmuxAttachNew'.tr()),
              subtitle: Text(defaultName),
              onTap: () => Navigator.of(context).pop(''),
            ),
            const Divider(height: 1),
            for (final session in sessions)
              ListTile(
                leading: Icon(
                  session.attached > 0 ? Symbols.link : Symbols.inventory,
                  color: scheme.onSurfaceVariant,
                ),
                title: Text(session.name),
                subtitle: Text(
                  session.attached > 0
                      ? '${session.windows} \u00b7 ${session.attached}'
                      : '${session.windows}',
                ),
                onTap: () => Navigator.of(context).pop(session.name),
              ),
          ],
        ),
      ),
    );
  }
}

class _TmuxSessionsSheet extends ConsumerStatefulWidget {
  const _TmuxSessionsSheet({required this.server});

  final Server server;

  @override
  ConsumerState<_TmuxSessionsSheet> createState() => _TmuxSessionsSheetState();
}

class _TmuxSessionsSheetState extends ConsumerState<_TmuxSessionsSheet> {
  TmuxSessionListing? _listing;
  String? _error;
  var _loading = true;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await listTmuxSessionsFor(ref, widget.server);
      if (!mounted) return;
      setState(() {
        _listing = listing;
        _loading = false;
      });
    } on MaidCafeRouteMissingException {
      if (!mounted) return;
      setState(() {
        _error = 'sessionsTmuxUnsupportedDaemon'.tr();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _attach(TmuxSessionInfo session) async {
    setState(() => _busy = session.name);
    try {
      await attachTmuxSession(ref, widget.server, session.name);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = null);
      showStyledSnackBar(
        message: error.toString(),
        title: 'serverCannotOpenTerminal'.tr(),
        icon: Symbols.terminal,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  Future<void> _kill(TmuxSessionInfo session) async {
    final confirmed = await showMaidKitConfirmAlert(
      'sessionsTmuxKillConfirm'.tr(args: [session.name]),
      'sessionsTmuxKill'.tr(),
      isDanger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = session.name);
    try {
      await killTmuxSession(ref, widget.server, session.name);
      if (!mounted) return;
      setState(() => _busy = null);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = null);
      showStyledSnackBar(
        message: error.toString(),
        title: 'serverCannotOpenTerminal'.tr(),
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SheetScaffold(
      titleText: 'sessionsTmuxBackgroundTitle'.tr(args: [widget.server.name]),
      onClose: () => Navigator.of(context).pop(),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: _body(scheme),
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(error, style: TextStyle(color: scheme.error)),
      );
    }
    final listing = _listing;
    if (listing == null || !listing.tmuxInstalled) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('sessionsTmuxBackgroundUnavailable'.tr()),
      );
    }
    if (listing.sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('sessionsTmuxBackgroundEmpty'.tr()),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: listing.sessions.length,
      itemBuilder: (context, index) {
        final session = listing.sessions[index];
        final busy = _busy == session.name;
        return ListTile(
          leading: Icon(
            session.attached > 0 ? Symbols.link : Symbols.inventory,
            color: scheme.onSurfaceVariant,
          ),
          title: Text(session.name),
          subtitle: Text(
            session.attached > 0
                ? '${session.windows} · ${session.attached}'
                : '${session.windows}',
          ),
          trailing: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => _attach(session),
                      child: Text('sessionsTmuxAttach'.tr()),
                    ),
                    IconButton(
                      tooltip: 'sessionsTmuxKill'.tr(),
                      onPressed: () => _kill(session),
                      icon: const Icon(Symbols.delete_forever, size: 18),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
