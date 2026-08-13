import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'connection_import_service.dart';

/// Review sheet for parsed connections: checkboxes per server, duplicates
/// unchecked by default, credential-less rows flagged. Pops with the selected
/// candidates or null when cancelled.
class ConnectionImportPreviewSheet extends StatefulWidget {
  const ConnectionImportPreviewSheet({super.key, required this.candidates});

  final List<ImportCandidate> candidates;

  @override
  State<ConnectionImportPreviewSheet> createState() =>
      _ConnectionImportPreviewSheetState();
}

class _ConnectionImportPreviewSheetState
    extends State<ConnectionImportPreviewSheet> {
  late final Set<int> _selected = {
    for (final (index, candidate) in widget.candidates.indexed)
      if (!candidate.isDuplicate) index,
  };

  @override
  Widget build(BuildContext context) {
    final candidates = widget.candidates;
    return SheetScaffold(
      titleText: 'settingsConnectionsImportPreviewTitle'.tr(),
      heightFactor: 0.75,
      child: candidates.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [const Text('settingsConnectionsImportEmpty').tr()],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                const Text('settingsConnectionsImportPreviewHint').tr(),
                const SizedBox(height: 12),
                for (final (index, candidate) in candidates.indexed)
                  CheckboxListTile(
                    value: _selected.contains(index),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        _selected.add(index);
                      } else {
                        _selected.remove(index);
                      }
                    }),
                    controlAffinity: ListTileControlAffinity.leading,
                    secondary: Icon(
                      candidate.connection.credential == null
                          ? Symbols.key_off
                          : Symbols.key,
                    ),
                    title: Text(candidate.connection.name),
                    subtitle: _candidateSubtitle(candidate),
                    isThreeLine: true,
                  ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      'settingsConnectionsImportSelected'.tr(
                        args: ['${_selected.length}'],
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('commonCancel').tr(),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _selected.isEmpty
                          ? null
                          : () => Navigator.of(context).pop([
                              for (final index in _selected) candidates[index],
                            ]),
                      child: const Text('settingsConnectionsImportAction').tr(),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  List<String> _candidateWarnings(ImportCandidate candidate) => [
    if (candidate.isDuplicate) 'settingsConnectionsImportDuplicate'.tr(),
    if (candidate.connection.credential == null)
      'settingsConnectionsImportNoCredential'.tr(),
  ];

  Widget _candidateSubtitle(ImportCandidate candidate) {
    final connection = candidate.connection;
    final address =
        '${connection.username.isEmpty ? '?' : connection.username}'
        '@${connection.host}:${connection.port}';
    final details = [connection.source, ..._candidateWarnings(candidate)];
    return Text('$address\n${details.join(' • ')}');
  }
}
