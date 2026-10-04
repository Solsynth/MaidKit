# MaidKit architecture

MaidKit is a desktop-first Flutter application for managing SSH servers.

## Stack

- **Flutter + Material 3** for the application UI.
- **Riverpod** and **flutter_hooks** for state, lifecycle-aware UI state, and dependency wiring.
- **auto_route** for declarative, nested navigation. Generated route files live beside their router and must not be edited manually.
- **Drift** for the local SQLite database. The current schema begins with saved server definitions.
- **dartssh2** for SSH client connections and remote command execution.
- **MaidCafe daemon over HTTP/SSE/WebSocket** for the optional daemon layer:
  host statistics, activity history, and terminals reach a daemon without an SSH
  session (`lib/servers/maidcafe_stats.dart`, `maidcafe_stream.dart`,
  `maidcafe_terminal_connection_manager.dart`). This is the only route that
  works in a browser build.
- **island_ui_foundation** from the Solian Git repository for the desktop window frame and reusable responsive UI utilities.
- **window_manager** for native desktop window setup, with **screen_retriever** for the display layout saved window bounds are restored against.

## Source layout

Features are flat and live directly under `lib/<feature>/`. Avoid `data`, `domain`, `presentation`, or similar subfolders unless a feature grows enough to make one necessary.

```
lib/
  app.dart                         # MaterialApp.router and theme
  main.dart                        # Bootstrap and desktop window setup
  data/local/                      # App-wide Drift database
  routing/                         # auto_route configuration and generated routes
  servers/                         # Server feature pages, providers, repository
  shared/presentation/             # App-wide reusable UI shell
```

## Navigation

`AppRouter` owns a single route: `ServerWorkspacePage`, the pane-tab workspace
(`SessionsWorkspace`). There is no tab router and no navigation rail — every
destination is a `SessionTab` in the pane tab strip
(`servers/terminal_tabs_provider.dart`): the servers dashboard, terminals, file
management, file editors, agent chats, assets, deployment projects, the MaidCafe
cloud console and settings.

A tab that can open a detail page (dashboard, server detail, assets, projects,
MaidCafe cloud, settings) wraps its content in a `TabNavigator`
(`shared/presentation/tab_navigator.dart`). Push details with
`TabNavigator.of(context).push(SomeDetailPage(...))` so the page lands inside the
tab that opened it and survives switching tabs and panes; pop them with
`TabNavigator.of(context).pop()`. `context.router` is only the root navigator and
must not be used for detail pages.

The pane tab strip is the workspace's title bar. On a pane narrower than 768
logical pixels only the focused tab draws its title, and that title expands out
of its icon and collapses back instead of snapping the strip's layout, so
background tabs stay icon-sized. The window shell
(`shared/presentation/maidkit_window_scaffold.dart`) owns the app-level
shortcuts — Shift+Tab opens the session-actions palette and Cmd/Ctrl+W closes
the focused pane tab — because focus may sit outside the workspace when they are
pressed. Closing routes through `TerminalTabsNotifier.close`, which asks first
when the tab is still working: a terminal running a task, an agent chat still
replying, or a dirty file editor.

When changing pages:

1. Add the destination or detail widget; only `ServerWorkspacePage` is a
   `@RoutePage()`.
2. Add a `SessionTab` subclass plus an `open*` method on `TerminalTabsNotifier`
   for a new destination, and render it in `_SessionTabBody`.
3. Run `dart run build_runner build` if routes changed.
4. Never hand-edit `*.g.dart` or `*.gr.dart` files.

## Persistence

`AppDatabase` in `lib/data/local/app_database.dart` is the single Drift database. Keep database tables and migrations there. Feature repositories should expose feature-focused queries, while Riverpod providers construct repositories and expose UI-friendly streams or async values.

## Validation

Run these before handing off changes:

```sh
dart format lib test
dart run build_runner build
flutter analyze
flutter test
```
