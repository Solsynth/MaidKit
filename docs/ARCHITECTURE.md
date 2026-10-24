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
  works in a browser build, and on a native build it is a fallback rather than
  the default: for a server that can also do SSH, a connected SSH session owns
  statistics, activity, container and management actions, while the daemon
  answers only until a session is live (and the statistics poll stands aside
  while one is). `lib/servers/session_lookup.dart` holds that rule —
  `sshPreferredOverDaemon` reads the session feed, whose
  `SessionTransport` tag is what keeps a daemon terminal from passing for an SSH
  session. Features SSH has no implementation for keep the daemon outright: the
  daemon console, container update checks, the compose stack registry,
  watched-process history, and the daemon's health score.
- **Host metrics have one app-wide switch.** `serverMetricsEnabledProvider`
  (`lib/servers/server_providers.dart`, persisted by
  `MetricsRefreshPreferences`) turns collection off for every server at once.
  Off means no scheduler serves a host, `SshConnectionManager` skips its metric
  and system-information commands and refuses the Activity tab's probe, and
  every surface shows a "metrics are turned off" placeholder instead of a
  reading — connections, terminals and process listings keep working.
- **Server rows are independent of transports.** `connectionType` names what the
  row *is* — `ssh`, `serial`, or `maidcafe` — and a daemon route can sit on any
  of them as a second way in. Only a row typed `maidcafe` is daemon-only; a row
  typed `ssh` always keeps its SSH route, and the daemon is what covers it when
  no session is up.
- **island_ui_foundation** from the Solian Git repository for reusable responsive UI utilities and sheets. Its `DesktopWindowFrame` is not used: `shared/presentation/window_chrome.dart` owns the window chrome.
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

`AppRouter` owns a single route: `ServerWorkspacePage`, the tab workspace
(`SessionsWorkspace` in `servers/tabs_screen.dart`). There is no tab router
and no navigation rail — every destination is content inside a tab, mounted
from `servers/terminal_tabs_provider.dart`: the servers dashboard, terminals,
file management, file editors, agent chats, assets, deployment projects, the
MaidCafe cloud console and settings.

A tab that can open a detail page (dashboard, server detail, assets, projects,
MaidCafe cloud, settings) wraps its content in a `TabNavigator`
(`shared/presentation/tab_navigator.dart`). Push details with
`TabNavigator.of(context).push(SomeDetailPage(...))` so the page lands inside the
tab that opened it and survives switching tabs and panes; pop them with
`TabNavigator.of(context).pop()`. `context.router` is only the root navigator and
must not be used for detail pages.

The workspace has one tab bar, not one per pane. A tab is a document that
owns its panes: `WorkspaceTab` carries a `SessionLayout` tree, the panes it
mounts (`TabPane`), and which pane has focus. Splitting adds a pane to the
current tab rather than a second tab, so a split terminal keeps its one bar
entry with a pane count and remembers its own divider ratio while other tabs
open single-pane. The bar lists tabs left to right, so the workspace reads as
one set of documents with several viewports rather than as several independent
windows. On desktop that bar *is* the window title bar: the window is
borderless, the bar occupies the native title bar row
(`kMaidKitTitleBarHeight`, 40 pt), and there is no second bar above it. The bar
reserves the macOS traffic-light inset on its leading edge, moves the window
when dragged from empty bar space, and draws the minimize/maximize/close
buttons itself where the OS does not (Windows, Linux). `MainFlutterWindow.swift`
re-centers the macOS traffic lights on the bar whenever the Dart side reports a
new effective height, so they stay aligned across UI-scale changes. While no
bar exists — the locked vault, an empty workspace — `MaidKitWindowScaffold`
draws a standalone `MaidKitTitleBar` instead, so the window is never
draggable-less. On a window narrower than 768 logical pixels only the selected
tab draws its title, and that title expands out of its icon and collapses back
instead of snapping the bar's layout, so background tabs stay icon-sized.

Panes below the bar are separate cards on the workspace paper: they are
separated by a gutter, with no rule drawn between them, and the gutter is the
drag band that resizes the split. Each pane ends in its own band — the
terminal status bar (`AnimatedTerminalStatusBar`) when that pane shows a
terminal, nothing otherwise — so a split reads out every terminal it shows, not
just the focused one. A split's focused pane carries a close control in its
corner, since panes no longer have strips to put one in.

A pane shows exactly one content instance. Every tab stays mounted, with only
the selected one visible, so switching tabs keeps a terminal's scrollback, an
editor's scroll position and a file browser's listing. Splitting duplicates what
can be mounted twice — a file manager, a file editor, a server detail page —
under fresh content ids so the bar still shows one entry; a terminal and an
agent chat own a single live renderer, so their new pane starts empty for a
fresh session instead. `forkSessionTab` holds that rule.

