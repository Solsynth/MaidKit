import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:maid_kit/shared/presentation/app_context_menu.dart';

import 'maidcafe_metoer.dart';
import 'maidcafe_service.dart';
import 'server_providers.dart';

/// Cloud notification feed for a single workspace.
///
/// Follows Solian's feed (lib/notifications/notification.dart and
/// notification_tile.dart): one row per notification with a topic icon, a
/// title, an optional subtitle and body, and a quiet topic · daemon · age
/// footer. The list is lazy, so a long history only builds the rows that are
/// on screen.
///
/// The host is a desktop tab rather than a modal, so the feed actions live in
/// one compact bar above the list instead of a toolbar: refresh stays a real
/// button (hover-only chrome is unreachable from the keyboard), unread
/// filtering is a chip, and the bulk action only appears while something is
/// unread. The cloud caps a page at 100 rows, so older rows are pulled on
/// demand through the "before" cursor instead of being silently dropped.
class MaidCafeNotificationsTab extends ConsumerStatefulWidget {
  const MaidCafeNotificationsTab({super.key, required this.workspaceId});

  /// Workspace whose feed is shown; null while none is selected.
  final String? workspaceId;

  @override
  ConsumerState<MaidCafeNotificationsTab> createState() =>
      _MaidCafeNotificationsTabState();
}

