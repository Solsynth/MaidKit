import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/package_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'container_models.dart';

Future<ContainerRuntime?> chooseContainerRuntimeToInstall(
  BuildContext context,
) => showModalBottomSheet<ContainerRuntime>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  builder: (_) => const _ContainerRuntimeInstallSheet(),
);

Future<void> installContainerRuntime({
  required WidgetRef ref,
  required Server server,
  required ContainerRuntime runtime,
  required String? sudoPassword,
}) async {
  final manager = ref.read(connectionManagerProvider);
  final status = await manager.getPackageManagerStatus(server.id);
  final packageManager = status.preferred;
  if (packageManager == null) {
    throw StateError('No supported system package manager was found.');
  }
  final package = _runtimePackageName(runtime, packageManager);
  await runWithDeployTerminal(
    ref: ref,
    title: 'Installing ${runtime.name}',
    subtitle: '${packageManager.label} · ${server.name}',
    command: '${packageManager.label} install $package',
    run: (onOutput) => manager.runPackageAction(
      server.id,
      manager: packageManager,
      action: PackageAction.install,
      packageName: package,
      sshUserIsRoot: server.username == 'root',
      sudoPassword: sudoPassword,
      onOutput: onOutput,
    ),
  );
}

String _runtimePackageName(ContainerRuntime runtime, PackageManager manager) =>
    switch ((runtime, manager)) {
      (ContainerRuntime.docker, PackageManager.apt) => 'docker.io',
      (ContainerRuntime.docker, PackageManager.dnf) ||
      (ContainerRuntime.docker, PackageManager.yum) => 'moby-engine',
      (ContainerRuntime.docker, _) => 'docker',
      (ContainerRuntime.podman, _) => 'podman',
    };

class _ContainerRuntimeInstallSheet extends StatefulWidget {
  const _ContainerRuntimeInstallSheet();

  @override
  State<_ContainerRuntimeInstallSheet> createState() =>
      _ContainerRuntimeInstallSheetState();
}

class _ContainerRuntimeInstallSheetState
    extends State<_ContainerRuntimeInstallSheet> {
  var _runtime = ContainerRuntime.docker;

  @override
  Widget build(BuildContext context) => SheetScaffold(
    titleText: 'runtimeInstallTitle'.tr(),
    heightFactor: 0.42,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'runtimeInstallInfo'.tr(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<ContainerRuntime>(
            initialValue: _runtime,
            decoration: InputDecoration(labelText: 'runtimeInstallLabel'.tr()),
            items: [
              DropdownMenuItem(
                value: ContainerRuntime.docker,
                child: Text('runtimeDocker'.tr()),
              ),
              DropdownMenuItem(
                value: ContainerRuntime.podman,
                child: Text('runtimePodman'.tr()),
              ),
            ],
            onChanged: (value) => setState(() => _runtime = value!),
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context, _runtime),
              icon: const Icon(Symbols.download),
              label: const Text('runtimeInstallSubmit').tr(),
            ),
          ),
        ],
      ),
    ),
  );
}
