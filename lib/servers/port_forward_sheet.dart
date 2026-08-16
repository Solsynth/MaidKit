import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'port_forwarding_models.dart';
import 'server_providers.dart';

/// Status sheet for the active port forwards: one row per forward with a stop
/// action. Managed forwards (MaidCafe's own API connection) are locked.
Future<void> showPortForwardSheet(
  BuildContext context,
  List<ActivePortForward> forwards,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (sheetContext) => _PortForwardSheet(forwards: forwards),
);

class _PortForwardSheet extends ConsumerWidget {
  const _PortForwardSheet({required this.forwards});

  final List<ActivePortForward> forwards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return SheetScaffold(
      titleText: 'activePortForwards'.plural(forwards.length),
      heightFactor: 0.55,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          for (final forward in forwards)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                forward.isManaged ? Symbols.lock : Symbols.swap_horiz,
                color: forward.isManaged
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.onSurface,
              ),
              title: Text(forward.serverName),
              subtitle: Text(
                forward.isManaged
                    ? '${forward.summary}\n'
                          '${'portForwardingManagedByMaidCafe'.tr()}'
                    : forward.summary,
              ),
              trailing: forward.isManaged
                  ? null
                  : IconButton(
                      tooltip: 'portForwardingStop'.tr(),
                      onPressed: () {
                        ref
                            .read(connectionManagerProvider)
                            .stopPortForward(forward.id);
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Symbols.stop_circle),
                    ),
            ),
        ],
      ),
    );
  }
}
