import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:island_ui_foundation/island_ui_foundation.dart';

import 'package:maid_kit/data/local/app_database.dart';

/// The endpoint override for a server, plus the reverse-proxy recipe that makes
/// one worth having.
///
/// The daemon serves plain HTTP and, by default, only on loopback. An override
/// names an address this app — and a browser build in particular, which has no
/// SSH tunnel to fall back on — reaches the daemon at, and the recommended
/// address is an HTTPS reverse proxy that terminates TLS in front of it.
class MaidCafeEndpointOverrideSection extends StatefulWidget {
  const MaidCafeEndpointOverrideSection({
    required this.server,
    required this.port,
    required this.busy,
    required this.onSave,
    required this.onChanged,
    super.key,
  });

  final Server server;

  /// The daemon's own port, for the proxy recipe.
  final int port;
  final bool busy;

  /// Persists the override, or clears it when [endpoint] is null. Throwing
  /// reports the validation message back to the user.
  final Future<void> Function(String? endpoint) onSave;

  /// Called after the override is written, so the rest of the app re-reads it.
  final VoidCallback onChanged;

  @override
  State<MaidCafeEndpointOverrideSection> createState() =>
      _MaidCafeEndpointOverrideSectionState();
}

class _MaidCafeEndpointOverrideSectionState
    extends State<MaidCafeEndpointOverrideSection> {
  late final TextEditingController _controller;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.server.maidCafeTerminalUrl ?? '',
    );
  }

  @override
  void didUpdateWidget(MaidCafeEndpointOverrideSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final stored = widget.server.maidCafeTerminalUrl ?? '';
    // The server row changed underneath (an install or a probe wrote it): show
    // what is stored rather than leaving a stale edit on screen.
    if (widget.server.id != oldWidget.server.id ||
        (widget.server.maidCafeTerminalUrl !=
                oldWidget.server.maidCafeTerminalUrl &&
            _controller.text.trim() != stored)) {
      _controller.text = stored;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _caddyRecipe =>
      '''
# /etc/caddy/Caddyfile
daemon.example.com {
    reverse_proxy 127.0.0.1:${widget.port}
}
''';

  String get _nginxRecipe =>
      '''
# /etc/nginx/sites-available/maidcafe
server {
    listen 443 ssl;
    server_name daemon.example.com;

    ssl_certificate     /etc/letsencrypt/live/daemon.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/daemon.example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:${widget.port};
        proxy_http_version 1.1;
        # The log stream and the terminal are long-lived connections.
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 1d;
    }
}
''';

  Future<void> _save({bool clear = false}) async {
    if (_saving || widget.busy) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(clear ? null : _controller.text.trim());
      if (clear) _controller.clear();
      widget.onChanged();
      if (mounted) {
        showStyledSnackBar(
          message: 'maidCafeEndpointOverrideSaved'.tr(),
          title: 'maidCafeGroupEndpoint'.tr(),
          icon: Symbols.check_circle,
          accentColor: Theme.of(context).colorScheme.primary,
        );
      }
    } catch (error) {
      if (mounted) {
        showStyledSnackBar(
          message: error.toString(),
          title: 'maidCafeEndpointOverrideInvalid'.tr(),
          icon: Symbols.error_outline,
          accentColor: Theme.of(context).colorScheme.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showStyledSnackBar(
        message: 'maidCafeReverseProxyCopied'.tr(),
        icon: Symbols.content_copy,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = widget.busy || _saving;
    // A TabBarView is a lookup boundary: a page it builds cannot see the
    // Material above the tab view. The rest of this page has the same need, so
    // a page-local Material keeps this field and its buttons satisfied however
    // the page is rebuilt.
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'maidCafeGroupEndpoint'.tr(),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              enabled: !disabled,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'maidCafeEndpointOverride'.tr(),
                helperText: 'maidCafeEndpointOverrideHint'.tr(),
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: disabled ? null : () => _save(),
                  icon: const Icon(Symbols.save, size: 18),
                  label: Text('commonSave'.tr()),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: disabled ? null : () => _save(clear: true),
                  icon: const Icon(Symbols.delete_sweep, size: 18),
                  label: Text('maidCafeEndpointOverrideClear'.tr()),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ProxyRecipe(
              title: 'maidCafeReverseProxyTitle'.tr(),
              body: 'maidCafeReverseProxyBody'.tr(args: ['${widget.port}']),
              recipes: [('Caddy', _caddyRecipe), ('nginx', _nginxRecipe)],
              onCopy: _copy,
            ),
          ],
        ),
      ),
    );
  }
}

/// The reverse-proxy recipe: why, and the two configs worth copying.
class _ProxyRecipe extends StatelessWidget {
  const _ProxyRecipe({
    required this.title,
    required this.body,
    required this.recipes,
    required this.onCopy,
  });

  final String title;
  final String body;
  final List<(String, String)> recipes;
  final Future<void> Function(String) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Symbols.shield_lock,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(title, style: theme.textTheme.labelLarge)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final (name, recipe) in recipes) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(name, style: theme.textTheme.labelMedium),
                  ),
                  IconButton(
                    tooltip: 'commonCopy'.tr(),
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onCopy(recipe),
                    icon: const Icon(Symbols.content_copy),
                  ),
                ],
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  recipe,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
