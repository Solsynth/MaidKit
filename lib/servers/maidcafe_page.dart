import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/shared/presentation/app_scaffold.dart';
import 'maidcafe_settings_section.dart';

/// Desktop workspace page for MaidCafe daemon and webhook management.
@RoutePage()
class MaidCafePage extends StatelessWidget {
  const MaidCafePage({super.key});

  @override
  Widget build(BuildContext context) => MaidKitAppScaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: const [
            _MaidCafeHeader(),
            SizedBox(height: 24),
            MaidCafeSettingsSection(showTitle: false),
          ],
        ),
      ),
    ),
  );
}

class _MaidCafeHeader extends StatelessWidget {
  const _MaidCafeHeader();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Symbols.cloud_sync, color: colors.onPrimaryContainer),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'maidCafePageEyebrow'.tr(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.primary,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'maidCafeTitle'.tr(),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'maidCafePageDescription'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
