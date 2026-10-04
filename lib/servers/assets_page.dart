import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/github/github_section.dart';
import 'package:maid_kit/shared/presentation/app_scaffold.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'package:maid_kit/shared/presentation/icon_label_tab.dart';
import 'package:maid_kit/snippets/snippet_confirmation.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';

import 'credentials_page.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'servers_page.dart';
import 'terminal_tabs_provider.dart';

/// A home for saved, reusable connection resources: server connections,
/// GitHub, credentials and snippets, each in its own tab. The primary
/// create action lives on a floating action button that adapts to the
/// active tab.
class AssetsPage extends ConsumerStatefulWidget {
  const AssetsPage({
    super.key,
    this.initialSection = AssetsSection.connections,
    this.onSectionChanged,
  });

  /// The page to show. Changing it switches the tab bar to that page, which is
  /// how the launcher opens ["GitHub"] or ["Snippets"] directly.
  final AssetsSection initialSection;

  /// Reports the page the user switched to, so the workspace tab can remember
  /// it.
  final ValueChanged<AssetsSection>? onSectionChanged;

  @override
  ConsumerState<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends ConsumerState<AssetsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: AssetsSection.values.length,
    vsync: this,
    initialIndex: widget.initialSection.index,
  )..addListener(_onTabChanged);

  @override
  void didUpdateWidget(AssetsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final section = widget.initialSection;
    if (section != oldWidget.initialSection &&
        _tabController.index != section.index) {
      _tabController.animateTo(section.index);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!mounted) return;
    setState(() {});
    // Report only a settled index; the listener also fires mid-animation.
    if (_tabController.indexIsChanging) return;
    widget.onSectionChanged?.call(AssetsSection.values[_tabController.index]);
  }

  @override
  Widget build(BuildContext context) {
    return MaidKitAppScaffold(
      body: DefaultTabController(
        length: AssetsSection.values.length,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              controller: _tabController,
              tabs: [
                IconLabelTab(
                  icon: const Icon(Symbols.dns, size: 18),
                  label: 'assetsConnections'.tr(),
                ),
                IconLabelTab(
                  icon: const Icon(Symbols.rocket_launch, size: 18),
                  label: 'tabGithub'.tr(),
                ),
                IconLabelTab(
                  icon: const Icon(Symbols.key, size: 18),
                  label: 'assetsCredentialsTitle'.tr(),
                ),
                IconLabelTab(
                  icon: const Icon(Symbols.code, size: 18),
                  label: 'tabSnippets'.tr(),
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                    children: const [ServerAssetsSection()],
                  ),
                  ListView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                    children: const [GitHubSection(showHeader: false)],
                  ),
                  ListView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                    children: const [CredentialsPage(showHeader: false)],
                  ),
                  ListView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                    children: const [SnippetsSection()],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _fabForTab(_tabController.index),
    );
  }

  /// The unified create action: one floating button whose label and target
  /// follow the active tab. The GitHub tab keeps its in-content sign-in and
  /// pin-repo controls, so no FAB there.
  Widget? _fabForTab(int index) {
    return switch (index) {
      0 => FloatingActionButton.extended(
        heroTag: 'assets-create-fab',
        onPressed: () => _addServer(context, ref),
        icon: const Icon(Symbols.add),
        label: Text('serversAddServer'.tr()),
      ),
      2 => FloatingActionButton.extended(
        heroTag: 'assets-create-fab',
        onPressed: () => _addCredential(context, ref),
        icon: const Icon(Symbols.add),
        label: Text('settingsCredentialAdd'.tr()),
      ),
      3 => FloatingActionButton.extended(
        heroTag: 'assets-create-fab',
        onPressed: () => _newSnippet(context, ref),
        icon: const Icon(Symbols.add),
        label: Text('snippetsNew'.tr()),
      ),
      _ => null,
    };
  }

  Future<void> _addServer(BuildContext context, WidgetRef ref) async {
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

  Future<void> _addCredential(BuildContext context, WidgetRef ref) async {
    final draft = await showCredentialEditorSheet(context);
    if (draft == null) return;
    try {
      await ref.read(serverRepositoryProvider).createCredential(draft);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _newSnippet(BuildContext context, WidgetRef ref) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _SnippetEditor(
        title: 'snippetsNew'.tr(),
        onSave:
            (name, script, tags, excludedFromAutocomplete, dangerous) async {
              await ref
                  .read(snippetRepositoryProvider)
                  .save(
                    id: null,
                    name: name,
                    script: script,
                    tags: tags,
                    excludedFromAutocomplete: excludedFromAutocomplete,
                    dangerous: dangerous,
                  );
              if (context.mounted) Navigator.pop(context, true);
            },
      ),
    );
    if (saved == true && context.mounted) {
      showSnackBar('snippetsSaved'.tr());
    }
  }
}

