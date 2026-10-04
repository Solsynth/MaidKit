import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:maid_kit/shared/presentation/maidkit_alert.dart';

import 'maidcafe_metoer.dart';
import 'maidcafe_service.dart';
import 'server_providers.dart';

/// Attention-modal id for the account notification feed, so asking for it
/// twice replaces the open modal instead of stacking another one.
const kNotificationsAttentionModalId = 'notifications';

/// Opens the signed-in account's MaidCafe notifications as an app-wide modal.
///
/// The feed is the one Metoer delivers push messages for, so the modal, the
/// unread badge, and a system notification all describe the same list.
Future<void> showNotificationsAttentionModal() {
  return showAttentionModal(
    id: kNotificationsAttentionModalId,
    replaceIfExists: true,
    barrierDismissible: true,
    builder: (context, dismiss) => NotificationModal(onDismiss: dismiss),
  );
}

/// The notification feed, rendered inside [AttentionModalScaffold].
class NotificationModal extends HookConsumerWidget {
  const NotificationModal({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fetching the feed marks the page viewed on the server, so both the list
    // and the badge have to be re-read on open rather than served from cache.
    useEffect(() {
      Future.microtask(() => _refreshFeeds(ref));
      return null;
    }, const []);

    final isMarkingAll = useState(false);
    final list = ref.watch(maidCafeMetoerNotificationsProvider);
    final scheme = Theme.of(context).colorScheme;

    Future<void> markAllRead() async {
      isMarkingAll.value = true;
      try {
        await ref.read(maidCafeMetoerClientProvider).markAllRead();
        _refreshFeeds(ref);
      } catch (error) {
        if (context.mounted) showMaidKitErrorAlert(error);
      } finally {
        if (context.mounted) isMarkingAll.value = false;
      }
    }

    Future<void> open(MaidCafeMetoerNotification notification) async {
      final uri = notification.meta['action_uri']?.toString() ?? '';
      if (!uri.startsWith('http://') && !uri.startsWith('https://')) return;
      await launchUrlString(uri);
      if (context.mounted) {
        dismissAttentionModal(kNotificationsAttentionModalId);
      }
    }

    return AttentionModalScaffold(
      titleText: 'maidCafeNotifications'.tr(),
      onDismiss: onDismiss,
      maxWidth: 560,
      actions: [
        IconButton(
          tooltip: 'maidCafeMarkAllRead'.tr(),
          onPressed: isMarkingAll.value ? null : markAllRead,
          icon: isMarkingAll.value
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                )
              : const Icon(Symbols.done_all),
        ),
        IconButton(
          tooltip: 'maidCafeRefresh'.tr(),
          onPressed: () => _refreshFeeds(ref),
          icon: const Icon(Symbols.refresh),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isMarkingAll.value)
            LinearProgressIndicator(minHeight: 2, color: scheme.primary),
          Expanded(
            child: list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _NotificationsError(
                error: error,
                onRetry: () => _refreshFeeds(ref),
              ),
              data: (items) => items.isEmpty
                  ? const _NotificationsEmpty()
                  : RefreshIndicator(
                      onRefresh: () async {
                        _refreshFeeds(ref);
                        await ref.read(
                          maidCafeMetoerNotificationsProvider.future,
                        );
                      },
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final notification = items[index];
                          return NotificationTile(
                            notification: notification,
                            onTap: () => open(notification),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Re-reads the feed and the badge together: they are two views of one list,
/// and every mutation (open, refresh, mark all read) changes both.
void _refreshFeeds(WidgetRef ref) {
  ref.invalidate(maidCafeMetoerNotificationsProvider);
  ref.invalidate(maidCafeMetoerUnreadCountProvider);
}

class _NotificationsEmpty extends StatelessWidget {
  const _NotificationsEmpty();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.notifications_none,
              size: 32,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'maidCafeNoNotifications'.tr(),
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsError extends StatelessWidget {
  const _NotificationsError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.error, size: 32, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              _errorMessage(error),
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.tonal(
              onPressed: onRetry,
              child: Text('maidCafeRetry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the feed. An unread row carries its dot and a stronger title so
/// the modal still reads as an inbox after the server has been marked read.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
  });

  final MaidCafeMetoerNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final unread = notification.unread;
    final title = notification.title?.trim() ?? '';
    final createdAt = notification.createdAt.toLocal();

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
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
                _notificationIcon(notification.topic),
                size: 20,
                color: unread
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title.isNotEmpty
                              ? title
                              : _humanizeTopic(notification.topic),
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
                          ),
                        ),
                      ),
                    ],
                  ),
                  // The title already is the topic when the cloud sent none, so
                  // the label only repeats it for notifications that have one.
                  if (title.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      _humanizeTopic(notification.topic),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (notification.subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      notification.subtitle.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (notification.body.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      notification.body.trim(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
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
    );
  }
}

/// The workspace's bell: the signed-in account's unread count, opening the
/// feed as an attention modal. Sized to sit beside the pane tab strip's other
/// icon buttons.
class NotificationsBellButton extends ConsumerWidget {
  const NotificationsBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(maidCafeMetoerUnreadCountProvider).value ?? 0;
    final label = unread > 99 ? '99+' : '$unread';

    return IconButton(
      tooltip: unread > 0
          ? 'maidCafeUnreadCount'.tr(args: [label])
          : 'maidCafeNotifications'.tr(),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      onPressed: showNotificationsAttentionModal,
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(label),
        child: Icon(
          unread > 0 ? Symbols.notifications_unread : Symbols.notifications,
          size: 20,
        ),
      ),
    );
  }
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

/// Falls back to the cloud's own topic spelling when the cloud sent no title:
/// daemon.alarm.disk_used_percent becomes Daemon Alarm Disk Used Percent.
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

/// The message a failed fetch shows, unwrapped from the transport exception
/// that carries it.
String _errorMessage(Object error) => switch (error) {
  MaidCafeException(:final message) => message,
  MaidCafeMetoerException(:final message) => message,
  _ => error.toString(),
};
