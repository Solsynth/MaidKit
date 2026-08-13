import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:yaml/yaml.dart';

import 'package:maid_kit/theme.dart';

/// A Compose editor with a safe guided form for common service settings and a
/// raw YAML mode for all Compose features.
class ComposeProjectEditor extends StatefulWidget {
  const ComposeProjectEditor({
    super.key,
    this.initialSource,
    required this.onChanged,
  });

  final String? initialSource;
  final ValueChanged<String> onChanged;

  @override
  State<ComposeProjectEditor> createState() => _ComposeProjectEditorState();
}

enum _ComposeEditorMode { guided, advanced }

class _ComposeProjectEditorState extends State<ComposeProjectEditor> {
  late final List<_ComposeServiceDraft> _services;
  late final _source = TextEditingController(text: widget.initialSource ?? '');
  late _ComposeEditorMode _mode;

  @override
  void initState() {
    super.initState();
    final parsed = _servicesFromCompose(widget.initialSource);
    _services =
        parsed ?? [_ComposeServiceDraft(name: 'app', image: 'nginx:alpine')];
    _mode = widget.initialSource?.trim().isNotEmpty == true && parsed == null
        ? _ComposeEditorMode.advanced
        : _ComposeEditorMode.guided;
    _notifyChanged();
  }

  @override
  void dispose() {
    _source.dispose();
    for (final service in _services) {
      service.dispose();
    }
    super.dispose();
  }

  void _notifyChanged() => widget.onChanged(
    _mode == _ComposeEditorMode.advanced ? _source.text : _buildCompose(),
  );

