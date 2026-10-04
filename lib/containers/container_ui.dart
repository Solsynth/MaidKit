import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/theme.dart';

import 'container_models.dart';

/// The container and image surfaces are one system, so they share it here.
///
/// Two rules hold the whole thing together:
///
/// * **One surface level.** A group is a card; the rows in it sit on that card
///   with hairline rules between them. Nothing is boxed inside a box.
/// * **Mono is the machine talking.** Image references, host paths, container
///   states, counts and the store a runtime keeps — anything the host printed —
///   is set in IBM Plex Mono. Names, labels and buttons stay in the UI face.
///   It reads like `--format` output on purpose: that is what an operator
///   trusts, and it is the one line a row needs for all of its metadata.
///
/// The one thing worth remembering: the transport stamp, which says who
/// answered the list — the MaidCafe daemon (streaming) or the SSH poller (on a
/// cadence) — because that decides what this client can actually do.

/// Which transport answered a container or image list.
enum ContainerListSource { daemon, ssh }

/// The toolbar both lists share: what the list holds, which transport answered
/// it, and the actions that work on the whole list rather than one row.
class ContainerListToolbar extends StatelessWidget {
  const ContainerListToolbar({
    super.key,
    required this.summary,
    required this.source,
    this.pollInterval,
    this.actions = const [],
  });

  /// Already-localized counts, joined with ` · `.
  final List<String> summary;

  final ContainerListSource source;

  /// The cadence the SSH poller refreshes on. Unused by the daemon source.
  final Duration? pollInterval;

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  summary.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ContainerSourceStamp(source: source, pollInterval: pollInterval),
              const SizedBox(width: 8),
              ...actions,
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
      ],
    );
  }
}

/// The transport stamp: a dot and a mono token naming who answered the list.
///
/// The dot is the only colour in the chrome — `primary` while the daemon
/// streams, muted while the SSH connection polls — so the state of the
/// connection is visible without reading anything.
class ContainerSourceStamp extends StatelessWidget {
  const ContainerSourceStamp({
    super.key,
    required this.source,
    this.pollInterval,
  });

