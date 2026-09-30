import 'package:easy_localization/easy_localization.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';

/// Asks twice before a [snippet] marked dangerous is run, so a single stray
/// confirmation cannot fire an irreversible command.
///
/// Returns `true` for snippets that are not dangerous, and only after both
/// prompts are accepted for the ones that are.
Future<bool> confirmDangerousSnippet(
  BuildContext context,
  ScriptSnippet snippet,
) async {
  if (!snippet.dangerous) return true;
  final confirmed = await showMaidKitConfirmAlert(
    'snippetsDangerousBody'.tr(args: [snippet.name]),
    'snippetsDangerousTitle'.tr(),
    icon: Symbols.warning_rounded,
    isDanger: true,
  );
  if (!confirmed || !context.mounted) return false;
  return showMaidKitConfirmAlert(
    'snippetsDangerousAgain'.tr(args: [snippet.name]),
    snippet.name,
    icon: Symbols.warning_rounded,
    isDanger: true,
  );
}