  bool _isServiceName(String value) =>
      RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]*$').hasMatch(value);

  List<_ComposeServiceDraft>? _servicesFromCompose(String? source) {
    if (source == null || source.trim().isEmpty) return null;
    try {
      final root = loadYaml(source);
      if (root is! YamlMap || root['services'] is! YamlMap) return null;
      if (root.keys.any((key) => key.toString() != 'services')) return null;
      final drafts = <_ComposeServiceDraft>[];
      for (final entry in (root['services'] as YamlMap).entries) {
        final serviceName = entry.key.toString();
        final service = entry.value;
        if (!_isServiceName(serviceName) || service is! YamlMap) continue;
        const supportedKeys = {'image', 'ports', 'environment', 'volumes'};
        if (service.keys.any(
              (key) => !supportedKeys.contains(key.toString()),
            ) ||
            !_isSimpleList(service['ports']) ||
            !_isSimpleEnvironment(service['environment']) ||
            !_isSimpleList(service['volumes'])) {
          return null;
        }
        final image = service['image']?.toString().trim() ?? '';
        if (image.isEmpty) return null;
        drafts.add(
          _ComposeServiceDraft(
            name: serviceName,
            image: image,
            ports: _composeLines(service['ports']),
            environment: _environmentLines(service['environment']),
            volumes: _composeLines(service['volumes']),
          ),
        );
      }
      return drafts.isEmpty ? null : drafts;
    } on YamlException {
      return null;
    }
  }

  bool _isSimpleList(Object? value) =>
      value == null ||
      value is String ||
      value is Iterable && value.every((item) => item is String || item is num);

  bool _isSimpleEnvironment(Object? value) =>
      _isSimpleList(value) ||
      value is Map &&
          value.entries.every(
            (entry) =>
                entry.key is String &&
                (entry.value == null ||
                    entry.value is String ||
                    entry.value is num ||
                    entry.value is bool),
          );

  String _composeLines(Object? value) => value is Iterable
      ? value.map((item) => item.toString()).join('\n')
      : value?.toString() ?? '';

  String _environmentLines(Object? value) => value is Map
      ? value.entries
            .map((entry) => '${entry.key}=${entry.value ?? ''}')
            .join('\n')
      : _composeLines(value);

  List<String> _lines(TextEditingController controller) => controller.text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  String _buildCompose() {
    final buffer = StringBuffer('services:\n');
    for (final service in _services) {
      buffer.writeln('  ${service.name.text.trim()}:');
      buffer.writeln('    image: ${jsonEncode(service.image.text.trim())}');
      _writeList(buffer, 'ports', _lines(service.ports));
      _writeEnvironment(buffer, _lines(service.environment));
      _writeList(buffer, 'volumes', _lines(service.volumes));
    }
    return buffer.toString();
  }

  void _writeList(StringBuffer buffer, String label, List<String> values) {
    if (values.isEmpty) return;
    buffer.writeln('    $label:');
    for (final value in values) {
      buffer.writeln('      - ${jsonEncode(value)}');
    }
  }

  void _writeEnvironment(StringBuffer buffer, List<String> values) {
    if (values.isEmpty) return;
    buffer.writeln('    environment:');
    for (final value in values) {
      final separator = value.indexOf('=');
      if (separator <= 0) {
        buffer.writeln('      - ${jsonEncode(value)}');
      } else {
        buffer.writeln(
          '      ${value.substring(0, separator).trim()}: ${jsonEncode(value.substring(separator + 1))}',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<_ComposeEditorMode>(
          segments: [
            ButtonSegment(
              value: _ComposeEditorMode.guided,
              icon: Icon(Symbols.tune, size: 18),
              label: Text('editorGuided'.tr()),
            ),
            ButtonSegment(
              value: _ComposeEditorMode.advanced,
              icon: Icon(Symbols.code, size: 18),
              label: Text('editorAdvanced'.tr()),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (selection) => setState(() {
            _mode = selection.first;
            _notifyChanged();
          }),
        ),
        const SizedBox(height: 16),
        if (_mode == _ComposeEditorMode.guided) ...[
          Text(
            widget.initialSource?.trim().isNotEmpty == true
                ? 'editorServicesLoaded'.tr()
                : 'editorServicesHint'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < _services.length; index++)
            _serviceEditor(index, _services[index]),
          TextButton.icon(
            onPressed: () => setState(() {
              _services.add(_ComposeServiceDraft());
              _notifyChanged();
            }),
            icon: const Icon(Symbols.add, size: 18),
            label: const Text('editorAddService').tr(),
          ),
        ] else
          TextField(
            controller: _source,
            onChanged: (_) => _notifyChanged(),
            minLines: 18,
            maxLines: 28,
            style: const TextStyle(fontFamily: MaidKitFonts.mono, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'editorComposeFileName'.tr(),
              alignLabelWithHint: true,
              helperText: 'editorComposeFileHint'.tr(),
            ),
          ),
      ],
    );
  }

  Widget _serviceEditor(int index, _ComposeServiceDraft service) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Service ${index + 1}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                if (_services.length > 1)
                  IconButton(
                    tooltip: 'editorRemoveService'.tr(),
                    onPressed: () => setState(() {
                      _services.removeAt(index).dispose();
                      _notifyChanged();
                    }),
                    icon: const Icon(Symbols.close, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _field(service.name, 'editorServiceName'.tr()),
            const SizedBox(height: 12),
            _field(
              service.image,
              'editorImage'.tr(),
              hint: 'editorImageHint'.tr(),
            ),
            const SizedBox(height: 12),
            _field(
              service.ports,
              'editorPortsLabel'.tr(),
              hint: 'editorPortsHint'.tr(),
              helper: 'editorPortsHelper'.tr(),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            _field(
              service.environment,
              'editorEnvLabel'.tr(),
              hint: 'editorEnvHint'.tr(),
              helper: 'editorEnvHelper'.tr(),
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            _field(
              service.volumes,
              'editorFoldersLabel'.tr(),
              hint: 'editorFoldersHint'.tr(),
              helper: 'editorFoldersHelper'.tr(),
              maxLines: 3,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    String? helper,
    int maxLines = 1,
  }) => TextField(
    controller: controller,
    onChanged: (_) => _notifyChanged(),
    minLines: 1,
    maxLines: maxLines,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
    ),
  );
}

class _ComposeServiceDraft {
  _ComposeServiceDraft({
    String name = '',
    String image = '',
    String ports = '',
    String environment = '',
    String volumes = '',
  }) : name = TextEditingController(text: name),
       image = TextEditingController(text: image),
       ports = TextEditingController(text: ports),
       environment = TextEditingController(text: environment),
       volumes = TextEditingController(text: volumes);
  final TextEditingController name;
  final TextEditingController image;
  final TextEditingController ports;
  final TextEditingController environment;
  final TextEditingController volumes;
  void dispose() {
    name.dispose();
    image.dispose();
    ports.dispose();
    environment.dispose();
    volumes.dispose();
  }
}
