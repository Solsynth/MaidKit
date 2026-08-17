import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/transfer_conflict_preferences.dart';

void main() {
  test('defaults to renaming conflicting files', () {
    final settings = InMemoryTransferConflictSettings();
    expect(settings.conflictMode, TransferConflictMode.rename);
  });

  test('restores and saves the transfer conflict mode', () async {
    final settings = InMemoryTransferConflictSettings(
      TransferConflictMode.rename,
    );
    final container = ProviderContainer(
      overrides: [transferConflictSettingsProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(transferConflictModeProvider),
      TransferConflictMode.rename,
    );

    await container
        .read(transferConflictModeProvider.notifier)
        .setMode(TransferConflictMode.overwrite);

    expect(settings.conflictMode, TransferConflictMode.overwrite);
    expect(
      container.read(transferConflictModeProvider),
      TransferConflictMode.overwrite,
    );
  });
}