class _MaidCafeNotificationsTabState
    extends ConsumerState<MaidCafeNotificationsTab> {
  /// Rows the cloud returns per request. A full page means older rows may
  /// still be behind the "before" cursor.
  static const _pageSize = 100;

  bool _unreadOnly = false;
  bool _refreshing = false;
  bool _markingAll = false;
  bool _loadingOlder = false;

  /// Set once a cursor page comes back short, which means the history ended.
  bool _exhausted = false;

  /// Rows fetched through the cursor, appended behind the provider's page.
  List<MaidCafeNotification> _older = const [];

  @override
  void didUpdateWidget(MaidCafeNotificationsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The tail belongs to the workspace it was fetched for; carrying it into
    // another workspace's feed would show rows the user cannot see there.
    if (oldWidget.workspaceId != widget.workspaceId) {
      _older = const [];
      _exhausted = false;
      _loadingOlder = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspaceId = widget.workspaceId;
    if (workspaceId == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('maidCafeNoWorkspaces'.tr()),
            ),
          ),
        ],
      );
    }

    final notifications = ref.watch(maidCafeNotificationsProvider(workspaceId));
    final unread = ref
        .watch(maidCafeUnreadNotificationCountProvider(workspaceId))
        .asData
        ?.value;
    final topics =
        ref
            .watch(maidCafeNotificationTopicsProvider(workspaceId))
            .asData
            ?.value ??
        const <MaidCafeNotificationTopic>[];
    final topicLabels = {
      for (final topic in topics) topic.topic: topic.description,
    };
    // A replaced first page (poll tick, push, mark-read, pull-to-refresh)
    // supersedes the cursor-loaded tail; keeping both would double rows.
    ref.listen(maidCafeNotificationsProvider(workspaceId), (previous, next) {
      if (_pageSignature(previous?.asData?.value) ==
          _pageSignature(next.asData?.value)) {
        return;
      }
      if (_older.isEmpty && !_exhausted) return;
      setState(() {
        _older = const [];
        _exhausted = false;
      });
    });

    final firstPage =
        notifications.asData?.value ?? const <MaidCafeNotification>[];
    final items = [...firstPage, ..._older];
    final visible = _unreadOnly
        ? items.where((item) => item.unread).toList(growable: false)
        : items;
    final hasMore = firstPage.length >= _pageSize && !_exhausted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Reserved so the progress line never shifts the bar.
        SizedBox(
          height: 2,
          child: _refreshing
              ? const LinearProgressIndicator(minHeight: 2)
              : null,
        ),
        _actionBar(unread),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: _feedSlivers(
                notifications: notifications,
                visible: visible,
                hasMore: hasMore,
                topicLabels: topicLabels,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _feedSlivers({
    required AsyncValue<List<MaidCafeNotification>> notifications,
    required List<MaidCafeNotification> visible,
    required bool hasMore,
    required Map<String, String> topicLabels,
  }) {
    return notifications.when<List<Widget>>(
      skipLoadingOnRefresh: true,
      loading: () => const [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 32),
          sliver: SliverToBoxAdapter(child: _NotificationSkeletonList()),
        ),
      ],
      error: (error, _) => [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          sliver: SliverToBoxAdapter(
            child: _NotificationErrorCard(error: error, onRetry: _refresh),
          ),
        ),
      ],
      data: (_) => [
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _NotificationsEmpty(unreadOnly: _unreadOnly),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(top: 8, left: 24, right: 24),
            sliver: SliverList.separated(
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final item = visible[index];
                return _NotificationTile(
                  key: ValueKey(item.id),
                  notification: item,
                  topicLabel: topicLabels[item.kind],
                  onMarkRead: () => _markRead(item),
                );
              },
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, indent: 64, endIndent: 16),
            ),
          ),
        if (hasMore || _loadingOlder)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Center(
                child: _loadingOlder
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton.icon(
                        key: const ValueKey(
                          'maidcafe-notifications-load-older',
                        ),
                        onPressed: _loadOlder,
                        icon: const Icon(Symbols.expand_more, size: 18),
                        label: Text('maidCafeLoadOlder'.tr()),
                      ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: hasMore || _loadingOlder ? 24 : 32),
        ),
      ],
    );
  }

  /// Refresh, unread filter, and the bulk read action, on one quiet row.
  Widget _actionBar(int? unread) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Narrow windows keep the actions and drop their labels.
              final showCount = constraints.maxWidth >= 560;
              final labelled = constraints.maxWidth >= 440;
              return Row(
                children: [
                  FilterChip(
                    selected: _unreadOnly,
                    avatar: const Icon(Symbols.mark_email_unread, size: 18),
                    label: Text('maidCafeUnreadOnly'.tr()),
                    onSelected: (selected) =>
                        setState(() => _unreadOnly = selected),
                  ),
                  if (showCount && unread != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      'maidCafeUnreadCount'.tr(args: ['$unread']),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (unread != null && unread > 0)
                    labelled
                        ? TextButton.icon(
                            onPressed: _markingAll ? null : _markAllRead,
                            icon: const Icon(Symbols.done_all, size: 18),
                            label: Text('maidCafeMarkAllRead'.tr()),
                          )
                        : IconButton(
                            tooltip: 'maidCafeMarkAllRead'.tr(),
                            onPressed: _markingAll ? null : _markAllRead,
                            icon: const Icon(Symbols.done_all, size: 20),
                          ),
                  IconButton(
                    key: const ValueKey('maidcafe-notifications-refresh'),
                    tooltip: 'maidCafeRefresh'.tr(),
                    onPressed: _refreshing ? null : _refresh,
                    icon: _refreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Symbols.refresh, size: 20),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String? _pageSignature(List<MaidCafeNotification>? items) {
    if (items == null) return null;
    if (items.isEmpty) return '0';
    return '${items.length}:${items.first.id}:${items.last.id}';
  }

  Future<void> _refresh() async {
    final workspaceId = widget.workspaceId;
    if (workspaceId == null || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      await Future.wait([
        ref.refresh(maidCafeNotificationsProvider(workspaceId).future),
        ref.refresh(
          maidCafeUnreadNotificationCountProvider(workspaceId).future,
        ),
        ref.refresh(maidCafeNotificationTopicsProvider(workspaceId).future),
      ]);
      if (!mounted) return;
      setState(() {
        _older = const [];
        _exhausted = false;
      });
    } catch (_) {
      // Failures surface through the feed's error card.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// Pulls the page behind the oldest loaded row.
  Future<void> _loadOlder() async {
    final workspaceId = widget.workspaceId;
    if (workspaceId == null || _loadingOlder) return;
    final loaded = [
      ...?ref.read(maidCafeNotificationsProvider(workspaceId)).asData?.value,
      ..._older,
    ];
    if (loaded.isEmpty) return;
    setState(() => _loadingOlder = true);
    try {
      final page = await ref
          .read(maidCafeServiceProvider)
          .listNotifications(
            workspaceId: workspaceId,
            limit: _pageSize,
            before: loaded.last.createdAt,
          );
      if (!mounted) return;
      final known = loaded.map((item) => item.id).toSet();
      setState(() {
        _older = [..._older, ...page.where((item) => !known.contains(item.id))];
        _exhausted = page.length < _pageSize;
        _loadingOlder = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingOlder = false);
      showSnackBar(_errorMessage(error));
    }
  }

  Future<void> _markRead(MaidCafeNotification item) async {
    final workspaceId = widget.workspaceId;
    if (workspaceId == null || !item.unread) return;
    try {
      await ref.read(maidCafeServiceProvider).markNotificationRead(item.id);
    } catch (error) {
      showSnackBar(_errorMessage(error));
      return;
    }
    _invalidateFeed(workspaceId);
  }

  Future<void> _markAllRead() async {
    final workspaceId = widget.workspaceId;
    if (workspaceId == null || _markingAll) return;
    setState(() => _markingAll = true);
    try {
      await ref
          .read(maidCafeServiceProvider)
          .markAllNotificationsRead(workspaceId: workspaceId);
      _invalidateFeed(workspaceId);
    } catch (error) {
      showSnackBar(_errorMessage(error));
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  void _invalidateFeed(String workspaceId) {
    ref.invalidate(maidCafeNotificationsProvider(workspaceId));
    ref.invalidate(maidCafeUnreadNotificationCountProvider(workspaceId));
  }
}

/// One row of the feed. Tapping an unread row marks it read; the same action
/// sits on the row's context menu so it also works without a primary click.
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    super.key,
    required this.notification,
    required this.topicLabel,
    required this.onMarkRead,
  });

  final MaidCafeNotification notification;
  final String? topicLabel;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final unread = notification.unread;
    final daemonName = notification.metadata['daemon_name']?.toString();
    final label = topicLabel ?? _humanizeTopic(notification.kind);
    final title = notification.title.trim().isNotEmpty
        ? notification.title.trim()
        : label;
    final createdAt = notification.createdAt.toLocal();
    final meta = [
      label,
      if (daemonName != null && daemonName.isNotEmpty)
        'maidCafeFromServer'.tr(args: [daemonName]),
    ];

    return AppContextMenuRegion(
      enabled: unread,
      menuBuilder: () => Menu(
        children: [
          MenuAction(
            title: 'maidCafeNotificationMarkRead'.tr(),
            image: MenuImage.icon(Symbols.mark_email_read),
            callback: onMarkRead,
          ),
        ],
      ),
      child: InkWell(
        onTap: unread ? onMarkRead : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: unread
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _notificationIcon(notification.kind),
                  size: 20,
                  color: unread
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: unread ? FontWeight.w600 : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Tooltip(
                          message: DateFormat(
                            'yyyy-MM-dd HH:mm',
                          ).format(createdAt),
                          child: Text(
                            _relativeTime(createdAt),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (notification.subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        notification.subtitle.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (notification.body.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        notification.body.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      meta.join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationSkeletonList extends StatelessWidget {
  const _NotificationSkeletonList();

  @override
  Widget build(BuildContext context) => Skeletonizer(
    enabled: true,
    child: Column(
      children: [
        for (var i = 0; i < 5; i++) ...[
          const _NotificationSkeletonTile(),
          if (i < 4) const Divider(height: 1, indent: 80, endIndent: 16),
        ],
      ],
    ),
  );
}

class _NotificationSkeletonTile extends StatelessWidget {
  const _NotificationSkeletonTile();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 36, height: 36, child: Icon(Symbols.notifications)),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Notification title'),
              SizedBox(height: 6),
              Text('A notification subtitle for this daemon'),
              SizedBox(height: 4),
              Text('Notification details and activity summary'),
              SizedBox(height: 6),
              Text('daemon.notification · From host-1'),
            ],
          ),
        ),
      ],
    ),
  );
}

class _NotificationsEmpty extends StatelessWidget {
  const _NotificationsEmpty({required this.unreadOnly});

  final bool unreadOnly;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              unreadOnly ? Symbols.mark_email_read : Symbols.notifications_none,
              size: 32,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'maidCafeNoNotifications'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationErrorCard extends StatelessWidget {
  const _NotificationErrorCard({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(child: Text(_errorMessage(error))),
          TextButton(onPressed: onRetry, child: Text('maidCafeRetry'.tr())),
        ],
      ),
    ),
  );
}

/// Icon for a notification kind, keyed off the topics the cloud publishes
/// (daemon.alarm.*, daemon.disconnected, webhook.*, user.request, ...).
IconData _notificationIcon(String kind) {
  final topic = kind.toLowerCase();
  if (topic.contains('alarm')) return Symbols.notification_important;
  if (topic.contains('disconnect')) return Symbols.cloud_off;
  if (topic.contains('reconnect')) return Symbols.cloud_done;
  if (topic.contains('fail') || topic.contains('error')) return Symbols.error;
  if (topic.contains('success') || topic.contains('completed')) {
    return Symbols.check_circle;
  }
  if (topic.contains('request')) return Symbols.person_alert;
  if (topic.contains('test')) return Symbols.science;
  if (topic.contains('container')) return Symbols.deployed_code;
  if (topic.contains('job') || topic.contains('cron')) return Symbols.schedule;
  if (topic.contains('webhook')) return Symbols.webhook;
  return Symbols.notifications;
}

/// Falls back to the cloud's own topic spelling when the topics list has not
/// loaded yet: daemon.alarm.disk_used_percent becomes Daemon Alarm Disk Used
/// Percent.
String _humanizeTopic(String topic) {
  final words = topic
      .split(RegExp(r'[._-]+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return 'maidCafeNotifications'.tr();
  return words
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
}

/// Compact age label. Reuses the agent feed's strings so wording stays
/// consistent app-wide; rows older than a week fall back to a date.
String _relativeTime(DateTime time) {
  final local = time.toLocal();
  final difference = DateTime.now().difference(local);
  if (difference.inMinutes < 1) return 'agentJustNow'.tr();
  if (difference.inHours < 1) {
    return 'agentMinutesAgo'.tr(args: ['${difference.inMinutes}']);
  }
  if (difference.inDays < 1) {
    return 'agentHoursAgo'.tr(args: ['${difference.inHours}']);
  }
  if (difference.inDays < 7) {
    return 'agentDaysAgo'.tr(args: ['${difference.inDays}']);
  }
  return DateFormat('yyyy-MM-dd').format(local);
}

String _errorMessage(Object error) => switch (error) {
  MaidCafeException(:final message) => message,
  MaidCafeMetoerException(:final message) => message,
  _ => error.toString(),
};
