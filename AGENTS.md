# MaidKit contributor guidance

Read `docs/architecture.md` before making structural changes.

## Tech stack rules

- Use Material 3 (`ThemeData.useMaterial3`) for standard controls and theming.
- Use `hooks_riverpod` for state management. Prefer `ConsumerWidget` for read-only reactive views and `HookConsumerWidget` only when hooks are needed.
- Keep feature code directly under `lib/<feature>/`; do not introduce deep `presentation`, `domain`, or `data` folders by default.
- Use `auto_route` for navigation. Add route annotations/configuration and regenerate code with `dart run build_runner build`; never edit generated `*.g.dart` or `*.gr.dart` files.
- Store persistent data in Drift and place app-wide schema changes in `lib/data/local/app_database.dart`.
- Use `dartssh2` for SSH behavior. Do not put credentials or private keys in Drift; introduce a secure credential store when authentication is implemented.

## Window and layout rules

- Keep the app wrapped in `MaidKitWindowScaffold`. On desktop the window is borderless and the workspace's single tab bar is the window title bar; `shared/presentation/window_chrome.dart` owns the drag area, window buttons and macOS traffic-light alignment. Do not add a second bar above it.
- Preserve desktop window initialization in `main.dart` when changing startup code.
- The main workspace is one tab shell: `SessionsWorkspace` (`lib/servers/tabs_screen.dart`) renders `terminalTabsProvider` under **one** workspace tab bar. A `WorkspaceTab` is a document that owns its panes and its own `SessionLayout` tree; its panes hold `SessionTab` content instances (the servers dashboard, terminals, file management, file editors, agent chats, assets, projects, MaidCafe cloud, settings). Do not reintroduce a navigation rail, bottom bar, per-pane tab strips, or `AutoTabsRouter`.
- The bar lists tabs, not panes: one entry per workspace tab, printing how many panes it is split into. A split adds a pane to the current tab (`splitSelectedTab`), so the tab keeps its place and the layout ratio is stored per tab. A pane shows exactly one content viewport — no strip of its own — and each pane is one `MaidKitPanel`; the gutter between panels separates panes, so never draw a rule between them. Every tab stays mounted with only the selected one visible, so terminals keep scrollback across switches. Terminals and agent chats own a single live renderer, so splitting them leaves the new pane empty for a fresh session; a tab's id is its bar identity, so content instances that can be duplicated (file managers, editors, server details) get fresh ids while destinations stay singletons.
- `AppRouter` owns a single route (`ServerWorkspacePage`). Detail pages opened from a tab are pushed with `TabNavigator.of(context).push(...)` so they stay inside that tab's own stack; never call `context.router.push` from inside the workspace.
- App-level shortcuts live in the window shell, not in the workspace: the tab bar and the terminal are not always the focus owner. Cmd/Ctrl+W closes the selected tab, every pane it owns — route it through `TerminalTabsNotifier.closeTab` so the close guard can ask before abandoning a running terminal task, a replying agent chat, or a dirty file editor.
- Reference `../SolarNetwork/Island/lib/shared/widgets/app_scaffold.dart` when extending window behaviour.

## UI guidelines

- Make the interface quiet, functional, and desktop-oriented. Prefer standard Material 3 components and the Island foundation helpers over custom chrome.
- Use calm theme colors already defined in `app.dart`; do not introduce gradients, glows, glass effects, decorative hero sections, or fake dashboards.
- Avoid oversized rounded corners, pill-heavy navigation, large shadows, and unnecessary cards.
- Keep spacing on a simple 4/8/12/16/24/32 scale. Use borders and contrast for hierarchy rather than effects.
- Do not add a page-level app bar to the tab workspace unless there is a clear product requirement. The window title bar and tab navigation provide the surrounding chrome.
- Keep responsive behavior intentional. The workspace has no rail or bottom bar any more; its breakpoint is the workspace tab bar: below 768 logical pixels only the selected entry keeps its title and the others collapse to their icon (a split tab keeps its pane count), animated rather than snapped.

## Checks

Run formatting, code generation when annotations or Drift schema change, then `flutter analyze` and `flutter test`.
