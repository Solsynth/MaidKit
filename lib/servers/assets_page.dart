import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/github/github_section.dart';
import 'package:maid_kit/shared/presentation/app_scaffold.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';

import 'credentials_page.dart';
import 'maidcafe_settings_section.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'servers_page.dart';

/// A home for saved, reusable connection resources.
@RoutePage()
class AssetsPage extends StatelessWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context) => MaidKitAppScaffold(
    body: LayoutBuilder(
      builder: (context, constraints) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          const ServerAssetsSection(),
          const SizedBox(height: 32),
          const GitHubSection(),
          const SizedBox(height: 32),
          const CredentialsPage(),
          if (constraints.maxWidth <= 768) ...[
            const SizedBox(height: 32),
            const MaidCafeSettingsSection(),
          ],
        ],
      ),
    ),
  );
}

class ServerAssetsSection extends ConsumerWidget {
  const ServerAssetsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final header = Text(
              'assetsConnections'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            );
            final addButton = FilledButton.icon(
              onPressed: () => _add(context, ref),
              icon: const Icon(Symbols.add),
              label: Text('serversAddServer'.tr()),
            );
            return constraints.maxWidth < 600
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [header, const SizedBox(height: 8), addButton],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [header, addButton],
                  );
          },
        ),
        const SizedBox(height: 4),
        Text(
          'assetsConnectionsDescription'.tr(),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        servers.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) =>
              Text('serversLoadError'.tr(args: [error.toString()])),
          data: (items) => items.isEmpty
              ? Text(
                  'serversEmptyHint'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              : Column(
                  children: [
                    for (var index = 0; index < items.length; index++) ...[
                      _ServerAssetRow(
                        server: items[index],
                        onEdit: () => _edit(context, ref, items[index]),
                        onDelete: () => _delete(context, ref, items[index]),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(serverRepositoryProvider);
    final credentials = await repository.credentials();
    final snippets = await ref.read(snippetRepositoryProvider).all();
    final servers = await repository.all();
    if (!context.mounted) return;
    final draft = await showModalBottomSheet<ServerDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ServerEditorDialog(
        credentials: credentials,
        snippets: snippets,
        servers: servers,
      ),
    );
    if (draft == null) return;
    try {
      await ref.read(serverRepositoryProvider).create(draft);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Server server) async {
    try {
      final repository = ref.read(serverRepositoryProvider);
      final credential = server.credentialId == null
          ? null
          : await repository.credentialFor(server);
      final proxy = await repository.proxyFor(server);
      final credentials = await repository.credentials();
      final snippets = await ref.read(snippetRepositoryProvider).all();
      final servers = await repository.all();
      if (!context.mounted) return;
      final draft = await showModalBottomSheet<ServerDraft>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ServerEditorDialog(
          credentials: credentials,
          snippets: snippets,
          servers: servers,
          serverId: server.id,
          initial: ServerDraft(
            name: server.name,
            host: server.host,
            port: server.port,
            username: server.username,
            credential: credential,
            credentialId: server.credentialId,
            collectStats: server.collectStats,
            collectSystemInfo: server.collectSystemInfo,
            proxy: proxy,
            jumpHostServerId: server.jumpHostServerId,
            environment: decodeEnvironmentMap(server.environment),
            initialSnippets: decodeSnippetIdList(server.initialSnippets),
            tags: decodeStringList(server.tags),
            connectionType:
                ServerConnectionType.values
                    .asNameMap()[server.connectionType] ??
                ServerConnectionType.ssh,
            serialConfig: decodeSerialConfig(server.serialConfig),
          ),
        ),
      );
      if (draft != null) await repository.update(server, draft);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Server server,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('serversDeleteServer'.tr()),
        content: Text(server.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('commonCancel').tr(),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('commonDelete').tr(),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(serverRepositoryProvider).delete(server);
  }
}

class _ServerAssetRow extends ConsumerWidget {
  const _ServerAssetRow({
    required this.server,
    required this.onEdit,
    required this.onDelete,
  });

  final Server server;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideAddresses = ref.watch(hideServerAddressesProvider);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: const Icon(Symbols.dns),
      title: Text(server.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            hideAddresses
                ? server.username
                : '${server.host} · ${server.username} · ${server.port}',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _AssetTag(label: 'SSH'),
              if (server.collectStats)
                _AssetTag(label: 'assetsTagMetrics'.tr()),
              if (server.collectSystemInfo)
                _AssetTag(label: 'assetsTagSystemInfo'.tr()),
            ],
          ),
        ],
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'serversEditServer'.tr(),
            onPressed: onEdit,
            icon: const Icon(Symbols.edit),
          ),
          IconButton(
            tooltip: 'commonDelete'.tr(),
            onPressed: onDelete,
            icon: const Icon(Symbols.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _AssetTag extends StatelessWidget {
  const _AssetTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) =>
      Text(label, style: Theme.of(context).textTheme.labelSmall);
}

void _showError(BuildContext context, Object error) {
  showStyledSnackBar(message: '$error', icon: Symbols.error);
}
