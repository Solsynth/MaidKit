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

- Keep the app wrapped in `MaidKitWindowScaffold`, which uses Island's `DesktopWindowFrame` for desktop-native chrome.
- Preserve desktop window initialization in `main.dart` when changing startup code.
- The main workspace is one pane-tab shell: `SessionsWorkspace` renders `terminalTabsProvider`'s panes and per-pane tab strips. Every destination — the servers dashboard, terminals, file management, file editors, agent chats, assets, projects, MaidCafe cloud, settings — is a `SessionTab` in that strip. Do not reintroduce a navigation rail, bottom bar, or `AutoTabsRouter`.
- `AppRouter` owns a single route (`ServerWorkspacePage`). Detail pages opened from a tab are pushed with `TabNavigator.of(context).push(...)` so they stay inside that tab's own stack; never call `context.router.push` from inside the workspace.
- App-level shortcuts live in the window shell, not in the workspace: the pane tab strip and the terminal are not always the focus owner. Cmd/Ctrl+W closes the focused pane tab — route it through `TerminalTabsNotifier.close` so the close guard can ask before abandoning a running terminal task, a replying agent chat, or a dirty file editor.
- Reference `../SolarNetwork/Island/lib/shared/widgets/app_scaffold.dart` when extending window behaviour.

## UI guidelines

- Make the interface quiet, functional, and desktop-oriented. Prefer standard Material 3 components and the Island foundation helpers over custom chrome.
- Use calm theme colors already defined in `app.dart`; do not introduce gradients, glows, glass effects, decorative hero sections, or fake dashboards.
- Avoid oversized rounded corners, pill-heavy navigation, large shadows, and unnecessary cards.
- Keep spacing on a simple 4/8/12/16/24/32 scale. Use borders and contrast for hierarchy rather than effects.
- Do not add a page-level app bar to the tab workspace unless there is a clear product requirement. The window title bar and tab navigation provide the surrounding chrome.
- Keep responsive behavior intentional. The workspace has no rail or bottom bar any more; its breakpoint is the pane tab strip: below 768 logical pixels of pane width only the focused tab keeps its title and the others collapse to their icon, animated rather than snapped.

## Checks

Run formatting, code generation when annotations or Drift schema change, then `flutter analyze` and `flutter test`.