  final ContainerListSource source;
  final Duration? pollInterval;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final live = source == ContainerListSource.daemon;
    final interval = pollInterval;
    final label = live
        ? 'containerListSourceDaemon'.tr()
        : interval == null
        ? 'containerListSourceSsh'.tr()
        : 'containerListSourceSshEvery'.tr(
            args: [formatContainerCadence(interval)],
          );
    return Tooltip(
      message: 'containerListSourceTooltip'.tr(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: live ? scheme.primary : scheme.onSurfaceVariant,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: containerMono(
              theme,
              size: 11,
            ).copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// A section heading and how many containers it holds.
class ContainerSectionLabel extends StatelessWidget {
  const ContainerSectionLabel({super.key, required this.label, this.count});

  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = this.count;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: containerMono(
                theme,
                size: 11,
              ).copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// One group of rows: an identity line, the facts about it in mono, and the
/// rows themselves on the same surface.
///
/// A compose project and a runtime/store environment are the same object to a
/// reader — a set of containers with a name, a place, and things you can do to
/// the whole set — so they are built from this one widget and read as siblings
/// rather than as two different inventions.
class ContainerGroup extends StatelessWidget {
  const ContainerGroup({
    super.key,
    required this.title,
    this.titleTrailing,
    required this.spec,
    this.actions = const [],
    required this.children,
    this.initiallyExpanded = true,
  });

  /// The group's name, in the UI face.
  final String title;

  /// Right-aligned text on the identity line — a compose project's directory.
  /// Machine text, so mono, and the first thing to ellipsize.
  final String? titleTrailing;

  /// The mono facts about the group.
  final List<String> spec;

  /// Actions that apply to the whole group, at the end of the identity line.
  final List<Widget> actions;

  /// The rows. A hairline is drawn between them; single-child bodies (an empty
  /// or failed environment) get none.
  final List<Widget> children;

  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final trailing = titleTrailing;
    final body = <Widget>[
      if (children.isNotEmpty)
        Divider(height: 1, color: containerRowRule(scheme)),
      for (var i = 0; i < children.length; i++) ...[
        children[i],
        if (i != children.length - 1)
          Divider(height: 1, color: containerRowRule(scheme)),
      ],
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: containerCardColor(scheme),
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Theme(
          // The expansion divider is drawn by the theme, and this card already
          // has a border and rules of its own.
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
            childrenPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            shape: const Border(),
            collapsedShape: const Border(),
            title: Row(
              children: [
                // The title takes a fixed share so every group's second column
                // (a compose directory) starts at the same x: aligned columns
                // are what make a list scannable instead of ragged.
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (trailing != null && trailing.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  Flexible(
                    flex: 3,
                    child: Tooltip(
                      message: trailing,
                      child: Text(
                        trailing,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: containerMono(
                          theme,
                        ).copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: ContainerSpecLine(spec),
            ),
            trailing: actions.isEmpty
                ? null
                : Row(mainAxisSize: MainAxisSize.min, children: actions),
            children: body,
          ),
        ),
      ),
    );
  }
}

/// A line of machine facts, separated by ` · ` — the one place a row's
/// metadata lives.
class ContainerSpecLine extends StatelessWidget {
  const ContainerSpecLine(this.parts, {super.key});

  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: containerMono(
        theme,
      ).copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

/// A group with no rows: what is true instead — nothing running, or nothing
/// readable.
class ContainerGroupNote extends StatelessWidget {
  const ContainerGroupNote(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // An ExpansionTile body lays a single child out centred, which would put
    // this note in the middle of the card; a full-width box keeps it with the
    // rows it replaces.
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// The group cards with a 12px gap between them, and nothing after the last.
List<Widget> spacedContainerGroups(List<Widget> groups) => [
  for (var i = 0; i < groups.length; i++) ...[
    groups[i],
    if (i != groups.length - 1) const SizedBox(height: 12),
  ],
];

/// The empty, not-installed and failed states, in one place so the container
/// and image lists cannot drift apart.
class ContainerEmptyPanel extends StatelessWidget {
  const ContainerEmptyPanel({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.filledAction = false,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final IconData? actionIcon;
  final bool filledAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              if (filledAction)
                FilledButton.icon(
                  onPressed: onAction,
                  icon: Icon(actionIcon ?? Symbols.refresh),
                  label: Text(actionLabel!),
                )
              else
                OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The mono face for machine facts, at the sizes this surface uses.
TextStyle containerMono(ThemeData theme, {double size = 12}) => theme
    .textTheme
    .bodySmall!
    .copyWith(fontFamily: MaidKitFonts.mono, fontSize: size, height: 1.3);

/// The fill of a group card: a step up from the panel the list sits in, quiet
/// enough that a list of ten groups is not ten boxes shouting.
Color containerCardColor(ColorScheme scheme) =>
    scheme.surfaceContainerHighest.withValues(alpha: 0.4);

/// The rule between rows inside a group: present, never loud.
Color containerRowRule(ColorScheme scheme) =>
    scheme.outlineVariant.withValues(alpha: 0.5);

/// The store a runtime keeps its containers in, named the way the daemon names
/// it: root's store, or the daemon account's own.
String containerStoreLabel(ContainerScope scope) => scope == ContainerScope.root
    ? 'containersStoreRoot'.tr()
    : 'containersStoreDaemon'.tr();

/// A cadence a person can read in a toolbar: `15s`, `2m`, `1h`.
String formatContainerCadence(Duration interval) {
  if (interval.inSeconds < 60) return '${interval.inSeconds}s';
  if (interval.inMinutes < 60) return '${interval.inMinutes}m';
  return '${interval.inHours}h';
}
