import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'server_models.dart';

import 'maidcafe_service.dart';
import 'maidcafe_install.dart';
import 'server_providers.dart';

class MaidCafeServerTab extends ConsumerStatefulWidget {
  const MaidCafeServerTab({super.key, required this.server});

  final Server server;

  @override
  ConsumerState<MaidCafeServerTab> createState() => _MaidCafeServerTabState();
}

class _MaidCafeServerTabState extends ConsumerState<MaidCafeServerTab> {
  late final TextEditingController _nameController;
  late final TextEditingController _daemonUrlController;
  late final TextEditingController _webhookSecretController;
  String? _message;
  String? _health;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.server.name);
    _daemonUrlController = TextEditingController(
      text: widget.server.maidCafeDaemonUrl ?? maidCafeDefaultLocalDaemonUrl,
    );
    _webhookSecretController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _daemonUrlController.dispose();
    _webhookSecretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cloudUser = ref.watch(cloudUserProvider);
    final daemons = ref.watch(maidCafeDaemonsProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'maidCafeServerTitle'.tr(),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text('maidCafeServerHint'.tr()),
          const SizedBox(height: 20),
          _serverConfig(context),
          const SizedBox(height: 20),
          cloudUser.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => _signedOut(),
            data: (user) => user == null ? _signedOut() : _registered(daemons),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!),
          ],
        ],
      ),
    );
  }

  Widget _serverConfig(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'maidCafeServerConfigTitle'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text('maidCafeServerConfigHint'.tr()),
          const SizedBox(height: 12),
          TextField(
            controller: _daemonUrlController,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: 'maidCafeServerDaemonUrl'.tr(),
              helperText: 'maidCafeServerDaemonUrlHint'.tr(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _webhookSecretController,
            enabled: !_busy,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'maidCafeServerWebhookSecret'.tr(),
              helperText: 'maidCafeServerWebhookSecretHint'.tr(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy ? null : () => _saveConfig(context),
                child: Text('maidCafeSave'.tr()),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _checkHealth(context),
                icon: const Icon(Symbols.health_and_safety),
                label: Text('maidCafeCheckHealth'.tr()),
              ),
              if (_health != null) Text(_health!),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _saveConfig(BuildContext context) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref
          .read(serverRepositoryProvider)
          .updateMaidCafeConfig(
            widget.server,
            daemonUrl: _daemonUrlController.text,
            webhookSecret: _webhookSecretController.text,
          );
      _webhookSecretController.clear();
      if (mounted) {
        setState(() => _message = 'maidCafeServerConfigSaved'.tr());
      }
      ref.invalidate(serversProvider);
    } catch (error) {
      if (mounted) setState(() => _message = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkHealth(BuildContext context) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final health = await ref
          .read(maidCafeServiceProvider)
          .checkDaemonHealth(daemonBaseUrl: _daemonUrlController.text);
      if (mounted) {
        setState(
          () => _health = '${'maidCafeHealthResult'.tr()}: ${health.ok}',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _signedOut() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text('maidCafeSignInRequired'.tr()),
    ),
  );

  Widget _registered(AsyncValue<List<MaidCafeDaemon>> daemons) => daemons.when(
    loading: () => const LinearProgressIndicator(),
    error: (error, _) => Row(
      children: [
        Expanded(child: Text(_errorText(error))),
        TextButton(
          onPressed: () => ref.invalidate(maidCafeDaemonsProvider),
          child: Text('maidCafeRetry'.tr()),
        ),
      ],
    ),
    data: (items) {
      final daemon = items
          .where((item) => item.name == _nameController.text.trim())
          .firstOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (daemon != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('maidCafeInstallDaemonHint'.tr()),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _installDaemon(daemon),
                        icon: const Icon(Symbols.download),
                        label: Text('maidCafeInstallDaemon'.tr()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          TextField(
            controller: _nameController,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: 'maidCafeDaemonName'.tr(),
              helperText: daemon == null
                  ? 'maidCafeServerRegisterHint'.tr()
                  : 'maidCafeServerRegisteredHint'.tr(),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _busy || daemon != null ? null : _register,
              icon: const Icon(Symbols.add_link),
              label: Text('maidCafeRegister'.tr()),
            ),
          ),
        ],
      );
    },
  );

  Future<void> _installDaemon(MaidCafeDaemon daemon) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final cloudSecret = await ref
          .read(maidCafeServiceProvider)
          .storedCloudSecret(daemon.id);
      if (cloudSecret == null || cloudSecret.trim().isEmpty) {
        if (mounted) {
          setState(
            () => _message = 'maidCafeInstallDaemonNeedsRegistration'.tr(),
          );
        }
        return;
      }
      String? sudoPassword;
      if (widget.server.username != 'root') {
        final credential = await ref
            .read(serverRepositoryProvider)
            .credentialFor(widget.server);
        if (credential.type == CredentialType.password) {
          sudoPassword = credential.password;
        }
      }
      await installMaidCafeDaemon(
        ref: ref,
        server: widget.server,
        daemon: daemon,
        cloudUrl: ref.read(maidCafeCloudUrlProvider),
        cloudSecret: cloudSecret,
        sudoPassword: sudoPassword,
      );
      if (mounted) {
        setState(() => _message = 'maidCafeInstallDaemonSuccess'.tr());
      }
    } catch (error) {
      if (mounted) setState(() => _message = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _message = 'maidCafeDaemonNameRequired'.tr());
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final credential = await ref
          .read(maidCafeServiceProvider)
          .createDaemon(name: name);
      ref.invalidate(maidCafeDaemonsProvider);
      if (mounted) await _showSecret(credential);
    } on MaidCafeException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showSecret(MaidCafeDaemonCredential credential) async {
    final snippet =
        '[daemon]\nid = "${credential.id}"\ncloudUrl = "${ref.read(maidCafeCloudUrlProvider)}"\ncloudSecret = "${credential.secret}"';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('maidCafeOneTimeSecret'.tr()),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('maidCafeOneTimeSecretWarning'.tr()),
              const SizedBox(height: 12),
              SelectableText(credential.secret),
              const SizedBox(height: 12),
              SelectableText(snippet),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: snippet)),
            child: Text('maidCafeCopySnippet'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text('maidCafeDone'.tr()),
          ),
        ],
      ),
    );
  }

  String _errorText(Object error) =>
      error is MaidCafeException ? error.message : error.toString();
}
