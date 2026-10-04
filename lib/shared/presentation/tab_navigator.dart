import 'package:material_ui/material_ui.dart';

/// One pushed page inside a session tab.
class TabNavigatorPage {
  TabNavigatorPage(this.child, {this.debugLabel}) : key = UniqueKey();

  final Widget child;

  /// Shown in debug output only; the pane tab strip keeps the tab's own label.
  final String? debugLabel;

  /// Stable across rebuilds so the page keeps its [State] while it is on the
  /// stack, even when a page below it is popped.
  final LocalKey key;
}

/// The pushed-page stack of a single session tab.
///
/// A tab hosts its own detail stack so a detail page opened from one tab stays
/// inside that tab: switching panes or tabs never pops it, and the tab's close
/// button throws the whole stack away with the tab.
class TabNavigatorController extends ChangeNotifier {
  TabNavigatorController(this.tabId);

  final String tabId;

  final List<TabNavigatorPage> _pages = [];

  List<TabNavigatorPage> get pages => List.unmodifiable(_pages);

  bool get canPop => _pages.isNotEmpty;

  void push(Widget child, {String? debugLabel}) {
    _pages.add(TabNavigatorPage(child, debugLabel: debugLabel));
    notifyListeners();
  }

  /// Removes the top page. No-op at the tab's own content.
  void pop() {
    if (_pages.isEmpty) return;
    _pages.removeLast();
    notifyListeners();
  }

  /// Pops the top page when there is one; reports whether anything was popped.
  bool maybePop() {
    if (_pages.isEmpty) return false;
    pop();
    return true;
  }
}

/// Live stacks by tab id.
///
/// Keyed by tab id like the pane view keys, so a stack follows its tab across
/// pane splits, drags between panes, and reorders. Controllers are removed when
/// their tab closes; they are deliberately not disposed there because the tab
/// subtree is still listening until the next build.
final Map<String, TabNavigatorController> _controllers = {};

TabNavigatorController tabNavigatorFor(String tabId) =>
    _controllers.putIfAbsent(tabId, () => TabNavigatorController(tabId));

void releaseTabNavigator(String tabId) => _controllers.remove(tabId);

/// Exposes a tab's [TabNavigatorController] to everything built inside it.
class TabNavigatorScope extends InheritedNotifier<TabNavigatorController> {
  const TabNavigatorScope({
    super.key,
    required TabNavigatorController controller,
    required super.child,
  }) : super(notifier: controller);

  static TabNavigatorController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabNavigatorScope>()?.notifier;

  static TabNavigatorController of(BuildContext context) {
    final controller = maybeOf(context);
    if (controller == null) {
      throw FlutterError(
        'TabNavigator.of() was called with a context that does not contain a '
        'TabNavigator. Detail pages must be pushed from inside a session tab '
        'that wraps its content in a TabNavigator.',
      );
    }
    return controller;
  }
}

/// Hosts the pushed-page stack of the session tab [tabId].
///
/// [builder] builds the tab's own content, which is the bottom of the stack:
/// detail pages pushed from anywhere inside it land above it and stay inside
/// the tab.
class TabNavigator extends StatelessWidget {
  const TabNavigator({super.key, required this.tabId, required this.builder});

  final String tabId;
  final WidgetBuilder builder;

  /// The stack of the nearest enclosing session tab.
  static TabNavigatorController of(BuildContext context) =>
      TabNavigatorScope.of(context);

  static TabNavigatorController? maybeOf(BuildContext context) =>
      TabNavigatorScope.maybeOf(context);

  @override
  Widget build(BuildContext context) {
    final controller = tabNavigatorFor(tabId);
    return TabNavigatorScope(
      controller: controller,
      child: _TabNavigatorView(
        controller: controller,
        rootKey: _rootPageKey(tabId),
        builder: builder,
      ),
    );
  }
}

LocalKey _rootPageKey(String tabId) => ValueKey<Object>('tab-root-$tabId');

class _TabNavigatorView extends StatelessWidget {
  const _TabNavigatorView({
    required this.controller,
    required this.rootKey,
    required this.builder,
  });

  final TabNavigatorController controller;
  final LocalKey rootKey;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final pages = controller.pages;
        return Navigator(
          pages: [
            MaterialPage<void>(
              key: rootKey,
              child: Builder(builder: builder),
            ),
            for (final page in pages)
              MaterialPage<void>(
                key: page.key,
                name: page.debugLabel,
                child: page.child,
              ),
          ],
          onDidRemovePage: (page) {
            // A back button or a system back gesture removed a page from the
            // navigator; mirror that on the stack that drives it.
            if (page.key != rootKey) controller.pop();
          },
        );
      },
    );
  }
}
