import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:styled_widget/styled_widget.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:maid_kit/shared/services/package_info_provider.dart';
import 'package:solsynth_express/solsynth_express.dart';
import 'package:maid_kit/shared/services/update_preferences.dart';

/// Opens the Solar Network product page in the default browser.
Future<void> _openSolarNetwork() async {
  final uri = Uri.parse('https://solsynth.dev/products/solar-network');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

@RoutePage()
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packageInfo = ref.watch(packageInfoProvider);
    final updateChannel =
        ref.watch(maidKitUpdateChannelProvider).asData?.value ??
        kMaidKitDefaultUpdateChannel;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('aboutTitle'.tr())),
      body: packageInfo.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('aboutLoadError'.tr(args: [error.toString()])),
          ),
        ),
        data: (info) {
          final appName = info.appName.isEmpty ? 'title'.tr() : info.appName;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/icons/icon.png',
                          width: 112,
                          height: 112,
                          errorBuilder: (_, _, _) => Container(
                            width: 112,
                            height: 112,
                            alignment: Alignment.center,
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Symbols.dns,
                              size: 48,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        appName,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'aboutVersionInfo'.tr(
                          args: [info.version, info.buildNumber],
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'aboutDescription'.tr(),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'aboutLogo'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('aboutAppInfo'.tr(), style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Symbols.info),
                          title: Text('aboutVersion'.tr()),
                          subtitle: Text(info.version),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Symbols.build),
                          title: Text('aboutBuild'.tr()),
                          subtitle: Text(info.buildNumber),
                        ),
                        if (info.packageName.isNotEmpty) ...[
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Symbols.inventory_2),
                            title: Text('aboutPackageName'.tr()),
                            subtitle: SelectableText(info.packageName),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'updateSection'.tr(),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: const Icon(Symbols.update),
                      title: Text('checkForUpdates'.tr()),
                      subtitle: Text('checkForUpdatesHint'.tr()),
                      trailing: const Icon(Symbols.chevron_right),
                      onTap: () async {
                        await UpdateService(
                          apiBaseUrl: kMaidKitDistributionApiBaseUrl,
                          channel: updateChannel,
                          productId: kMaidKitDistributionProductId,
                          enabled: true,
                        ).checkForUpdates(context);
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'aboutOtherWorks'.tr(),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/icons/solian-icon.webp',
                          width: 40,
                          height: 40,
                          errorBuilder: (_, _, _) => Container(
                            width: 40,
                            height: 40,
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Symbols.diversity_3,
                              size: 24,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      title: Text('aboutSolianName'.tr()),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('aboutSolianDescription'.tr()),
                          const SizedBox(height: 4),
                          Text('aboutSolianSubDescription'.tr()).fontSize(11),
                        ],
                      ),
                      trailing: TextButton(
                        onPressed: _openSolarNetwork,
                        child: Text('aboutSeeMore'.tr()),
                      ),
                      onTap: _openSolarNetwork,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('aboutLegal'.tr(), style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: const Icon(Symbols.description),
                      title: Text('aboutOpenSourceLicenses'.tr()),
                      subtitle: Text('aboutOpenSourceLicensesHint'.tr()),
                      trailing: const Icon(Symbols.chevron_right),
                      onTap: () {
                        showLicensePage(
                          context: context,
                          applicationName: appName,
                          applicationVersion: info.version,
                          applicationIcon: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Image.asset(
                              'assets/icons/icon.png',
                              width: 48,
                              height: 48,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Symbols.dns, size: 48),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'aboutCopyright'.tr(args: ['${DateTime.now().year}']),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'aboutMadeWith'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