The window shell
(`shared/presentation/maidkit_window_scaffold.dart`) owns the app-level
shortcuts — Shift+Tab opens the session-actions palette and Cmd/Ctrl+W closes
the selected tab — because focus may sit outside the workspace when they are
pressed. Closing routes through `TerminalTabsNotifier.closeTab`, which takes
every pane the tab owns and asks first when any of them is still working: a
terminal running a task, an agent chat still replying, or a dirty file editor.

The saved workspace (`servers/workspace_snapshot.dart`, version 2) stores one
layout and one pane map per tab. Version 1 saves — a single workspace layout
with tab lists frozen inside each pane — are converted on load, one tab per
pane tab, so an older session still reopens.

When changing pages:

1. Add the destination or detail widget; only `ServerWorkspacePage` is a
   `@RoutePage()`.
2. Add a `SessionTab` subclass plus an `open*` method on `TerminalTabsNotifier`
   for a new destination, and render it in `_SessionTabBody`. Teach
   `forkSessionTab` how a split should duplicate it, or list it among the
   single-renderer kinds that split into an empty pane.
3. Run `dart run build_runner build` if routes changed.
4. Never hand-edit `*.g.dart` or `*.gr.dart` files.

## Long-running tasks

`shared/presentation/task_progress.dart` owns every task the user starts and
waits on: `TaskProgressNotifier` queues one `AppTaskRequest` at a time, samples
speed, throttles progress to 250 ms, and hands each action a `TaskControl` for
pause/cancel and a report callback. `TaskProgressBar` in the window shell
renders the queue over the app, and tapping it opens the full list, so a
background transfer is visible and cancellable from any tab.

A feature submits work rather than building its own queue: the file transfer
path in `servers/file_management_tab.dart` is one `AppTaskRequest` per copy,
and the tab tracks the returned ids only to mark itself busy and to cancel its
work when the tab closes. Throwing `TaskSkipped` settles a task quietly (no
success callback); throwing `TaskCancelled` — normally from
`TaskControl.throwIfCancelled` — settles it as cancelled.

## Theming

`lib/theme.dart` is the single source of design decisions, ported from Island's
`lib/core/theme.dart`. Feature widgets must depend on it rather than inventing
local colour schemes or chrome.

- **Tokens.** `MaidKitSpace` (spacing), `MaidKitRadius` (corner radii) and
  `MaidKitInsets` (reusable insets) are the scales. If a value is not on a
  scale it is a one-off, not a system decision — prefer the nearest token.
- **Surfaces.** `createMaidKitTheme` rebuilds only the *neutral ramp* from the
  seed (`_seedPaper`), keeping accent roles as `ColorScheme.fromSeed` produced
  them. Neutrals are tinted toward the seed's own hue, so a teal seed reads as
  cool paper and a clay seed as warm paper.
- **Tone over outlines.** Cards, sections and the workspace tab bar separate
  themselves with a deeper surface tone, not borders or shadows. One paper
  runs through the app: `scaffoldBackgroundColor`/`canvasColor` are
  `surfaceContainerLow`, the same tone as the tab bar, so the locked vault, the
  window frame and every top-level page share it. The bar's selected entry
  paints `surface`. Panes are `MaidKitPanel` cards that step off the paper by
  exactly one tone: the focused pane is `surfaceContainer` and an unfocused one
  is `surfaceContainerLow`, so it sits back down on the paper and the gutter
  alone divides the split. A panel republishes its own tone as the theme paper
  for everything inside it, so a tab body that paints a surface — a page
  scaffold, a pushed detail page, a file editor — fills the card instead of
  cutting a paper-coloured hole in it, and cards inside step one tone further
  (`surfaceContainerHigh`).
- **Inputs are tonal first.** A soft fill (`surfaceContainerHigh` at 70%)
  defines a field; only focus and error draw an edge.
- **Placeholders.** Every empty or failed surface renders through
  `MaidKitEmptyState` (`lib/shared/presentation/empty_state.dart`). One shape
  everywhere: `compact: true` inside panels, sheets and overlays, and
  `iconColor` when the placeholder is an error.

`material_ui` and Flutter's own Material library expose separate `Theme`
inherited widgets, so the window chrome — which reads the Flutter SDK theme —
would otherwise fall back to Flutter defaults. `maidkit_window_scaffold.dart`
therefore copies the app's colour scheme into a `flutter.ThemeData` (rather
than regenerating one from the seed) so both libraries agree on the paper ramp.

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