class ServerAssetsSection extends ConsumerWidget {
  const ServerAssetsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            fileManagementInitialPath: server.fileManagementInitialPath,
            fileManagementFavorites: decodeStringList(
              server.fileManagementFavorites,
            ),
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

class SnippetsSection extends ConsumerWidget {
  const SnippetsSection({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    ScriptSnippet? item,
  ]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _SnippetEditor(
        title: item == null ? 'snippetsNew'.tr() : 'snippetsEdit'.tr(),
        initialName: item?.name,
        initialScript: item?.script,
        initialTags: item == null ? const [] : decodeStringList(item.tags),
        initialExcludedFromAutocomplete:
            item?.excludedFromAutocomplete ?? false,
        initialDangerous: item?.dangerous ?? false,
        onSave:
            (name, script, tags, excludedFromAutocomplete, dangerous) async {
              await ref
                  .read(snippetRepositoryProvider)
                  .save(
                    id: item?.id,
                    name: name,
                    script: script,
                    tags: tags,
                    excludedFromAutocomplete: excludedFromAutocomplete,
                    dangerous: dangerous,
                  );
              if (context.mounted) Navigator.pop(context, true);
            },
      ),
    );
    if (saved == true && context.mounted) {
      showSnackBar('snippetsSaved'.tr());
    }
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    ScriptSnippet snippet,
  ) async {
    final servers = ref.read(serversProvider).asData?.value ?? const <Server>[];
    final connected = ref.read(sessionsProvider).asData?.value ?? const [];
    final connectedIds = connected
        .where((session) => session.status == SessionStatus.connected)
        .map((session) => session.serverId)
        .toSet();
    final remembered = decodeSnippetIdList(snippet.lastServerIds).toSet();
    final selected = await showModalBottomSheet<List<Server>>(
      context: context,
      useSafeArea: true,
      builder: (context) => _ServerPicker(
        servers: servers,
        connectedIds: connectedIds,
        initialSelection: remembered.isEmpty ? connectedIds : remembered,
      ),
    );
    if (selected == null || selected.isEmpty) return;
    if (!context.mounted) return;
    if (!await confirmDangerousSnippet(context, snippet)) return;
    if (!context.mounted) return;

    // Remember the choice so the next run dialog starts from it.
    await ref.read(snippetRepositoryProvider).rememberServers(snippet.id, [
      for (final server in selected) server.id,
    ]);
    if (!context.mounted) return;

    try {
      await Future.wait([
        for (final server in selected)
          (() {
            void Function()? terminate;
            var cancelledBeforeStart = false;
            return runWithDeployTerminal(
              ref: ref,
              title: 'snippetsRunning'.tr(args: [snippet.name]),
              subtitle: server.name,
              command: 'sh -s',
              onCancel: () {
                cancelledBeforeStart = true;
                terminate?.call();
              },
              run: (onOutput) => ref
                  .read(connectionManagerProvider)
                  .runScriptSnippet(
                    server.id,
                    script: snippet.script,
                    onOutput: onOutput,
                    onCancelReady: (callback) {
                      terminate = callback;
                      if (cancelledBeforeStart) callback();
                    },
                  ),
            );
          })(),
      ]);
    } catch (_) {
      // The task terminal shows the per-server error and keeps its log.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snippets = ref.watch(scriptSnippetsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        snippets.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text(error.toString()),
          data: (items) => items.isEmpty
              ? _EmptySnippets(onCreate: () => _edit(context, ref))
              : Column(
                  children: [
                    for (final item in items)
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (item.dangerous)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(
                                  Symbols.warning,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            if (item.excludedFromAutocomplete)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(
                                  Symbols.visibility_off,
                                  size: 18,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                        subtitle: _SnippetSubtitle(snippet: item),
                        leading: const Icon(Symbols.code),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'snippetsRun'.tr(),
                              onPressed: () => _run(context, ref, item),
                              icon: const Icon(Symbols.play_arrow),
                            ),
                            IconButton(
                              tooltip: 'snippetsEdit'.tr(),
                              onPressed: () => _edit(context, ref, item),
                              icon: const Icon(Symbols.edit),
                            ),
                            IconButton(
                              tooltip: 'commonDelete'.tr(),
                              onPressed: () => ref
                                  .read(snippetRepositoryProvider)
                                  .delete(item.id),
                              icon: const Icon(Symbols.delete_outline),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SnippetSubtitle extends StatelessWidget {
  const _SnippetSubtitle({required this.snippet});

  final ScriptSnippet snippet;

  @override
  Widget build(BuildContext context) {
    final tags = decodeStringList(snippet.tags);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          snippet.script.replaceAll('\n', ' '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final tag in tags)
                  Chip(
                    label: Text(tag),
                    labelStyle: Theme.of(context).textTheme.labelSmall,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EmptySnippets extends StatelessWidget {
  const _EmptySnippets({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Symbols.code, size: 40),
          const SizedBox(height: 16),
          Text(
            'snippetsEmpty'.tr(),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text('snippetsEmptyHint'.tr(), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Symbols.add),
            label: Text('snippetsNew'.tr()),
          ),
        ],
      ),
    ),
  );
}

class _SnippetEditor extends ConsumerStatefulWidget {
  const _SnippetEditor({
    required this.title,
    this.initialName,
    this.initialScript,
    this.initialTags = const [],
    this.initialExcludedFromAutocomplete = false,
    this.initialDangerous = false,
    required this.onSave,
  });

  final String title;
  final String? initialName;
  final String? initialScript;
  final List<String> initialTags;
  final bool initialExcludedFromAutocomplete;
  final bool initialDangerous;
  final Future<void> Function(
    String name,
    String script,
    List<String> tags,
    bool excludedFromAutocomplete,
    bool dangerous,
  )
  onSave;

  @override
  ConsumerState<_SnippetEditor> createState() => _SnippetEditorState();
}

class _SnippetEditorState extends ConsumerState<_SnippetEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.initialName);
  late final _scriptController = TextEditingController(
    text: widget.initialScript,
  );
  late final _tags = List<String>.of(widget.initialTags);
  final _tagInput = TextEditingController();
  late bool _excludedFromAutocomplete = widget.initialExcludedFromAutocomplete;
  late bool _dangerous = widget.initialDangerous;

  @override
  void dispose() {
    _nameController.dispose();
    _scriptController.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  void _addTag() {
    final candidates = _tagInput.text
        .split(RegExp(r'[,;]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (candidates.isEmpty) return;
    setState(() {
      for (final tag in candidates) {
        if (!_tags.contains(tag)) _tags.add(tag);
      }
      _tagInput.clear();
    });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(labelText: 'snippetsName'.tr()),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'commonRequired'.tr()
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _scriptController,
              minLines: 10,
              maxLines: 18,
              style: const TextStyle(fontFamily: 'IBM Plex Mono'),
              decoration: InputDecoration(
                labelText: 'snippetsScript'.tr(),
                alignLabelWithHint: true,
                hintText: '#!/bin/sh\necho "Hello from MaidKit"',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'commonRequired'.tr()
                  : null,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'snippetsTagsLabel'.tr(),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'snippetsTagsHint'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in _tags)
                      InputChip(
                        label: Text(tag),
                        onDeleted: () => setState(() => _tags.remove(tag)),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagInput,
                    decoration: InputDecoration(
                      labelText: 'snippetsTagAdd'.tr(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addTag(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _addTag,
                  icon: const Icon(Symbols.add, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('snippetsExcludeFromAutocomplete'.tr()),
              subtitle: Text('snippetsExcludeFromAutocompleteHint'.tr()),
              value: _excludedFromAutocomplete,
              onChanged: (value) =>
                  setState(() => _excludedFromAutocomplete = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('snippetsDangerous'.tr()),
              subtitle: Text('snippetsDangerousHint'.tr()),
              secondary: _dangerous
                  ? Icon(
                      Symbols.warning,
                      color: Theme.of(context).colorScheme.error,
                    )
                  : null,
              value: _dangerous,
              onChanged: (value) => setState(() => _dangerous = value),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  unawaited(
                    widget.onSave(
                      _nameController.text,
                      _scriptController.text,
                      List.of(_tags),
                      _excludedFromAutocomplete,
                      _dangerous,
                    ),
                  );
                },
                child: Text('commonSave'.tr()),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ServerPicker extends ConsumerStatefulWidget {
  const _ServerPicker({
    required this.servers,
    required this.connectedIds,
    this.initialSelection,
  });

  final List<Server> servers;
  final Set<int> connectedIds;

  /// Server ids to pre-check, typically the ones this snippet ran on last
  /// time. Ids without a live connection are dropped because they cannot be
  /// reached.
  final Set<int>? initialSelection;

  @override
  ConsumerState<_ServerPicker> createState() => _ServerPickerState();
}

class _ServerPickerState extends ConsumerState<_ServerPicker> {
  late final Set<int> _selected =
      (widget.initialSelection ?? widget.connectedIds)
          .intersection(widget.connectedIds)
          .toSet();

  @override
  Widget build(BuildContext context) {
    final connectedServers = widget.servers
        .where((server) => widget.connectedIds.contains(server.id))
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'snippetsSelectServers'.tr(),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text('snippetsSelectServersHint'.tr()),
          const SizedBox(height: 12),
          if (connectedServers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('snippetsNoConnectedServers'.tr()),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final server in connectedServers)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _selected.contains(server.id),
                      title: Text(server.name),
                      subtitle: Text(
                        ref.watch(hideServerAddressesProvider)
                            ? server.username
                            : server.host,
                      ),
                      onChanged: (checked) => setState(() {
                        if (checked ?? false) {
                          _selected.add(server.id);
                        } else {
                          _selected.remove(server.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      connectedServers
                          .where((server) => _selected.contains(server.id))
                          .toList(),
                    ),
              icon: const Icon(Symbols.play_arrow),
              label: Text('snippetsRun'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}
