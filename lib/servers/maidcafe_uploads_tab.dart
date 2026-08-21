import 'package:easy_localization/easy_localization.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'maidcafe_stream.dart';

/// Structured editor for the daemon's managed-container cloud upload
/// settings: the `statusUploadEnabled` switch plus the `managedContainers`
/// and `managedComposes` allowlists.
///
/// Changes persist through [onPersist]: the host's root-owned
/// `/etc/maidcafe/config.toml` is patched over SSH (the daemon user cannot
/// write it on managed hosts) and the daemon hot-reloads the file — no
/// restart. The tab still needs the port-forwarded session to read the
/// current values; without it the server tab shows a connect hint.
class MaidCafeUploadsTab extends StatefulWidget {
  const MaidCafeUploadsTab({
    super.key,
    required this.session,
    required this.onPersist,
  });

  final MaidCafeStreamSession session;

  /// Persists a settings patch host-side: the root-owned config is patched
  /// over SSH (same channel as the alarms editor) and the daemon's config
  /// watcher hot-reloads it.
  final Future<void> Function(Map<String, Object?> patch) onPersist;

  @override
  State<MaidCafeUploadsTab> createState() => _MaidCafeUploadsTabState();
}

class _MaidCafeUploadsTabState extends State<MaidCafeUploadsTab> {
  var _loading = true;
  Object? _error;
  var _statusUpload = false;
  List<String> _managedContainers = const [];
  List<String> _managedComposes = const [];
  var _saving = false;

  final _containerController = TextEditingController();
  final _composeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _containerController.dispose();
    _composeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await widget.session.config();
      final view = config['config'];
      if (view is! Map) {
        throw StateError('maidCafeUploadsInvalidConfig'.tr());
      }
      if (!mounted) return;
      setState(() {
        _statusUpload = view['status_upload_enabled'] == true;
        _managedContainers = _stringList(view['managed_containers']);
        _managedComposes = _stringList(view['managed_composes']);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  static List<String> _stringList(Object? value) => [
    if (value is List)
      for (final entry in value)
        if (entry is String) entry,
  ];

  Future<void> _patch(Map<String, Object?> patch) async {
    setState(() => _saving = true);
    try {
      await widget.onPersist(patch);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('maidCafeUploadsSaved'.tr())));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('maidCafeUploadsSaveFailed'.tr(args: ['$error'])),
        ),
      );
      // The daemon may have rejected part of the change; resync with its
      // actual state.
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _updateContainers(List<String> next) {
    setState(() => _managedContainers = next);
    _patch({'managedContainers': next});
  }

  void _updateComposes(List<String> next) {
    setState(() => _managedComposes = next);
    _patch({'managedComposes': next});
  }

  void _toggleStatus(bool value) {
    setState(() => _statusUpload = value);
    _patch({'statusUploadEnabled': value});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          Icon(Symbols.error, size: 40, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(
            '$_error',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton(
              onPressed: _load,
              child: Text('maidCafeUploadsRetry'.tr()),
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('maidCafeUploadsTitle'.tr(), style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'maidCafeUploadsHint'.tr(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('maidCafeUploadsStatusSwitch'.tr()),
          subtitle: Text('maidCafeUploadsStatusHint'.tr()),
          value: _statusUpload,
          onChanged: _saving ? null : _toggleStatus,
        ),
        _listEditor(
          title: 'maidCafeUploadsContainers'.tr(),
          fieldHint: 'maidCafeUploadsAddContainer'.tr(),
          values: _managedContainers,
          controller: _containerController,
          onChanged: _updateContainers,
        ),
        _listEditor(
          title: 'maidCafeUploadsComposes'.tr(),
          fieldHint: 'maidCafeUploadsAddCompose'.tr(),
          values: _managedComposes,
          controller: _composeController,
          onChanged: _updateComposes,
        ),
      ],
    );
  }

  Widget _listEditor({
    required String title,
    required String fieldHint,
    required List<String> values,
    required TextEditingController controller,
    required ValueChanged<List<String>> onChanged,
  }) {
    final theme = Theme.of(context);
    void add() {
      final value = controller.text.trim();
      if (value.isEmpty || values.contains(value)) return;
      controller.clear();
      onChanged([...values, value]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (values.isEmpty)
          Text(
            'maidCafeUploadsEmpty'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in values)
                InputChip(
                  label: Text(value),
                  onDeleted: _saving
                      ? null
                      : () => onChanged([...values]..remove(value)),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !_saving,
                decoration: InputDecoration(
                  hintText: fieldHint,
                  isDense: true,
                ),
                onSubmitted: (_) => add(),
              ),
            ),
            IconButton(
              icon: const Icon(Symbols.add),
              tooltip: 'maidCafeUploadsAdd'.tr(),
              onPressed: _saving ? null : add,
            ),
          ],
        ),
      ],
    );
  }
}
