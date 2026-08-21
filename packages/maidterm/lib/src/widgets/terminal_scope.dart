import 'package:flutter/widgets.dart';

import '../rendering/terminal_render_cache.dart';

TerminalRenderCache? terminalScopeRenderCacheOf(BuildContext context) {
  return context
      .dependOnInheritedWidgetOfExactType<_TerminalScopeInherited>()
      ?.renderCache;
}

/// Shares terminal resources across descendant [TerminalView] widgets.
///
/// Wrapping multiple terminals in the same scope lets compatible renderers
/// reuse expensive internal caches. Terminals outside a scope create an
/// isolated local scope automatically.
class TerminalScope extends StatefulWidget {
  final Widget child;

  const TerminalScope({super.key, required this.child});

  @override
  State<TerminalScope> createState() => _TerminalScopeState();
}

class _TerminalScopeState extends State<TerminalScope> {
  final _renderCache = TerminalRenderCache();

  @override
  Widget build(BuildContext context) {
    return _TerminalScopeInherited(
      renderCache: _renderCache,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _renderCache.dispose();
    super.dispose();
  }
}

class _TerminalScopeInherited extends InheritedWidget {
  final TerminalRenderCache renderCache;

  const _TerminalScopeInherited({
    required this.renderCache,
    required super.child,
  });

  @override
  bool updateShouldNotify(_TerminalScopeInherited oldWidget) {
    return !identical(renderCache, oldWidget.renderCache);
  }
}
